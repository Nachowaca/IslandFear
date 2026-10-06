using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates scattered object points using Mitchell's Best-Candidate blue noise algorithm.
/// </summary>
public partial class ScatterNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public ScatterNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="ScatterNode"/> class.
    /// </summary>
    public ScatterNode()
    {
        Inputs.Add(new Port("density_mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    private struct LcgRandom
    {
        private uint _state;
        public LcgRandom(uint seed)
        {
            _state = seed;
        }
        public float NextFloat()
        {
            _state = (_state * 1103515245 + 12345) & 0x7fffffff;
            return (float)_state / 0x7fffffff;
        }
    }

    /// <summary>
    /// Evaluates the Mitchell's best-candidate scatter algorithm.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float density = AssociatedResource != null ? AssociatedResource.Density : 0.5f;
        int seed = AssociatedResource != null ? AssociatedResource.Seed : 1;
        int candidatesCount = AssociatedResource != null ? AssociatedResource.Candidates : 5;
        float minSpacing = AssociatedResource != null ? AssociatedResource.MinSpacing : 2.0f;

        // Fetch upstream density mask matrix (optional)
        HeightMatrix densityMask = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            densityMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        var instanceSet = new InstanceSet();

        // Calculate N points to place based on density and chunk area in world units
        float area = ctx.WorldSize * ctx.WorldSize;
        int n = Math.Max(1, (int)MathF.Floor(density * area / 100.0f));

        // Deterministic chunk-specific seed
        uint chunkSeed = (uint)(seed ^ ctx.Coord.GetHashCode());
        var rand = new LcgRandom(chunkSeed);

        // Core chunk bounds in world space
        float xMin = ctx.WorldOrigin.X;
        float xMax = ctx.WorldOrigin.X + ctx.WorldSize;
        float zMin = ctx.WorldOrigin.Z;
        float zMax = ctx.WorldOrigin.Z + ctx.WorldSize;

        var scatteredPoints = new List<Vector3>();

        // Spatial hash grid for O(1) candidate closest distance lookup
        float cellSize = minSpacing > 0.1f ? minSpacing : 1.0f;
        var grid = new Dictionary<long, List<Vector3>>();

        void AddToGrid(Vector3 p)
        {
            int cx = (int)MathF.Floor(p.X / cellSize);
            int cz = (int)MathF.Floor(p.Z / cellSize);
            long key = ((long)cx << 32) | (uint)cz;
            if (!grid.TryGetValue(key, out var list))
            {
                list = new List<Vector3>();
                grid[key] = list;
            }
            list.Add(p);
        }

        float FindClosestPointDistanceSq(Vector3 candidate)
        {
            if (scatteredPoints.Count == 0) return float.MaxValue;

            int cellX = (int)MathF.Floor(candidate.X / cellSize);
            int cellZ = (int)MathF.Floor(candidate.Z / cellSize);

            float dClosestSq = float.MaxValue;
            int ring = 0;
            bool foundAny = false;

            while (!foundAny || (ring * cellSize * ring * cellSize < dClosestSq))
            {
                int minX = cellX - ring;
                int maxX = cellX + ring;
                int minZ = cellZ - ring;
                int maxZ = cellZ + ring;

                for (int cx = minX; cx <= maxX; cx++)
                {
                    for (int cz = minZ; cz <= maxZ; cz++)
                    {
                        if (ring > 0 && cx > minX && cx < maxX && cz > minZ && cz < maxZ)
                        {
                            continue;
                        }

                        long key = ((long)cx << 32) | (uint)cz;
                        if (grid.TryGetValue(key, out var list))
                        {
                            foreach (var p in list)
                            {
                                float dx = candidate.X - p.X;
                                float dz = candidate.Z - p.Z;
                                float distSq = dx * dx + dz * dz;
                                if (distSq < dClosestSq)
                                {
                                    dClosestSq = distSq;
                                    foundAny = true;
                                }
                            }
                        }
                    }
                }
                ring++;
                if (ring > 50 + scatteredPoints.Count)
                {
                    break;
                }
            }

            return dClosestSq;
        }

        // Place the first point
        Vector3 firstPoint = Vector3.Zero;
        bool firstPlaced = false;

        if (densityMask != null)
        {
            // If we have a mask, try to find a valid starting point with non-zero density
            for (int attempt = 0; attempt < 50; attempt++)
            {
                float rx = rand.NextFloat();
                float rz = rand.NextFloat();
                float x = xMin + rx * (xMax - xMin);
                float z = zMin + rz * (zMax - zMin);
                Vector3 p = new Vector3(x, ctx.WorldOrigin.Y, z);

                float maskVal = CoordinateMapping.SampleBilinearWorld(densityMask, p, ctx);
                if (maskVal > 0.01f)
                {
                    firstPoint = p;
                    firstPlaced = true;
                    break;
                }
            }
        }
        else
        {
            float rx = rand.NextFloat();
            float rz = rand.NextFloat();
            float x = xMin + rx * (xMax - xMin);
            float z = zMin + rz * (zMax - zMin);
            firstPoint = new Vector3(x, ctx.WorldOrigin.Y, z);
            firstPlaced = true;
        }

        if (firstPlaced)
        {
            scatteredPoints.Add(firstPoint);
            AddToGrid(firstPoint);
            uint hash = (uint)BitConverter.SingleToInt32Bits(firstPoint.X) ^ (uint)BitConverter.SingleToInt32Bits(firstPoint.Z) ^ chunkSeed;
            int id = scatteredPoints.Count - 1;
            instanceSet.Add(new InstanceTransform(firstPoint, Quaternion.Identity, Vector3.One, 0, hash, id));
        }

        float minSpacingSq = minSpacing * minSpacing;

        // Place subsequent points using Mitchell's Best-Candidate
        for (int i = 1; i < n; i++)
        {
            int C = Math.Max(1, candidatesCount);
            Vector3 bestCandidate = Vector3.Zero;
            float maxDFinalSq = -1f;
            float bestClosestSq = -1f;
            bool hasValidCandidate = false;

            for (int k = 0; k < C; k++)
            {
                float rx = rand.NextFloat();
                float rz = rand.NextFloat();
                float cx = xMin + rx * (xMax - xMin);
                float cz = zMin + rz * (zMax - zMin);
                Vector3 candidate = new Vector3(cx, ctx.WorldOrigin.Y, cz);

                // 1. Find squared distance to closest already-scattered point using spatial hash
                float dClosestSq = FindClosestPointDistanceSq(candidate);

                // 2. Find squared distance to tile borders (with factor of 4 reflection scaling)
                float dbXMin = 4.0f * (cx - xMin) * (cx - xMin);
                float dbZMin = 4.0f * (cz - zMin) * (cz - zMin);
                float dbXMax = 4.0f * (xMax - cx) * (xMax - cx);
                float dbZMax = 4.0f * (zMax - cz) * (zMax - cz);
                float dBorderSq = MathF.Min(MathF.Min(dbXMin, dbZMin), MathF.Min(dbXMax, dbZMax));

                // 3. Compute baseline squared distance
                float dBaseSq = MathF.Min(dClosestSq, dBorderSq);

                // 4. Multiply by density mask
                float pMask = 1.0f;
                if (densityMask != null)
                {
                    pMask = CoordinateMapping.SampleBilinearWorld(densityMask, candidate, ctx);
                }

                float dFinalSq = dBaseSq * pMask;

                if (dFinalSq > 0.0001f && dFinalSq > maxDFinalSq)
                {
                    maxDFinalSq = dFinalSq;
                    bestCandidate = candidate;
                    bestClosestSq = dClosestSq;
                    hasValidCandidate = true;
                }
            }

            if (hasValidCandidate)
            {
                // Respect min_spacing parameter
                if (bestClosestSq >= minSpacingSq)
                {
                    scatteredPoints.Add(bestCandidate);
                    AddToGrid(bestCandidate);
                    uint hash = (uint)BitConverter.SingleToInt32Bits(bestCandidate.X) ^ (uint)BitConverter.SingleToInt32Bits(bestCandidate.Z) ^ chunkSeed ^ (uint)i;
                    int id = scatteredPoints.Count - 1;
                    instanceSet.Add(new InstanceTransform(bestCandidate, Quaternion.Identity, Vector3.One, 0, hash, id));
                }
            }
        }

        return instanceSet;
    }
}

#endregion
