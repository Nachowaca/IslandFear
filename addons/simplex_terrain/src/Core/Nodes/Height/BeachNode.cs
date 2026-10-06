using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that creates smooth sandy beaches and deposition profiles around the water level.
/// </summary>
public partial class BeachNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public BeachNodeResource AssociatedResource { get; set; }

    private readonly Dictionary<ChunkCoordinate, HeightMatrix[]> _localCache = new();
    private readonly object _localCacheLock = new();

    /// <summary>
    /// Initializes a new instance of the <see cref="BeachNode"/> class.
    /// </summary>
    public BeachNode()
    {
        Inputs.Add(new Port("HeightIn", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("Mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("HeightOut", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("ShoreMaskOut", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates beach shoreline profiling and outputs both modified heights and shore transition mask.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(ctx.Coord, out var cached))
            {
                if (outputPortIndex == 0) return cached[0].Clone();
                if (outputPortIndex == 1) return cached[1].Clone();
                return null;
            }
        }

        // Fetch inputs
        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix maskInput = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            maskInput = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        if (inputHM == null)
        {
            var emptyH = ctx.AllocateHeightMatrix();
            var emptyM = ctx.AllocateHeightMatrix();
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { emptyH, emptyM };
            }
            return outputPortIndex == 0 ? emptyH.Clone() : emptyM.Clone();
        }

        float seaLevel = AssociatedResource != null ? AssociatedResource.SeaLevel : 0.3f;
        float beachWidth = AssociatedResource != null ? AssociatedResource.BeachWidth : 0.05f;
        float beachSlope = AssociatedResource != null ? AssociatedResource.BeachSlope : 0.3f;
        float underwaterSandDepth = AssociatedResource != null ? AssociatedResource.UnderwaterSandDepth : 0.05f;
        float shoreRelax = AssociatedResource != null ? AssociatedResource.ShoreRelax : 5.0f;
        float beachSize = AssociatedResource != null ? AssociatedResource.BeachSize : 10.0f;

        // Defensive limits
        beachWidth = MathF.Max(1e-5f, beachWidth);
        underwaterSandDepth = MathF.Max(1e-5f, underwaterSandDepth);
        beachSlope = Math.Clamp(beachSlope, 0.0f, 1.0f);
        shoreRelax = MathF.Max(0.1f, shoreRelax);
        beachSize = MathF.Max(0.1f, beachSize);

        int w = inputHM.Width;
        int h = inputHM.Height;

        // Step 1: Shoreline Isolation
        using HeightMatrix mShore = new HeightMatrix(w, h);
        float threshold = seaLevel + beachWidth * 0.5f;
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                mShore[x, z] = inputHM[x, z] > threshold ? 1.0f : 0.0f;
            }
        }

        // Step 2: Inward Spread on (1.0f - M_shore)
        using HeightMatrix invertedShore = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                invertedShore[x, z] = 1.0f - mShore[x, z];
            }
        }
        using HeightMatrix mIn = SpreadLinear(invertedShore, 1.0f / shoreRelax);

        // Step 3: Curvature Smoothing: Threshold at 0.01, invert, apply 3.75 Gaussian blur
        using HeightMatrix mSelect1 = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                mSelect1[x, z] = mIn[x, z] < 0.01f ? 1.0f : 0.0f;
            }
        }
        using HeightMatrix mIns = GaussianBlur(mSelect1, 3.75f);

        // Step 4: Outward Spread: Threshold relaxed shore at 0.5, apply linear spreading outwards by beachSize (pixels)
        using HeightMatrix mSelect2 = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                mSelect2[x, z] = mIns[x, z] >= 0.5f ? 1.0f : 0.0f;
            }
        }
        using HeightMatrix sSpreadRaw = SpreadLinear(mSelect2, 1.0f / beachSize);
        using HeightMatrix sSpreadClamped = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                sSpreadClamped[x, z] = Math.Clamp(sSpreadRaw[x, z], 0.0f, 1.0f);
            }
        }

        // Step 5: Convolve sSpreadClamped with a 3.75 pixel Gaussian blur
        using HeightMatrix sSpreadFinal = GaussianBlur(sSpreadClamped, 3.75f);

        // Height Profiling & Sand distribution
        HeightMatrix heightOut = ctx.AllocateHeightMatrix();
        HeightMatrix shoreMaskOut = ctx.AllocateHeightMatrix();

        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                float H_val = inputHM[x, z];
                float sSpread = sSpreadFinal[x, z];
                float maskVal = maskInput != null ? maskInput[x, z] : 1.0f;

                // 1. Calculate quadratic falloff modifier
                float mPrime = 1.0f - (1.0f - maskVal) * (1.0f - maskVal);

                // 2. Combined beach influence weight
                float p = sSpread * mPrime;

                // 3. Interpolate target beach plateau height
                float vTarget = seaLevel - beachWidth * 0.5f + p * beachWidth;

                // 4. Determine bottom transition smoothing weight
                float pBottom = MathF.Max(0.0f, (0.5f - p) * 2.0f);
                float pBottomSmooth = 3.0f * pBottom * pBottom - 2.0f * pBottom * pBottom * pBottom;

                // 5. Blend target beach with original terrain height
                float hBeach = vTarget * (1.0f - pBottomSmooth) + H_val * pBottomSmooth;

                // 6. Merge with max operator to prevent excavation into high terrain
                float hFinal = MathF.Max(H_val, hBeach);
                heightOut[x, z] = hFinal;

                // Beach Sand Distribution
                float pSand = 0.0f;
                if (hFinal > seaLevel)
                {
                    pSand = MathF.Max(0.0f, MathF.Min(1.0f, (hFinal - H_val) / underwaterSandDepth));
                }
                else if (seaLevel >= hFinal && hFinal > (seaLevel - underwaterSandDepth * 0.5f))
                {
                    pSand = hFinal > H_val ? 1.0f : 0.0f;
                }
                else
                {
                    pSand = 1.0f;
                }

                shoreMaskOut[x, z] = pSand;
            }
        }

        lock (_localCacheLock)
        {
            _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, shoreMaskOut };
        }

        if (outputPortIndex == 0) return heightOut.Clone();
        if (outputPortIndex == 1) return shoreMaskOut.Clone();
        return null;
    }

    private HeightMatrix SpreadLinear(HeightMatrix src, float rate)
    {
        int w = src.Width;
        int h = src.Height;
        HeightMatrix dst = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                dst[x, z] = src[x, z];
            }
        }
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                float val = dst[x, z];
                if (x > 0) val = MathF.Max(val, dst[x - 1, z] - rate);
                if (z > 0) val = MathF.Max(val, dst[x, z - 1] - rate);
                if (x > 0 && z > 0) val = MathF.Max(val, dst[x - 1, z - 1] - rate * MathF.Sqrt(2f));
                dst[x, z] = val;
            }
        }
        for (int z = h - 1; z >= 0; z--)
        {
            for (int x = w - 1; x >= 0; x--)
            {
                float val = dst[x, z];
                if (x < w - 1) val = MathF.Max(val, dst[x + 1, z] - rate);
                if (z < h - 1) val = MathF.Max(val, dst[x, z + 1] - rate);
                if (x < w - 1 && z < h - 1) val = MathF.Max(val, dst[x + 1, z + 1] - rate * MathF.Sqrt(2f));
                dst[x, z] = val;
            }
        }
        return dst;
    }

    private HeightMatrix GaussianBlur(HeightMatrix src, float radius)
    {
        int w = src.Width;
        int h = src.Height;
        HeightMatrix dst = new HeightMatrix(w, h);
        int kernelSize = (int)MathF.Round(radius * 3.0f) * 2 + 1;
        if (kernelSize < 3) kernelSize = 3;
        if (kernelSize > 25) kernelSize = 25;
        float[] kernel = new float[kernelSize];
        float sum = 0.0f;
        int half = kernelSize / 2;
        float twoSigmaSq = 2.0f * radius * radius;
        for (int i = 0; i < kernelSize; i++)
        {
            int x = i - half;
            kernel[i] = MathF.Exp(-(x * x) / twoSigmaSq);
            sum += kernel[i];
        }
        for (int i = 0; i < kernelSize; i++) kernel[i] /= sum;
        HeightMatrix temp = new HeightMatrix(w, h);
        for (int z = 0; z < h; z++)
        {
            for (int x = 0; x < w; x++)
            {
                float val = 0.0f;
                for (int k = 0; k < kernelSize; k++)
                {
                    int kx = Math.Clamp(x + k - half, 0, w - 1);
                    val += src[kx, z] * kernel[k];
                }
                temp[x, z] = val;
            }
        }
        for (int x = 0; x < w; x++)
        {
            for (int z = 0; z < h; z++)
            {
                float val = 0.0f;
                for (int k = 0; k < kernelSize; k++)
                {
                    int kz = Math.Clamp(z + k - half, 0, h - 1);
                    val += temp[x, kz] * kernel[k];
                }
                dst[x, z] = val;
            }
        }
        temp.Dispose();
        return dst;
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
