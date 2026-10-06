using Godot;
using System;
using System.Runtime.Intrinsics;
using System.Runtime.CompilerServices;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that applies a highly optimized, separable horizontal and vertical 1D binomial Gaussian blur sweep.
/// </summary>
public partial class BlurNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public BlurNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="BlurNode"/> class.
    /// </summary>
    public BlurNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates separable binomial blur over the input height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float beta = AssociatedResource != null ? AssociatedResource.Beta : 0.5f;
        int iterations = AssociatedResource != null ? AssociatedResource.Iterations : 1;

        beta = Math.Clamp(beta, 0.001f, 1.0f);
        iterations = Math.Clamp(iterations, 1, 100);

        // Fetch upstream height matrix
        HeightMatrix inputHM = null;
        var link = InputLinks[0];
        if (link.SourceNode != null)
        {
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        if (inputHM == null)
        {
            return hm;
        }

        int width = inputHM.Width;
        int height = inputHM.Height;

        // Special check: if matrix is too small to blur, just pass it through
        if (width < 3 || height < 3)
        {
            inputHM.AsReadOnlySpan().CopyTo(hm.AsSpan());
            return hm;
        }

        // Precompute binomial coefficients
        float q = beta / 4.0f;
        float h = 1.0f - 2.0f * q;

        if (GpuTerrain.IsSupported && AssociatedResource != null && AssociatedResource.UseGpu)
        {
            var shader = GpuTerrain.LoadShader("res://addons/simplex_terrain/shaders/blur.glsl");
            if (shader.IsValid)
            {
                byte[] paramsBytes = new byte[16];
                Buffer.BlockCopy(BitConverter.GetBytes(q), 0, paramsBytes, 0, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(h), 0, paramsBytes, 4, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)width), 0, paramsBytes, 8, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)height), 0, paramsBytes, 12, 4);

                uint groupsX = (uint)Mathf.CeilToInt(width / 8.0f);
                uint groupsY = (uint)Mathf.CeilToInt(height / 8.0f);

                HeightMatrix src = inputHM;
                HeightMatrix dest = hm;

                if (iterations == 1)
                {
                    GpuTerrain.DispatchModifier(shader, src, dest, paramsBytes, groupsX, groupsY);
                }
                else
                {
                    using HeightMatrix tempBlur = new HeightMatrix(width, height);
                    for (int iter = 0; iter < iterations; iter++)
                    {
                        HeightMatrix stepDst = (iter % 2 == 0) ? tempBlur : dest;
                        GpuTerrain.DispatchModifier(shader, src, stepDst, paramsBytes, groupsX, groupsY);
                        src = stepDst;
                    }
                    if (iterations % 2 != 0)
                    {
                        tempBlur.AsReadOnlySpan().CopyTo(dest.AsSpan());
                    }
                }
                return hm;
            }
        }

        // Allocate a temporary buffer for separable pass (using IDisposable safety)
        using HeightMatrix temp = new HeightMatrix(width, height);

        HeightMatrix currentSrc = inputHM;

        for (int iter = 0; iter < iterations; iter++)
        {
            var srcSpan = currentSrc.AsReadOnlySpan();
            var tmpSpan = temp.AsSpan();

            // 1. Horizontal Pass: sweep rows, write to temp buffer
            if (Vector256.IsHardwareAccelerated)
            {
                var vQ = Vector256.Create(q);
                var vH = Vector256.Create(h);

                for (int z = 0; z < height; z++)
                {
                    int row = z * width;

                    // Interior cells - process 8 elements at a time
                    int x = 1;
                    for (; x <= width - 9; x += 8)
                    {
                        var left = Vector256.LoadUnsafe(ref Unsafe.AsRef(in srcSpan[row + x - 1]));
                        var center = Vector256.LoadUnsafe(ref Unsafe.AsRef(in srcSpan[row + x]));
                        var right = Vector256.LoadUnsafe(ref Unsafe.AsRef(in srcSpan[row + x + 1]));

                        var result = Vector256.Add(
                            Vector256.Add(Vector256.Multiply(left, vQ), Vector256.Multiply(center, vH)),
                            Vector256.Multiply(right, vQ)
                        );
                        Vector256.StoreUnsafe(result, ref tmpSpan[row + x]);
                    }

                    // Scalar tail for remaining interior elements
                    for (; x < width - 1; x++)
                    {
                        tmpSpan[row + x] = q * srcSpan[row + x - 1] + h * srcSpan[row + x] + q * srcSpan[row + x + 1];
                    }

                    // virtual clamped edge boundaries
                    tmpSpan[row] = h * srcSpan[row] + 2.0f * q * srcSpan[row + 1];
                    tmpSpan[row + width - 1] = h * srcSpan[row + width - 1] + 2.0f * q * srcSpan[row + width - 2];
                }
            }
            else
            {
                for (int z = 0; z < height; z++)
                {
                    int row = z * width;
                    // Interior cells
                    for (int x = 1; x < width - 1; x++)
                    {
                        tmpSpan[row + x] = q * srcSpan[row + x - 1] + h * srcSpan[row + x] + q * srcSpan[row + x + 1];
                    }
                    // virtual clamped edge boundaries
                    tmpSpan[row] = h * srcSpan[row] + 2.0f * q * srcSpan[row + 1];
                    tmpSpan[row + width - 1] = h * srcSpan[row + width - 1] + 2.0f * q * srcSpan[row + width - 2];
                }
            }

            // 2. Vertical Pass: sweep columns of temp, write to destination matrix
            var dstSpan = hm.AsSpan();
            var tmpSpanReadOnly = temp.AsReadOnlySpan();

            if (Vector256.IsHardwareAccelerated)
            {
                var vQ = Vector256.Create(q);     // Binomial side weight
                var vH = Vector256.Create(h);     // Binomial center weight
                var vTwoQ = Vector256.Create(2.0f * q); // Clamped edge weight

                // 1. Process interior rows (z = 1 to height - 2) in row-major order
                for (int z = 1; z < height - 1; z++)
                {
                    int row = z * width;
                    int rowPrev = (z - 1) * width;
                    int rowNext = (z + 1) * width;
                    int x = 0;

                    // Process 8 columns at a time
                    for (; x <= width - 8; x += 8)
                    {
                        var prev = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[rowPrev + x]));
                        var curr = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[row + x]));
                        var next = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[rowNext + x]));

                        var rPrev = Vector256.Multiply(prev, vQ);
                        var rCurr = Vector256.Multiply(curr, vH);
                        var rNext = Vector256.Multiply(next, vQ);

                        var result = Vector256.Add(Vector256.Add(rPrev, rCurr), rNext);
                        Vector256.StoreUnsafe(result, ref dstSpan[row + x]);
                    }

                    // Scalar tail for remaining columns
                    for (; x < width; x++)
                    {
                        dstSpan[row + x] = q * tmpSpanReadOnly[rowPrev + x] + h * tmpSpanReadOnly[row + x] + q * tmpSpanReadOnly[rowNext + x];
                    }
                }

                // 2. Vectorized Boundary Row 0 (Clamped edge)
                int x0 = 0;
                for (; x0 <= width - 8; x0 += 8)
                {
                    var curr = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[x0]));
                    var next = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[width + x0]));
                    var res = Vector256.Add(Vector256.Multiply(curr, vH), Vector256.Multiply(next, vTwoQ));
                    Vector256.StoreUnsafe(res, ref dstSpan[x0]);
                }
                for (; x0 < width; x0++)
                {
                    dstSpan[x0] = h * tmpSpanReadOnly[x0] + 2.0f * q * tmpSpanReadOnly[width + x0];
                }

                // 3. Vectorized Boundary Row (height - 1) (Clamped edge)
                int lastRow = (height - 1) * width;
                int prevRow = (height - 2) * width;
                int xl = 0;
                for (; xl <= width - 8; xl += 8)
                {
                    var curr = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[lastRow + xl]));
                    var prev = Vector256.LoadUnsafe(ref Unsafe.AsRef(in tmpSpanReadOnly[prevRow + xl]));
                    var res = Vector256.Add(Vector256.Multiply(curr, vH), Vector256.Multiply(prev, vTwoQ));
                    Vector256.StoreUnsafe(res, ref dstSpan[lastRow + xl]);
                }
                for (; xl < width; xl++)
                {
                    dstSpan[lastRow + xl] = h * tmpSpanReadOnly[lastRow + xl] + 2.0f * q * tmpSpanReadOnly[prevRow + xl];
                }
            }
            else
            {
                // Fallback row-major scalar vertical pass
                for (int z = 1; z < height - 1; z++)
                {
                    int row = z * width;
                    int rowPrev = (z - 1) * width;
                    int rowNext = (z + 1) * width;
                    for (int x = 0; x < width; x++)
                    {
                        dstSpan[row + x] = q * tmpSpanReadOnly[rowPrev + x] + h * tmpSpanReadOnly[row + x] + q * tmpSpanReadOnly[rowNext + x];
                    }
                }

                // Clamped boundaries (scalar)
                for (int x = 0; x < width; x++)
                {
                    dstSpan[x] = h * tmpSpanReadOnly[x] + 2.0f * q * tmpSpanReadOnly[width + x];
                    int lastRow = (height - 1) * width;
                    int prevRow = (height - 2) * width;
                    dstSpan[lastRow + x] = h * tmpSpanReadOnly[lastRow + x] + 2.0f * q * tmpSpanReadOnly[prevRow + x];
                }
            }

            // Subsequent iterations read from the newly updated destination matrix
            currentSrc = hm;
        }

        return hm;
    }
}

#endregion
