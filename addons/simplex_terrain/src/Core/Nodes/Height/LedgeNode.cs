using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that creates flat horizontal plateaus (cliffs) at specific height contours.
/// </summary>
public partial class LedgeNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public LedgeNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="LedgeNode"/> class.
    /// </summary>
    public LedgeNode()
    {
        Inputs.Add(new Port("HeightIn", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("Mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("HeightOut", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the ledge contour deformation over the height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float contourLevel = AssociatedResource != null ? AssociatedResource.ContourLevel : 0.5f;
        float topShoulder = AssociatedResource != null ? AssociatedResource.TopShoulder : 0.15f;
        float bottomShoulder = AssociatedResource != null ? AssociatedResource.BottomShoulder : 0.1f;
        float cliffHeight = AssociatedResource != null ? AssociatedResource.CliffHeight : 0.3f;
        float steepness = AssociatedResource != null ? AssociatedResource.Steepness : 20.0f;
        float blurRadius = AssociatedResource != null ? AssociatedResource.BlurRadius : 2.0f;

        // Defensive clamping
        steepness = MathF.Max(0.001f, steepness);
        topShoulder = MathF.Max(0.0f, topShoulder);
        bottomShoulder = MathF.Max(0.0f, bottomShoulder);
        cliffHeight = MathF.Max(0.0f, cliffHeight);
        blurRadius = MathF.Max(0.0f, blurRadius);

        // Fetch upstream height matrix
        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        // Fetch intensity mask
        HeightMatrix maskInput = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            maskInput = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        if (inputHM == null)
        {
            return hm;
        }

        int width = inputHM.Width;
        int height = inputHM.Height;

        // 1. Create the contour-smoothed heightmap mask (H_mask)
        HeightMatrix maskHM;
        if (blurRadius > 2.0f)
        {
            int factor = (int)MathF.Floor(blurRadius);
            maskHM = DownsampleBlur(inputHM, factor, 1.75f);
        }
        else if (blurRadius > 0.0f)
        {
            maskHM = GaussianBlur(inputHM, blurRadius);
        }
        else
        {
            maskHM = inputHM; // No smoothing, point directly
        }

        // 2. Precompute core mathematical boundaries for deformation (where intensity is not applied)
        float halfCliff = cliffHeight * 0.5f;

        // 3. Process each pixel according to contour region classification
        var spanIn = inputHM.AsReadOnlySpan();
        var spanMask = maskHM.AsReadOnlySpan();
        ReadOnlySpan<float> spanMaskInput = maskInput != null ? maskInput.AsReadOnlySpan() : default;
        var spanOut = hm.AsSpan();
        bool hasMaskInput = maskInput != null;
        int total = width * height;

        for (int i = 0; i < total; i++)
        {
            if (i % width == 0)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
            }

            float h = spanIn[i];
            float m = spanMask[i];
            float I_val = hasMaskInput ? spanMaskInput[i] : 1.0f;

            float halfCliff_I = halfCliff * I_val;
            float start = contourLevel - (1.0f / steepness) * I_val;
            float end = contourLevel + (1.0f / steepness) * I_val;

            float startShoulder = start - (halfCliff_I * bottomShoulder);
            float endShoulder = end + (halfCliff_I * topShoulder);

            float invLedgeRange = MathF.Abs(end - start) > 1e-6f ? 1.0f / (end - start) : 0.0f;
            float invBottomRange = MathF.Abs(start - startShoulder) > 1e-6f ? 1.0f / (start - startShoulder) : 0.0f;
            float invTopRange = MathF.Abs(endShoulder - end) > 1e-6f ? 1.0f / (endShoulder - end) : 0.0f;

            if (m > start && m < end)
            {
                // Ledge Core
                float p = (m - start) * invLedgeRange;
                float pSmooth = 3.0f * p * p - 2.0f * p * p * p;
                spanOut[i] = (h - halfCliff_I) * (1.0f - pSmooth) + (h + halfCliff_I) * pSmooth;
            }
            else if (m > startShoulder && m <= start)
            {
                // Bottom Shoulder
                float p = (m - startShoulder) * invBottomRange;
                float pSmooth = 3.0f * p * p - 2.0f * p * p * p;
                spanOut[i] = h - halfCliff_I * pSmooth;
            }
            else if (m >= end && m < endShoulder)
            {
                // Top Shoulder
                float p = (endShoulder - m) * invTopRange;
                float pSmooth = 3.0f * p * p - 2.0f * p * p * p;
                spanOut[i] = h + halfCliff_I * pSmooth;
            }
            else
            {
                // Unaffected Zone
                spanOut[i] = h;
            }
        }

        // Clean up temporary blurred matrix if we allocated a new one
        if (maskHM != inputHM)
        {
            maskHM.Dispose();
        }

        return hm;
    }

    private static HeightMatrix Downsample(HeightMatrix src, int factor)
    {
        int srcW = src.Width;
        int srcH = src.Height;
        int dstW = Math.Max(1, srcW / factor);
        int dstH = Math.Max(1, srcH / factor);
        HeightMatrix dst = new HeightMatrix(dstW, dstH);
        var srcSpan = src.AsReadOnlySpan();
        var dstSpan = dst.AsSpan();

        for (int z = 0; z < dstH; z++)
        {
            int sz = Math.Clamp(z * factor, 0, srcH - 1);
            int dstRowOff = z * dstW;
            int srcRowOff = sz * srcW;
            for (int x = 0; x < dstW; x++)
            {
                int sx = Math.Clamp(x * factor, 0, srcW - 1);
                dstSpan[dstRowOff + x] = srcSpan[srcRowOff + sx];
            }
        }
        return dst;
    }

    private static HeightMatrix Upsample(HeightMatrix src, int targetW, int targetH, int factor)
    {
        HeightMatrix dst = new HeightMatrix(targetW, targetH);
        var srcSpan = src.AsReadOnlySpan();
        var dstSpan = dst.AsSpan();
        int srcW = src.Width;
        int srcH = src.Height;

        for (int z = 0; z < targetH; z++)
        {
            float srcZ = (float)z / factor;
            int z0 = (int)MathF.Floor(srcZ);
            int z1 = Math.Min(z0 + 1, srcH - 1);
            float tz = srcZ - z0;
            z0 = Math.Clamp(z0, 0, srcH - 1);

            int dstRowOff = z * targetW;
            int z0Off = z0 * srcW;
            int z1Off = z1 * srcW;

            for (int x = 0; x < targetW; x++)
            {
                float srcX = (float)x / factor;
                int x0 = (int)MathF.Floor(srcX);
                int x1 = Math.Min(x0 + 1, srcW - 1);
                float tx = srcX - x0;
                x0 = Math.Clamp(x0, 0, srcW - 1);

                float h00 = srcSpan[z0Off + x0];
                float h10 = srcSpan[z0Off + x1];
                float h01 = srcSpan[z1Off + x0];
                float h11 = srcSpan[z1Off + x1];

                float h0 = h00 * (1f - tx) + h10 * tx;
                float h1 = h01 * (1f - tx) + h11 * tx;
                dstSpan[dstRowOff + x] = h0 * (1f - tz) + h1 * tz;
            }
        }
        return dst;
    }

    private static HeightMatrix DownsampleBlur(HeightMatrix src, int factor, float radius)
    {
        using HeightMatrix downsampled = Downsample(src, factor);
        using HeightMatrix blurred = GaussianBlur(downsampled, radius);
        return Upsample(blurred, src.Width, src.Height, factor);
    }

    private static HeightMatrix GaussianBlur(HeightMatrix src, float radius)
    {
        int w = src.Width;
        int h = src.Height;
        HeightMatrix dst = new HeightMatrix(w, h);
        int kernelSize = (int)MathF.Round(radius * 3.0f) * 2 + 1;
        if (kernelSize < 3) kernelSize = 3;
        if (kernelSize > 25) kernelSize = 25;

        Span<float> kernel = stackalloc float[kernelSize];
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
        var srcSpan = src.AsReadOnlySpan();
        var tempSpan = temp.AsSpan();
        var dstSpan = dst.AsSpan();

        for (int z = 0; z < h; z++)
        {
            int rowOff = z * w;
            for (int x = 0; x < w; x++)
            {
                float val = 0.0f;
                for (int k = 0; k < kernelSize; k++)
                {
                    int kx = Math.Clamp(x + k - half, 0, w - 1);
                    val += srcSpan[rowOff + kx] * kernel[k];
                }
                tempSpan[rowOff + x] = val;
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
                    val += tempSpan[kz * w + x] * kernel[k];
                }
                dstSpan[z * w + x] = val;
            }
        }
        temp.Dispose();
        return dst;
    }
}

#endregion
