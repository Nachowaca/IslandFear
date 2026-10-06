using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that carves U-shaped riverbeds along 3D splines and creates water & bank masks.
/// </summary>
public partial class RiverGeneratorNode : TerrainNode
{
    private struct SegmentData
    {
        public Vector3 P0;
        public Vector3 P1;
        public Vector3 P2;
        public Vector3 P3;
        public Vector2 P0_2D;
        public Vector2 P1_2D;
        public Vector2 P2_2D;
        public Vector2 P3_2D;
        public float MinX;
        public float MaxX;
        public float MinZ;
        public float MaxZ;
        public Vector2[] PrecomputedPoints;
    }

    private static float ProjectPointOntoSegment2D(
        Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3,
        Vector2[] precomputed, Vector2 Q, out float minDistanceSq)
    {
        float bestP = 0.0f;
        float bestDistSq = float.MaxValue;
        int kApprox = precomputed.Length;

        // Phase 1: Coarse Grid Search using precomputed points
        for (int i = 0; i < kApprox; i++)
        {
            float distSq = precomputed[i].DistanceSquaredTo(Q);
            if (distSq < bestDistSq)
            {
                bestDistSq = distSq;
                bestP = (float)i / (kApprox - 1);
            }
        }

        // Phase 2: Binary Interval Refinement
        int jRefine = 4;
        float width = 1.0f / (kApprox - 1);

        for (int j = 0; j < jRefine; j++)
        {
            width *= 0.5f;
            float pUpper = Math.Clamp(bestP + width, 0.0f, 1.0f);
            float pLower = Math.Clamp(bestP - width, 0.0f, 1.0f);

            float omtU = 1.0f - pUpper;
            Vector2 posUpper = omtU * omtU * omtU * p0
                             + 3.0f * pUpper * omtU * omtU * p1
                             + 3.0f * pUpper * pUpper * omtU * p2
                             + pUpper * pUpper * pUpper * p3;

            float omtL = 1.0f - pLower;
            Vector2 posLower = omtL * omtL * omtL * p0
                             + 3.0f * pLower * omtL * omtL * p1
                             + 3.0f * pLower * pLower * omtL * p2
                             + pLower * pLower * pLower * p3;

            float distUpperSq = posUpper.DistanceSquaredTo(Q);
            float distLowerSq = posLower.DistanceSquaredTo(Q);

            if (distUpperSq < distLowerSq)
            {
                bestP = pUpper;
            }
            else
            {
                bestP = pLower;
            }
        }

        float omtF = 1.0f - bestP;
        Vector2 finalPos = omtF * omtF * omtF * p0
                         + 3.0f * bestP * omtF * omtF * p1
                         + 3.0f * bestP * bestP * omtF * p2
                         + bestP * bestP * bestP * p3;
        minDistanceSq = finalPos.DistanceSquaredTo(Q);
        return bestP;
    }

    public RiverGeneratorNodeResource AssociatedResource { get; set; }

    private readonly Dictionary<ChunkCoordinate, HeightMatrix[]> _localCache = new();
    private readonly object _localCacheLock = new();

    public RiverGeneratorNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("water_mask", PortType.Mask, PortDirection.Output));
        Outputs.Add(new Port("river_mask", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(ctx.Coord, out var cached))
            {
                if (outputPortIndex == 0) return cached[0].Clone();
                if (outputPortIndex == 1) return cached[1].Clone();
                if (outputPortIndex == 2) return cached[2].Clone();
                return null;
            }
        }

        var swTotal = System.Diagnostics.Stopwatch.StartNew();

        float riverWidth = AssociatedResource != null ? AssociatedResource.RiverWidth : 20.0f;
        float riverDepth = AssociatedResource != null ? AssociatedResource.RiverDepth : 4.0f;
        float bankWidth = AssociatedResource != null ? AssociatedResource.BankWidth : 10.0f;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        SplineSet splineSet = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            splineSet = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplineSet;
        }

        HeightMatrix heightOut = ctx.AllocateHeightMatrix();
        HeightMatrix waterMask = ctx.AllocateHeightMatrix();
        HeightMatrix riverMask = ctx.AllocateHeightMatrix();

        if (inputHM == null)
        {
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, waterMask, riverMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            if (outputPortIndex == 1) return waterMask.Clone();
            return riverMask.Clone();
        }

        // Copy input heights
        int width = inputHM.Width;
        int height = inputHM.Height;
        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                heightOut[x, z] = inputHM[x, z];
            }
        }

        if (splineSet == null || splineSet.GetCurveCount() == 0)
        {
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, waterMask, riverMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            if (outputPortIndex == 1) return waterMask.Clone();
            return riverMask.Clone();
        }

        // Precompute curve tangents
        var curvesData = new List<(Vector3[] controlPoints, Vector3[] tangentsOut, Vector3[] tangentsIn, CurveType type)>();
        foreach (var curve in splineSet.Curves)
        {
            if (curve.ControlPoints.Count < 2) continue;
            var pts = curve.ControlPoints;
            SplineMath.ComputeTangents(curve, out var tOut, out var tIn);
            curvesData.Add((pts.ToArray(), tOut, tIn, curve.Type));
        }

        if (curvesData.Count == 0)
        {
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, waterMask, riverMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            if (outputPortIndex == 1) return waterMask.Clone();
            return riverMask.Clone();
        }

        var segmentsList = new List<SegmentData>();
        foreach (var data in curvesData)
        {
            int n = data.controlPoints.Length;
            int segmentsCount = data.type == CurveType.Closed ? n : n - 1;

            for (int s = 0; s < segmentsCount; s++)
            {
                Vector3 p0 = data.controlPoints[s];
                Vector3 p3 = data.controlPoints[(s + 1) % n];
                Vector3 t0 = data.tangentsOut[s];
                Vector3 t3 = data.tangentsIn[(s + 1) % n];

                Vector3 p1 = p0 + t0;
                Vector3 p2 = p3 + t3;

                // 2D bounding box of control points p0, p1, p2, p3
                float minX = MathF.Min(MathF.Min(p0.X, p1.X), MathF.Min(p2.X, p3.X));
                float maxX = MathF.Max(MathF.Max(p0.X, p1.X), MathF.Max(p2.X, p3.X));
                float minZ = MathF.Min(MathF.Min(p0.Z, p1.Z), MathF.Min(p2.Z, p3.Z));
                float maxZ = MathF.Max(MathF.Max(p0.Z, p1.Z), MathF.Max(p2.Z, p3.Z));

                Vector2 p0_2D = new Vector2(p0.X, p0.Z);
                Vector2 p1_2D = new Vector2(p1.X, p1.Z);
                Vector2 p2_2D = new Vector2(p2.X, p2.Z);
                Vector2 p3_2D = new Vector2(p3.X, p3.Z);

                int kApprox = 8;
                Vector2[] precomputed = new Vector2[kApprox];
                for (int i = 0; i < kApprox; i++)
                {
                    float t = (float)i / (kApprox - 1);
                    float omt = 1.0f - t;
                    precomputed[i] = omt * omt * omt * p0_2D
                                   + 3.0f * t * omt * omt * p1_2D
                                   + 3.0f * t * t * omt * p2_2D
                                   + t * t * t * p3_2D;
                }

                segmentsList.Add(new SegmentData
                {
                    P0 = p0,
                    P1 = p1,
                    P2 = p2,
                    P3 = p3,
                    P0_2D = p0_2D,
                    P1_2D = p1_2D,
                    P2_2D = p2_2D,
                    P3_2D = p3_2D,
                    MinX = minX,
                    MaxX = maxX,
                    MinZ = minZ,
                    MaxZ = maxZ,
                    PrecomputedPoints = precomputed
                });
            }
        }

        float rRadius = riverWidth / 2.0f;
        float bRadius = rRadius + bankWidth;
        float heightScaleVal = MathF.Abs(heightScale) > 1e-5f ? heightScale : 1.0f;
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;

        float checkRadiusSq = bRadius * bRadius;

        // Chunk-level bounding box filtering to avoid checking distant segments for all 331K pixels
        float chunkMinX = ctx.WorldOrigin.X - ctx.Padding * step;
        float chunkMaxX = ctx.WorldOrigin.X + (ctx.Resolution + ctx.Padding) * step;
        float chunkMinZ = ctx.WorldOrigin.Z - ctx.Padding * step;
        float chunkMaxZ = ctx.WorldOrigin.Z + (ctx.Resolution + ctx.Padding) * step;

        var localSegments = new List<SegmentData>();
        foreach (var seg in segmentsList)
        {
            float segMinX = seg.MinX - bRadius;
            float segMaxX = seg.MaxX + bRadius;
            float segMinZ = seg.MinZ - bRadius;
            float segMaxZ = seg.MaxZ + bRadius;

            if (segMaxX >= chunkMinX && segMinX <= chunkMaxX &&
                segMaxZ >= chunkMinZ && segMinZ <= chunkMaxZ)
            {
                localSegments.Add(seg);
            }
        }

        if (localSegments.Count == 0)
        {
            // No segments close to this chunk: cache and return inputs directly (0 ms)
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, waterMask, riverMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            if (outputPortIndex == 1) return waterMask.Clone();
            return riverMask.Clone();
        }

        // 16x16 Grid Spatial Partitioning for active segments in this chunk
        int gridResolution = 16;
        var grid = new List<SegmentData>[gridResolution, gridResolution];
        for (int rz = 0; rz < gridResolution; rz++)
        {
            for (int rx = 0; rx < gridResolution; rx++)
            {
                grid[rx, rz] = new List<SegmentData>();
            }
        }

        float cellWidth = (chunkMaxX - chunkMinX) / gridResolution;
        float cellHeight = (chunkMaxZ - chunkMinZ) / gridResolution;

        foreach (var seg in localSegments)
        {
            float segMinX = seg.MinX - bRadius;
            float segMaxX = seg.MaxX + bRadius;
            float segMinZ = seg.MinZ - bRadius;
            float segMaxZ = seg.MaxZ + bRadius;

            int minCellX = Math.Clamp((int)((segMinX - chunkMinX) / cellWidth), 0, gridResolution - 1);
            int maxCellX = Math.Clamp((int)((segMaxX - chunkMinX) / cellWidth), 0, gridResolution - 1);
            int minCellZ = Math.Clamp((int)((segMinZ - chunkMinZ) / cellHeight), 0, gridResolution - 1);
            int maxCellZ = Math.Clamp((int)((segMaxZ - chunkMinZ) / cellHeight), 0, gridResolution - 1);

            for (int gz = minCellZ; gz <= maxCellZ; gz++)
            {
                for (int gx = minCellX; gx <= maxCellX; gx++)
                {
                    grid[gx, gz].Add(seg);
                }
            }
        }

        var swPixels = System.Diagnostics.Stopwatch.StartNew();
        long projectionCount = 0;
        long projectionTicks = 0;

        for (int pz = 0; pz < height; pz++)
        {
            float worldZ = ctx.WorldOrigin.Z + (pz - ctx.Padding) * step;
            for (int px = 0; px < width; px++)
            {
                float worldX = ctx.WorldOrigin.X + (px - ctx.Padding) * step;
                Vector2 q2D = new Vector2(worldX, worldZ);
                float hOrig = inputHM[px, pz];

                float bestDist2DSq = float.MaxValue;
                float bestT = 0.0f;
                SegmentData bestSeg = default;
                bool foundCloseSegment = false;

                int cellX = Math.Clamp((int)((worldX - chunkMinX) / cellWidth), 0, gridResolution - 1);
                int cellZ = Math.Clamp((int)((worldZ - chunkMinZ) / cellHeight), 0, gridResolution - 1);
                var cellSegments = grid[cellX, cellZ];

                foreach (var seg in cellSegments)
                {
                    // Compute distance from query point Q (worldX, worldZ) to segment's 2D bounding box
                    float boxDistX = MathF.Max(0.0f, MathF.Max(seg.MinX - worldX, worldX - seg.MaxX));
                    float boxDistZ = MathF.Max(0.0f, MathF.Max(seg.MinZ - worldZ, worldZ - seg.MaxZ));
                    float boxDistSq = boxDistX * boxDistX + boxDistZ * boxDistZ;

                    if (boxDistSq > checkRadiusSq)
                    {
                        continue;
                    }

                    long startTicks = System.Diagnostics.Stopwatch.GetTimestamp();
                    float segmentDist2DSq;
                    float tProj = ProjectPointOntoSegment2D(seg.P0_2D, seg.P1_2D, seg.P2_2D, seg.P3_2D, seg.PrecomputedPoints, q2D, out segmentDist2DSq);
                    long endTicks = System.Diagnostics.Stopwatch.GetTimestamp();
                    projectionCount++;
                    projectionTicks += (endTicks - startTicks);

                    if (segmentDist2DSq < bestDist2DSq)
                    {
                        bestDist2DSq = segmentDist2DSq;
                        bestT = tProj;
                        bestSeg = seg;
                        foundCloseSegment = true;
                    }
                }

                if (!foundCloseSegment)
                {
                    heightOut[px, pz] = hOrig;
                    waterMask[px, pz] = 0.0f;
                    riverMask[px, pz] = 0.0f;
                    continue;
                }

                Vector3 bestProjPoint = SplineMath.EvaluateBezierPosition(bestSeg.P0, bestSeg.P1, bestSeg.P2, bestSeg.P3, bestT);
                float d = MathF.Sqrt(bestDist2DSq);
                float yOrig = hOrig * heightScaleVal;
                float yTarget = yOrig;

                float wWater = 0.0f;
                float wRiver = 0.0f;

                if (d <= rRadius)
                {
                    float u = d / (rRadius > 0.001f ? rRadius : 0.001f);
                    float profileFactor = MathF.Cos(MathF.PI * 0.5f * u);
                    yTarget = bestProjPoint.Y - riverDepth * profileFactor;

                    wWater = 1.0f;
                    wRiver = 1.0f;
                }
                else if (d <= bRadius)
                {
                    float t = (d - rRadius) / (bankWidth > 0.001f ? bankWidth : 0.001f);
                    t = Math.Clamp(t, 0.0f, 1.0f);
                    float w = 3.0f * t * t - 2.0f * t * t * t; // smoothstep
                    yTarget = bestProjPoint.Y * (1.0f - w) + yOrig * w;

                    wWater = 0.0f;
                    wRiver = 1.0f - w;
                }
                else
                {
                    yTarget = yOrig;
                    wWater = 0.0f;
                    wRiver = 0.0f;
                }

                // Carve only: prevent raising terrain below target level
                float yFinal = MathF.Min(yOrig, yTarget);
                heightOut[px, pz] = yFinal / heightScaleVal;
                waterMask[px, pz] = wWater;
                riverMask[px, pz] = wRiver;
            }
        }

        swPixels.Stop();
        swTotal.Stop();

        float totalMs = swTotal.ElapsedMilliseconds;
        float pixelsMs = swPixels.ElapsedMilliseconds;
        float projMs = (float)projectionTicks / System.Diagnostics.Stopwatch.Frequency * 1000.0f;

        GD.Print($"[RiverGeneratorNode Detail] chunk({ctx.Coord}): Total={totalMs:F1}ms, PixelLoop={pixelsMs:F1}ms (of which Projections={projMs:F1}ms, Count={projectionCount}), Segments={localSegments.Count}");

        lock (_localCacheLock)
        {
            _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, waterMask, riverMask };
        }

        if (outputPortIndex == 0) return heightOut.Clone();
        if (outputPortIndex == 1) return waterMask.Clone();
        return riverMask.Clone();
    }
    public override void ClearCache()
    {
        base.ClearCache();
        lock (_localCacheLock)
        {
            foreach (var kvp in _localCache)
            {
                if (kvp.Value != null)
                {
                    foreach (var hm in kvp.Value)
                    {
                        hm?.Dispose();
                    }
                }
            }
            _localCache.Clear();
        }
    }

    public override void ClearCacheForChunk(ChunkCoordinate coord)
    {
        base.ClearCacheForChunk(coord);
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(coord, out var matrices))
            {
                if (matrices != null)
                {
                    foreach (var hm in matrices)
                    {
                        hm?.Dispose();
                    }
                }
                _localCache.Remove(coord);
            }
        }
    }
}

#endregion
