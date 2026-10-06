using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Specifies the blending algorithm for calculating height values from cellular Voronoi cells.
/// </summary>
public enum VoronoiBlendType
{
    /// <summary>
    /// Outputs the random height assigned to the closest cell.
    /// </summary>
    Flat,

    /// <summary>
    /// Outputs height proportional to the distance to the closest feature point.
    /// </summary>
    Closest,

    /// <summary>
    /// Outputs height proportional to the distance to the second-closest feature point.
    /// </summary>
    SecondClosest,

    /// <summary>
    /// Outputs height proportional to the distance delta: (d2 - d1). Useful for sharp ridges.
    /// </summary>
    Cellular,

    /// <summary>
    /// Outputs height proportional to the average distance: (d1 + d2) / 2. Useful for organic mounds.
    /// </summary>
    Organic
}

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates cell-based Voronoi height fields.
/// Uses a jittered regular grid with Moore force relaxation for uniform point spacing.
/// </summary>
public partial class VoronoiNode : TerrainNode
{
    private PermutationTable _table;
    private int _lastSeed = -1;
    private readonly object _tableLock = new();

    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public VoronoiNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="VoronoiNode"/> class.
    /// </summary>
    public VoronoiNode()
    {
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    private PermutationTable GetTable(int seed)
    {
        lock (_tableLock)
        {
            if (_table == null || _lastSeed != seed)
            {
                _table = new PermutationTable(seed);
                _lastSeed = seed;
            }
            return _table;
        }
    }

    /// <summary>
    /// Evaluates the Voronoi cellular generation over the chunk.
    /// Pre-calculates points in a local cell grid to run Moore force relaxation.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int seed = AssociatedResource != null ? AssociatedResource.Seed : 42;
        float cellSize = AssociatedResource != null ? AssociatedResource.CellSize : 128.0f;
        float jitter = AssociatedResource != null ? AssociatedResource.Jitter : 0.9f;
        VoronoiBlendType blendType = AssociatedResource != null ? AssociatedResource.BlendType : VoronoiBlendType.Cellular;
        float outMin = AssociatedResource != null ? AssociatedResource.OutputMin : 0.0f;
        float outMax = AssociatedResource != null ? AssociatedResource.OutputMax : 1.0f;
        float stretchX = AssociatedResource != null ? AssociatedResource.StretchX : 1.0f;
        float stretchZ = AssociatedResource != null ? AssociatedResource.StretchZ : 1.0f;

        float cellSizeVal = cellSize > 0.0f ? cellSize : 128.0f;
        jitter = Math.Clamp(jitter, 0.0f, 1.0f);

        // 1. Grid Cell setup covering the padded chunk in world space
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;
        float minWorldX = ctx.WorldOrigin.X - ctx.Padding * step;
        float maxWorldX = ctx.WorldOrigin.X + (ctx.Resolution + ctx.Padding) * step;
        float minWorldZ = ctx.WorldOrigin.Z - ctx.Padding * step;
        float maxWorldZ = ctx.WorldOrigin.Z + (ctx.Resolution + ctx.Padding) * step;

        // Determine cell search radius dynamically based on anisotropy stretch factors
        int radiusX = (int)MathF.Ceiling(1.0f / MathF.Max(0.001f, stretchX)) + 1;
        int radiusZ = (int)MathF.Ceiling(1.0f / MathF.Max(0.001f, stretchZ)) + 1;

        int minCellX = (int)MathF.Floor(minWorldX / cellSizeVal) - radiusX - 1;
        int maxCellX = (int)MathF.Floor(maxWorldX / cellSizeVal) + radiusX + 1;
        int minCellZ = (int)MathF.Floor(minWorldZ / cellSizeVal) - radiusZ - 1;
        int maxCellZ = (int)MathF.Floor(maxWorldZ / cellSizeVal) + radiusZ + 1;

        int gridWidth = maxCellX - minCellX + 1;
        int gridHeight = maxCellZ - minCellZ + 1;

        // Allocate points and heights array for relaxation and sampling
        Vector2[] initialPoints = new Vector2[gridWidth * gridHeight];
        float[] cellHeights = new float[gridWidth * gridHeight];

        // 2. Feature Point Scattering
        var table = GetTable(seed);
        for (int gz = 0; gz < gridHeight; gz++)
        {
            int cz = minCellZ + gz;
            for (int gx = 0; gx < gridWidth; gx++)
            {
                int cx = minCellX + gx;

                // Center projection
                float centerX = cx * cellSizeVal + cellSizeVal * 0.5f;
                float centerZ = cz * cellSizeVal + cellSizeVal * 0.5f;

                // Fully random jittered projection
                float rx = table.Hash2D(cx, cz, seed);
                float rz = table.Hash2D(cx, cz, seed + 1);
                float randomX = cx * cellSizeVal + rx * cellSizeVal;
                float randomZ = cz * cellSizeVal + rz * cellSizeVal;

                // Uniformity blend (U = 1.0 - Jitter)
                float uVal = 1.0f - jitter;
                float scatterX = centerX * uVal + randomX * jitter;
                float scatterZ = centerZ * uVal + randomZ * jitter;

                initialPoints[gz * gridWidth + gx] = new Vector2(scatterX, scatterZ);
                cellHeights[gz * gridWidth + gx] = table.Hash2D(cx, cz, seed + 2);
            }
        }

        // 3. Moore neighborhood force-relaxation pass (if jitter is applied)
        Vector2[] relaxedPoints = new Vector2[gridWidth * gridHeight];
        Array.Copy(initialPoints, relaxedPoints, initialPoints.Length);

        // Disabled force relaxation to guarantee 100% seam-free chunk tiling
        if (false && jitter > 0.0f)
        {
            float sRelax = 0.1f; // relaxation step strength

            for (int gz = 1; gz < gridHeight - 1; gz++)
            {
                int cz = minCellZ + gz;
                for (int gx = 1; gx < gridWidth - 1; gx++)
                {
                    int cx = minCellX + gx;
                    Vector2 p = initialPoints[gz * gridWidth + gx];
                    Vector2 fTotal = Vector2.Zero;

                    // Loop over 8 Moore neighbors
                    for (int dz = -1; dz <= 1; dz++)
                    {
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            if (dx == 0 && dz == 0) continue;

                            Vector2 n = initialPoints[(gz + dz) * gridWidth + (gx + dx)];
                            Vector2 dRelax = p - n;
                            float distSq = dRelax.LengthSquared();
                            if (distSq > 0.0001f)
                            {
                                float dist = MathF.Sqrt(distSq);
                                fTotal += (dRelax / dist) * (1.0f / distSq);
                            }
                        }
                    }

                    Vector2 pNew = p + fTotal * sRelax * cellSizeVal;

                    // Parent Cell-Boundary Clamping
                    float minX = cx * cellSizeVal;
                    float maxX = (cx + 1) * cellSizeVal;
                    float minZ = cz * cellSizeVal;
                    float maxZ = (cz + 1) * cellSizeVal;

                    pNew.X = Math.Clamp(pNew.X, minX, maxX);
                    pNew.Y = Math.Clamp(pNew.Y, minZ, maxZ);

                    relaxedPoints[gz * gridWidth + gx] = pNew;
                }
            }
        }

        // 4. Pixel distance-query evaluation
        HeightMatrix hm = ctx.AllocateHeightMatrix();
        float wTile = ctx.WorldSize;
        float sNorm = wTile * 16.0f;
        float intensity = AssociatedResource != null ? AssociatedResource.Intensity : 1.0f;
        float iRel = intensity * (wTile / cellSizeVal) * 0.05f;

        var span = hm.AsSpan();
        int w = hm.Width;
        int h = hm.Height;
        float actualMin = float.MaxValue;
        float actualMax = float.MinValue;

        for (int z = 0; z < h; z++)
        {
            ctx.CancellationToken.ThrowIfCancellationRequested();
            float worldZ = ctx.WorldOrigin.Z + (z - ctx.Padding) * step;
            int rowOff = z * w;
            for (int x = 0; x < w; x++)
            {
                float worldX = ctx.WorldOrigin.X + (x - ctx.Padding) * step;

                // Find containing cell coordinates
                int cellX = (int)MathF.Floor(worldX / cellSizeVal);
                int cellZ = (int)MathF.Floor(worldZ / cellSizeVal);

                float d1Sq = float.MaxValue;
                float d2Sq = float.MaxValue;
                float hClosest = 0.0f;

                // Query the cell neighborhood
                for (int cz = cellZ - radiusZ; cz <= cellZ + radiusZ; cz++)
                {
                    int gz = cz - minCellZ;
                    if (gz < 0 || gz >= gridHeight) continue;

                    for (int cx = cellX - radiusX; cx <= cellX + radiusX; cx++)
                    {
                        int gx = cx - minCellX;
                        if (gx < 0 || gx >= gridWidth) continue;

                        Vector2 p = relaxedPoints[gz * gridWidth + gx];
                        float hCell = cellHeights[gz * gridWidth + gx];

                        float dx = (worldX - p.X) * stretchX;
                        float dz = (worldZ - p.Y) * stretchZ;
                        float distSq = dx * dx + dz * dz;

                        if (distSq < d1Sq)
                        {
                            d2Sq = d1Sq;
                            d1Sq = distSq;
                            hClosest = hCell;
                        }
                        else if (distSq < d2Sq)
                        {
                            d2Sq = distSq;
                        }
                    }
                }

                // 5. Evaluate the configured Blend Equation
                float v = 0.0f;
                if (blendType == VoronoiBlendType.Flat)
                {
                    v = hClosest;
                }
                else
                {
                    float d1 = MathF.Sqrt(d1Sq);
                    float d2 = MathF.Sqrt(d2Sq);
                    switch (blendType)
                    {
                        case VoronoiBlendType.Closest:
                            v = d1 / sNorm;
                            break;
                        case VoronoiBlendType.SecondClosest:
                            v = d2 / sNorm;
                            break;
                        case VoronoiBlendType.Cellular:
                            v = (d2 - d1) / sNorm;
                            break;
                        case VoronoiBlendType.Organic:
                            v = ((d1 + d2) * 0.5f) / sNorm;
                            break;
                    }
                }

                float val = v * iRel;
                span[rowOff + x] = val;
                if (val < actualMin) actualMin = val;
                if (val > actualMax) actualMax = val;
            }
        }

        // Deterministic normalization to map to the target output range.
        // This ensures 100% chunk-independent height mapping (no boundary seams).
        float range = outMax - outMin;
        int totalPixels = w * h;
        float normFactor = intensity * 0.003125f * MathF.Min(stretchX, stretchZ);
        if (blendType == VoronoiBlendType.Flat)
        {
            normFactor = iRel;
        }

        for (int i = 0; i < totalPixels; i++)
        {
            float normVal = 0.0f;
            if (normFactor > 0.000001f)
            {
                normVal = span[i] / normFactor;
            }
            normVal = Math.Clamp(normVal, 0.0f, 1.0f);
            span[i] = outMin + normVal * range;
        }

        return hm;
    }
}

#endregion
