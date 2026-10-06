using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that translates temperature and moisture maps into soft biome weight masks.
/// </summary>
public partial class WhittakerLookupNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public WhittakerLookupNodeResource AssociatedResource { get; set; }

    private readonly Dictionary<ChunkCoordinate, HeightMatrix[]> _localCache = new();
    private readonly object _localCacheLock = new();

    private readonly object _imageLock = new();
    private int[,] _cachedIndices = null;
    private int _cachedWidth = 0;
    private int _cachedHeight = 0;

    // Pre-blurred per-biome soft probability masks for smooth transitions.
    // _softBiomeMasks[biomeIndex] is a flat float[width * height] array indexed as [y * width + x].
    private float[][] _softBiomeMasks = null;
    private int _softMaskBiomeCount = -1;
    private float _softMaskSoftness = -1f;

    /// <summary>
    /// Initializes a new instance of the <see cref="WhittakerLookupNode"/> class.
    /// </summary>
    public WhittakerLookupNode()
    {
        OnResourceSet();
    }

    /// <summary>
    /// Dynamically defines ports based on the associated parameter resource.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        Inputs.Add(new Port("temperature_mask", PortType.Mask, PortDirection.Input));
        Inputs.Add(new Port("moisture_mask", PortType.Mask, PortDirection.Input));

        Outputs.Clear();
        int count = AssociatedResource != null ? AssociatedResource.BiomeCount : 2;
        if (count < 1) count = 1;

        for (int i = 0; i < count; i++)
        {
            Outputs.Add(new Port($"biome_{i}_out", PortType.Mask, PortDirection.Output));
        }

        InitializePorts();
    }

    /// <summary>
    /// Caches the Whittaker diagram texture's pixel values as a thread-safe 2D integer index array.
    /// If no diagram texture is provided, generates a procedural Whittaker grid.
    /// Runs once on the main or execution thread.
    /// </summary>
    private void CacheWhittakerImage()
    {
        lock (_imageLock)
        {
            if (_cachedIndices != null) return;

            var tex = AssociatedResource?.WhittakerDiagram;
            if (tex != null)
            {
                var img = tex.GetImage();
                if (img != null)
                {
                    _cachedWidth = img.GetWidth();
                    _cachedHeight = img.GetHeight();
                    _cachedIndices = new int[_cachedWidth, _cachedHeight];
                    for (int y = 0; y < _cachedHeight; y++)
                    {
                        for (int x = 0; x < _cachedWidth; x++)
                        {
                            Color c = img.GetPixel(x, y);
                            // Encode biome index as Red channel integer representation
                            _cachedIndices[x, y] = (int)MathF.Round(c.R * 255.0f);
                        }
                    }
                }
            }

            // Procedural fallback: generate a virtual 256x256 Whittaker grid
            if (_cachedIndices == null)
            {
                _cachedWidth = 256;
                _cachedHeight = 256;
                _cachedIndices = new int[_cachedWidth, _cachedHeight];
                for (int y = 0; y < _cachedHeight; y++)
                {
                    for (int x = 0; x < _cachedWidth; x++)
                    {
                        float t = (float)x / (_cachedWidth - 1);
                        float m = (float)y / (_cachedHeight - 1);
                        _cachedIndices[x, y] = GetBiomeIndexProcedural(t, m);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Ensures pre-blurred per-biome soft probability masks are built and up-to-date.
    /// Rebuilds if biomeCount or softness has changed.
    /// Ref: 08_HEIGHT_AND_BIOME_OUTPUTS.md §3.A — Whittaker Diagram Lookup with soft blending.
    /// </summary>
    private void EnsureSoftMasks(int biomeCount, float softness)
    {
        lock (_imageLock)
        {
            CacheWhittakerImage();

            if (_softBiomeMasks != null && _softMaskBiomeCount == biomeCount
                && MathF.Abs(_softMaskSoftness - softness) < 0.001f)
            {
                return;
            }

            BuildSoftBiomeMasks(biomeCount, softness);
            _softMaskBiomeCount = biomeCount;
            _softMaskSoftness = softness;
        }
    }

    /// <summary>
    /// Builds per-biome soft probability masks from the indexed Whittaker diagram.
    /// For each biome, a binary mask (1 where biome==k, 0 elsewhere) is created and then
    /// Gaussian-blurred using a separable kernel with sigma proportional to Softness.
    /// This produces wide, smooth transition zones instead of hard 1-pixel boundaries.
    /// </summary>
    private void BuildSoftBiomeMasks(int biomeCount, float softness)
    {
        if (_cachedIndices == null || _cachedWidth == 0 || _cachedHeight == 0) return;

        int w = _cachedWidth;
        int h = _cachedHeight;
        var masks = new float[biomeCount][];

        // Sigma scales with diagram size and softness parameter.
        // softness=0.0 → sigma < 0.5 → no blur (hard edges)
        // softness=0.2 → moderate transition zones
        // softness=0.5 → wide smooth transitions
        // softness=1.0 → very wide (almost global) blending
        float sigma = softness * MathF.Max(w, h) * 0.1f;

        for (int b = 0; b < biomeCount; b++)
        {
            float[] mask = new float[w * h];

            // Create binary mask: 1.0 where diagram index matches biome, 0.0 elsewhere
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    mask[y * w + x] = (_cachedIndices[x, y] == b) ? 1.0f : 0.0f;
                }
            }

            // Apply separable Gaussian blur for smooth transitions
            if (sigma >= 0.5f)
            {
                SeparableGaussianBlur(mask, w, h, sigma);
            }

            masks[b] = mask;
        }

        _softBiomeMasks = masks;
    }

    /// <summary>
    /// Applies an in-place separable 2D Gaussian blur (horizontal pass then vertical pass).
    /// Uses clamp-to-edge boundary handling.
    /// </summary>
    private static void SeparableGaussianBlur(float[] data, int width, int height, float sigma)
    {
        int radius = Math.Min((int)MathF.Ceiling(sigma * 2.5f), Math.Max(width, height) / 2);
        if (radius < 1) return;

        // Build normalized 1D Gaussian kernel
        int kernelSize = 2 * radius + 1;
        float[] kernel = new float[kernelSize];
        float kSum = 0.0f;
        float twoSigmaSq = 2.0f * sigma * sigma;

        for (int i = -radius; i <= radius; i++)
        {
            kernel[i + radius] = MathF.Exp(-(float)(i * i) / twoSigmaSq);
            kSum += kernel[i + radius];
        }
        for (int i = 0; i < kernelSize; i++)
        {
            kernel[i] /= kSum;
        }

        float[] temp = new float[width * height];

        // Horizontal pass: data → temp
        for (int y = 0; y < height; y++)
        {
            int rowOff = y * width;
            for (int x = 0; x < width; x++)
            {
                float acc = 0.0f;
                for (int k = -radius; k <= radius; k++)
                {
                    int sx = Math.Clamp(x + k, 0, width - 1);
                    acc += data[rowOff + sx] * kernel[k + radius];
                }
                temp[rowOff + x] = acc;
            }
        }

        // Vertical pass: temp → data
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                float acc = 0.0f;
                for (int k = -radius; k <= radius; k++)
                {
                    int sy = Math.Clamp(y + k, 0, height - 1);
                    acc += temp[sy * width + x] * kernel[k + radius];
                }
                data[y * width + x] = acc;
            }
        }
    }

    /// <summary>
    /// Procedural Whittaker biome classification fallback (used when no diagram image is loaded).
    /// </summary>
    private int GetBiomeIndexProcedural(float temp, float moist)
    {
        if (temp < 0.3f)
        {
            return moist < 0.4f ? 0 : 1; // 0=Tundra, 1=Taiga
        }
        else if (temp < 0.7f)
        {
            return moist < 0.3f ? 5 : 4; // 5=Grassland, 4=Temperate Forest
        }
        else
        {
            return moist < 0.2f ? 2 : 3; // 2=Desert, 3=Tropical Forest
        }
    }

    /// <summary>
    /// Evaluates temperature and moisture masks, returning the requested biome soft mask.
    /// Uses pre-blurred per-biome probability masks for smooth transitions.
    /// Ref: 08_HEIGHT_AND_BIOME_OUTPUTS.md §3 — Whittaker Biome Soft Blending & Weight Normalization.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int biomeCount = AssociatedResource != null ? AssociatedResource.BiomeCount : 2;
        if (biomeCount < 1) biomeCount = 1;

        HeightMatrix[] results;
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(ctx.Coord, out results))
            {
                if (outputPortIndex >= 0 && outputPortIndex < results.Length)
                {
                    return results[outputPortIndex];
                }
            }
        }

        // Pull inputs
        HeightMatrix tempMask = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            tempMask = InputLinks[0].SourceNode.PullReadOnlyHeight(ctx, InputLinks[0].SourcePortIndex);
        }

        HeightMatrix moistMask = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            moistMask = InputLinks[1].SourceNode.PullReadOnlyHeight(ctx, InputLinks[1].SourcePortIndex);
        }

        int width = tempMask?.Width ?? (moistMask?.Width ?? 256);
        int height = tempMask?.Height ?? (moistMask?.Height ?? 256);

        results = new HeightMatrix[biomeCount];
        for (int i = 0; i < biomeCount; i++)
        {
            results[i] = new HeightMatrix(width, height);
        }

        float softness = AssociatedResource != null ? AssociatedResource.Softness : 0.2f;
        if (softness < 0.001f) softness = 0.001f;

        float sharpness = AssociatedResource != null ? AssociatedResource.Sharpness : 0.0f;
        sharpness = Math.Clamp(sharpness, 0.0f, 1.0f);

        // Ensure pre-blurred soft masks are ready (one-time initialization)
        EnsureSoftMasks(biomeCount, softness);

        // Hoist biomeAccum allocation outside nested loops to prevent GC pressure
        float[] biomeAccum = new float[biomeCount];
        float[] unsharpenedAccum = new float[biomeCount];

        for (int z = 0; z < height; z++)
        {
            ctx.CancellationToken.ThrowIfCancellationRequested();
            for (int x = 0; x < width; x++)
            {
                float tCenter = tempMask != null ? tempMask[x, z] : 0.5f;
                float mCenter = moistMask != null ? moistMask[x, z] : 0.5f;
                tCenter = Math.Clamp(tCenter, 0.0f, 1.0f);
                mCenter = Math.Clamp(mCenter, 0.0f, 1.0f);

                Array.Clear(biomeAccum, 0, biomeCount);
                Array.Clear(unsharpenedAccum, 0, biomeCount);

                // Bilinear sampling on pre-blurred soft per-biome probability masks
                // Ref: 08_HEIGHT_AND_BIOME_OUTPUTS.md §3.A
                float u = tCenter * (_cachedWidth - 1);
                float v = mCenter * (_cachedHeight - 1);

                int u0 = (int)MathF.Floor(u);
                int u1 = Math.Min(u0 + 1, _cachedWidth - 1);
                int v0 = (int)MathF.Floor(v);
                int v1 = Math.Min(v0 + 1, _cachedHeight - 1);

                u0 = Math.Clamp(u0, 0, _cachedWidth - 1);
                v0 = Math.Clamp(v0, 0, _cachedHeight - 1);

                float tu = u - MathF.Floor(u);
                float tv = v - MathF.Floor(v);

                if (_softBiomeMasks != null)
                {
                    int cw = _cachedWidth;
                    for (int b = 0; b < biomeCount; b++)
                    {
                        float[] mask = _softBiomeMasks[b];
                        float s00 = mask[v0 * cw + u0];
                        float s10 = mask[v0 * cw + u1];
                        float s01 = mask[v1 * cw + u0];
                        float s11 = mask[v1 * cw + u1];

                        biomeAccum[b] = (1.0f - tu) * (1.0f - tv) * s00
                                      + tu * (1.0f - tv) * s10
                                      + (1.0f - tu) * tv * s01
                                      + tu * tv * s11;
                        unsharpenedAccum[b] = biomeAccum[b];
                    }
                }

                // Apply Contrast Sharpness Offset
                // Ref: 08_HEIGHT_AND_BIOME_OUTPUTS.md §3.B
                float halfSharpness = sharpness * 0.5f;
                float sumW = 0.0f;
                for (int b = 0; b < biomeCount; b++)
                {
                    biomeAccum[b] = MathF.Max(0.0f, biomeAccum[b] - halfSharpness);
                    sumW += biomeAccum[b];
                }

                // Normalize weights — Partition of Unity
                // Ref: 08_HEIGHT_AND_BIOME_OUTPUTS.md §3.C
                if (sumW > 0.0001f)
                {
                    for (int b = 0; b < biomeCount; b++)
                    {
                        results[b][x, z] = biomeAccum[b] / sumW;
                    }
                }
                else
                {
                    float sumUnsharpened = 0.0f;
                    for (int b = 0; b < biomeCount; b++)
                    {
                        sumUnsharpened += unsharpenedAccum[b];
                    }
                    if (sumUnsharpened > 0.0001f)
                    {
                        for (int b = 0; b < biomeCount; b++)
                        {
                            results[b][x, z] = unsharpenedAccum[b] / sumUnsharpened;
                        }
                    }
                    else
                    {
                        for (int b = 0; b < biomeCount; b++)
                        {
                            results[b][x, z] = 1.0f / biomeCount;
                        }
                    }
                }
            }
        }

        lock (_localCacheLock)
        {
            _localCache[ctx.Coord] = results;
        }

        if (outputPortIndex >= 0 && outputPortIndex < results.Length)
        {
            return results[outputPortIndex];
        }

        return null;
    }

    /// <summary>
    /// Clears the local sub-port evaluation cache and the base node cache.
    /// </summary>
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

    /// <summary>
    /// Clears cached data specifically for the given chunk coordinate.
    /// </summary>
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
