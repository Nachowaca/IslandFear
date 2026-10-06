using Godot;
using System;
using System.Runtime.Intrinsics;
using System.Runtime.CompilerServices;

namespace SimpleXTerrain;

#region Resources

/// <summary>
/// Specifies the blending mathematical operation between two heightfields.
/// </summary>
public enum BlendMode
{
    Lerp,
    Add,
    Subtract,
    Multiply,
    Max,
    Min,
    Override
}


#endregion

#region Nodes

/// <summary>
/// Runtime node that combines two heightfield matrices using standard image/terrain blending formulas.
/// Supports masking and custom blending operations.
/// </summary>
public partial class BlendNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public BlendNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="BlendNode"/> class.
    /// </summary>
    public BlendNode()
    {
        Inputs.Add(new Port("height_a", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("height_b", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the blending of two heightfields over the chunk matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        BlendMode blendMode = AssociatedResource != null ? AssociatedResource.BlendMode : BlendMode.Lerp;
        float globalStrength = AssociatedResource != null ? AssociatedResource.Strength : 1.0f;

        // 1. Pull base heightfield (Height A)
        HeightMatrix hmA = null;
        var linkA = InputLinks[0];
        if (linkA.SourceNode != null)
        {
            hmA = linkA.SourceNode.PullReadOnlyHeight(ctx, linkA.SourcePortIndex);
        }

        // 2. Pull overlay heightfield (Height B)
        HeightMatrix hmB = null;
        var linkB = InputLinks[1];
        if (linkB.SourceNode != null)
        {
            hmB = linkB.SourceNode.PullReadOnlyHeight(ctx, linkB.SourcePortIndex);
        }

        // 3. Pull optional blend mask
        HeightMatrix hmMask = null;
        var linkMask = InputLinks[2];
        if (linkMask.SourceNode != null)
        {
            hmMask = linkMask.SourceNode.PullReadOnlyHeight(ctx, linkMask.SourcePortIndex);
        }

        // Allocate a new output heightfield matrix
        HeightMatrix hmOut = ctx.AllocateHeightMatrix();

        int width = hmOut.Width;
        int height = hmOut.Height;

        if (GpuTerrain.IsSupported && AssociatedResource != null && AssociatedResource.UseGpu && hmA != null && hmB != null)
        {
            var shader = GpuTerrain.LoadShader("res://addons/simplex_terrain/shaders/blend.glsl");
            if (shader.IsValid)
            {
                byte[] paramsBytes = new byte[20];
                Buffer.BlockCopy(BitConverter.GetBytes(globalStrength), 0, paramsBytes, 0, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)blendMode), 0, paramsBytes, 4, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)width), 0, paramsBytes, 8, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)height), 0, paramsBytes, 12, 4);
                float hasMaskVal = hmMask != null ? 1f : 0f;
                Buffer.BlockCopy(BitConverter.GetBytes(hasMaskVal), 0, paramsBytes, 16, 4);

                uint groupsX = (uint)Mathf.CeilToInt(width / 8.0f);
                uint groupsY = (uint)Mathf.CeilToInt(height / 8.0f);

                GpuTerrain.DispatchBlend(shader, hmA, hmB, hmMask, hmOut, paramsBytes, groupsX, groupsY);
                return hmOut;
            }
        }

        ReadOnlySpan<float> spanA = hmA != null ? hmA.AsReadOnlySpan() : default;
        ReadOnlySpan<float> spanB = hmB != null ? hmB.AsReadOnlySpan() : default;
        ReadOnlySpan<float> spanMask = hmMask != null ? hmMask.AsReadOnlySpan() : default;
        var spanOut = hmOut.AsSpan();
        bool hasA = hmA != null, hasB = hmB != null, hasMask = hmMask != null;
        int total = width * height;

        if ((blendMode == BlendMode.Lerp || blendMode == BlendMode.Override) && Vector256.IsHardwareAccelerated && hasA && hasB)
        {
            var vStrength = Vector256.Create(globalStrength);
            var vOne = Vector256.Create(1.0f);
            var vZero = Vector256<float>.Zero;
            int i = 0;

            for (; i <= total - 8; i += 8)
            {
                if (i % width == 0)
                {
                    ctx.CancellationToken.ThrowIfCancellationRequested();
                }

                var a = Vector256.LoadUnsafe(ref Unsafe.AsRef(in spanA[i]));
                var b = Vector256.LoadUnsafe(ref Unsafe.AsRef(in spanB[i]));

                Vector256<float> m;
                if (hasMask)
                {
                    var maskVal = Vector256.LoadUnsafe(ref Unsafe.AsRef(in spanMask[i]));
                    m = Vector256.Min(Vector256.Max(Vector256.Multiply(maskVal, vStrength), vZero), vOne);
                }
                else
                {
                    m = vStrength;
                }

                var result = Vector256.Add(a, Vector256.Multiply(Vector256.Subtract(b, a), m));
                Vector256.StoreUnsafe(result, ref spanOut[i]);
            }

            // Scalar tail
            for (; i < total; i++)
            {
                if (i % width == 0)
                {
                    ctx.CancellationToken.ThrowIfCancellationRequested();
                }
                float a = spanA[i];
                float b = spanB[i];
                float m = hasMask ? spanMask[i] : 1.0f;
                m = Math.Clamp(m * globalStrength, 0.0f, 1.0f);
                spanOut[i] = a + (b - a) * m;
            }
        }
        else
        {
            for (int i = 0; i < total; i++)
            {
                if (i % width == 0)
                {
                    ctx.CancellationToken.ThrowIfCancellationRequested();
                }

                float a = hasA ? spanA[i] : 0.0f;
                float b = hasB ? spanB[i] : 0.0f;

                // Compute final weight mask value
                float m = hasMask ? spanMask[i] : 1.0f;
                m = Math.Clamp(m * globalStrength, 0.0f, 1.0f);

                float result = a;

                switch (blendMode)
                {
                    case BlendMode.Lerp:
                    case BlendMode.Override:
                        result = a + (b - a) * m;
                        break;
                    case BlendMode.Add:
                        result = a + b * m;
                        break;
                    case BlendMode.Subtract:
                        result = a - b * m;
                        break;
                    case BlendMode.Multiply:
                        result = Mathf.Lerp(a, a * b, m);
                        break;
                    case BlendMode.Max:
                        result = Mathf.Lerp(a, Math.Max(a, b), m);
                        break;
                    case BlendMode.Min:
                        result = Mathf.Lerp(a, Math.Min(a, b), m);
                        break;
                }

                spanOut[i] = result;
            }
        }

        return hmOut;
    }
}

#endregion
