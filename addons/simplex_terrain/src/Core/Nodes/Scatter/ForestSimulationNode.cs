using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that runs a multi-year cellular forest simulation over the chunk's coordinate grid.
/// </summary>
public partial class ForestSimulationNode : TerrainNode
{
    public ForestSimulationNodeResource AssociatedResource { get; set; }

    public ForestSimulationNode()
    {
        Inputs.Add(new Port("fertility_mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int years = AssociatedResource != null ? Math.Max(0, AssociatedResource.Years) : 20;
        float seedRate = AssociatedResource != null ? AssociatedResource.SeedRate : 0.05f;
        float survivalThreshold = AssociatedResource != null ? AssociatedResource.SurvivalThreshold : 0.3f;
        int crowdingRadius = AssociatedResource != null ? Math.Max(1, AssociatedResource.CrowdingRadius) : 2;
        float density = AssociatedResource != null ? Math.Max(1.0f, AssociatedResource.Density) : 1000.0f;
        int seedVal = AssociatedResource != null ? AssociatedResource.Seed : 42;
        float maxLifespan = AssociatedResource != null ? AssociatedResource.MaxLifespan : 30.0f;
        int crowdingThreshold = AssociatedResource != null ? AssociatedResource.CrowdingThreshold : 8;

        HeightMatrix fertilityMask = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            fertilityMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        // Determine simulation cell size based on target tree density: deltaCell = 1000 / sqrt(density) (Ref: §9.A)
        float deltaCell = 1000.0f / MathF.Sqrt(density);

        // Map padded heightmap size to world-space meters to size the simulation grid
        float cellSize = ctx.WorldSize / ctx.Resolution;
        float totalSizeMeters = ctx.PaddedSize * cellSize;

        int gridWidth = (int)MathF.Ceiling(totalSizeMeters / deltaCell);
        int gridHeight = gridWidth;

        // Ensure we have at least a 1x1 grid
        gridWidth = Math.Max(1, gridWidth);
        gridHeight = Math.Max(1, gridHeight);

        // Simulation grid containing tree age (0.0 means empty)
        float[,] gridPrev = new float[gridWidth, gridHeight];
        float[,] gridNext = new float[gridWidth, gridHeight];

        // Core and padded chunk coordinates in world space
        Vector3 paddedOrigin = ctx.WorldOrigin - new Vector3(ctx.Padding * cellSize, 0f, ctx.Padding * cellSize);

        // Add chunk-specific modifier to the seed
        int chunkSeed = seedVal ^ ctx.Coord.GetHashCode();

        // Multi-year simulation loop (Ref: §9.B)
        for (int t = 1; t <= years; t++)
        {
            // Reset gridNext
            Array.Clear(gridNext, 0, gridNext.Length);

            // Pass 1: Tree aging, natural lifespan death, soil survival, and crowding checks
            for (int x = 0; x < gridWidth; x++)
            {
                for (int z = 0; z < gridHeight; z++)
                {
                    float age = gridPrev[x, z];
                    if (age <= 0.0f)
                    {
                        continue;
                    }

                    // 1. Age increment
                    float newAge = age + 1.0f;

                    // 2. Lifespan death (dies if > maxLifespan years)
                    if (newAge > maxLifespan)
                    {
                        continue;
                    }

                    // 3. Soil fertility survival check
                    Vector3 worldPos = GetWorldPos(x, z, deltaCell, paddedOrigin);
                    float fert = 1.0f;
                    if (fertilityMask != null)
                    {
                        fert = CoordinateMapping.SampleBilinearWorld(fertilityMask, worldPos, ctx);
                    }

                    if (fert < survivalThreshold)
                    {
                        continue; // Fertility too low, tree dies
                    }

                    // Stochastic survival check against 0.95 * fert
                    float rSurv = GetDeterministicFloat(x, z, t, chunkSeed);
                    if (rSurv > 0.95f * fert)
                    {
                        continue; // Died stochastically
                    }

                    // 4. Crowding check
                    int neighborCount = 0;
                    for (int dx = -crowdingRadius; dx <= crowdingRadius; dx++)
                    {
                        for (int dz = -crowdingRadius; dz <= crowdingRadius; dz++)
                        {
                            if (dx == 0 && dz == 0) continue;
                            int nx = x + dx;
                            int nz = z + dz;
                            if (nx >= 0 && nx < gridWidth && nz >= 0 && nz < gridHeight)
                            {
                                if (gridPrev[nx, nz] > 0.0f)
                                {
                                    neighborCount++;
                                }
                            }
                        }
                    }

                    if (neighborCount > crowdingThreshold)
                    {
                        continue; // Crowding death
                    }

                    // Survived all checks
                    gridNext[x, z] = newAge;
                }
            }

            // Pass 2: Reproduction dispersal and spontaneous seeding
            for (int x = 0; x < gridWidth; x++)
            {
                for (int z = 0; z < gridHeight; z++)
                {
                    Vector3 worldPos = GetWorldPos(x, z, deltaCell, paddedOrigin);
                    float fert = 1.0f;
                    if (fertilityMask != null)
                    {
                        fert = CoordinateMapping.SampleBilinearWorld(fertilityMask, worldPos, ctx);
                    }

                    if (fert < survivalThreshold)
                    {
                        continue;
                    }

                    // Seed dispersal from mature trees (age >= 5 in gridPrev)
                    float oldAge = gridPrev[x, z];
                    if (oldAge >= 5.0f && gridNext[x, z] > 0.0f) // Mature and survived this year
                    {
                        // Check if mature tree successfully produces seeds
                        float rRep = GetDeterministicFloat(x, z, t, chunkSeed + 1000);
                        if (rRep < seedRate)
                        {
                            // Determine radial dispersal direction and distance (Ref: §9.C)
                            float theta = GetDeterministicFloat(x, z, t, chunkSeed + 2000) * MathF.PI * 2.0f;
                            float normDist = GetDeterministicFloat(x, z, t, chunkSeed + 3000);
                            
                            // Dispersal distance in cell units, up to 5 cells
                            float dCell = normDist * 5.0f + 1.0f;

                            int tx = (int)MathF.Floor(x + MathF.Sin(theta) * dCell);
                            int tz = (int)MathF.Floor(z + MathF.Cos(theta) * dCell);

                            if (tx >= 0 && tx < gridWidth && tz >= 0 && tz < gridHeight)
                            {
                                // Seed germinates if target cell is currently empty in the new grid
                                if (gridNext[tx, tz] < 0.5f)
                                {
                                    Vector3 tPos = GetWorldPos(tx, tz, deltaCell, paddedOrigin);
                                    float tFert = 1.0f;
                                    if (fertilityMask != null)
                                    {
                                        tFert = CoordinateMapping.SampleBilinearWorld(fertilityMask, tPos, ctx);
                                    }

                                    if (tFert >= survivalThreshold)
                                    {
                                        gridNext[tx, tz] = 1.0f; // Seed germinated!
                                    }
                                }
                            }
                        }
                    }

                    // Spontaneous seeding for empty cells (Ref: NODE_SPEC_SHEET.md)
                    if (gridNext[x, z] < 0.5f)
                    {
                        float rSeed = GetDeterministicFloat(x, z, t, chunkSeed + 4000);
                        if (rSeed < seedRate * fert)
                        {
                            gridNext[x, z] = 1.0f; // Spontaneous germination
                        }
                    }
                }
            }

            // Copy next state to prev grid for next year
            Array.Copy(gridNext, gridPrev, gridNext.Length);
        }

        // Export surviving trees within core chunk boundaries
        var instanceSetOut = new InstanceSet();
        float xMin = ctx.WorldOrigin.X;
        float xMax = ctx.WorldOrigin.X + ctx.WorldSize;
        float zMin = ctx.WorldOrigin.Z;
        float zMax = ctx.WorldOrigin.Z + ctx.WorldSize;

        int nextId = 1;
        for (int x = 0; x < gridWidth; x++)
        {
            for (int z = 0; z < gridHeight; z++)
            {
                if (gridPrev[x, z] > 0.0f)
                {
                    Vector3 pos = GetWorldPos(x, z, deltaCell, paddedOrigin);

                    // Output only instances that reside within the core chunk boundaries
                    if (pos.X >= xMin && pos.X < xMax && pos.Z >= zMin && pos.Z < zMax)
                    {
                        uint hash = (uint)x ^ (uint)z ^ (uint)chunkSeed;
                        
                        // Rotations: Deterministic yaw (around Y axis) in [0, 360) degrees
                        float yaw = GetDeterministicFloat(x, z, 0, chunkSeed + 5000) * 360.0f;
                        Quaternion rot = Quaternion.FromEuler(new Vector3(0f, Mathf.DegToRad(yaw), 0f));

                        // Scale: isotropic scale variance modulated stochastically
                        float sVar = 0.8f + GetDeterministicFloat(x, z, 0, chunkSeed + 6000) * 0.4f;
                        Vector3 scale = new Vector3(sVar, sVar, sVar);

                        InstanceTransform tree = new InstanceTransform(
                            pos,
                            rot,
                            scale,
                            0, // Default meshAssetId
                            hash,
                            nextId++
                        );
                        instanceSetOut.Add(tree);
                    }
                }
            }
        }

        return instanceSetOut;
    }

    private static Vector3 GetWorldPos(int x, int z, float deltaCell, Vector3 paddedOrigin)
    {
        float wx = paddedOrigin.X + (x + 0.5f) * deltaCell;
        float wz = paddedOrigin.Z + (z + 0.5f) * deltaCell;
        return new Vector3(wx, paddedOrigin.Y, wz);
    }

    private static float GetDeterministicFloat(int x, int z, int year, int seed)
    {
        uint hash = (uint)seed;
        hash ^= (uint)x * 73856093u;
        hash ^= (uint)z * 19349663u;
        hash ^= ((uint)x + (uint)z) * 83492791u;
        hash ^= (uint)year * 214013u;
        hash = hash ^ (hash >> 16);
        hash *= 0x7feb352d;
        hash = hash ^ (hash >> 15);
        hash *= 0x846ca68b;
        hash = hash ^ (hash >> 16);
        return (float)(hash & 0x7FFFFFFF) / 0x7FFFFFFF;
    }
}

#endregion
