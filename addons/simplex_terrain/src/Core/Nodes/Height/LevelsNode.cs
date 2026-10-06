using Godot;
using System;
using System.Runtime.Intrinsics;
using System.Runtime.CompilerServices;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that performs range remapping and symmetrical gamma adjustment.
/// </summary>
public partial class LevelsNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public LevelsNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="LevelsNode"/> class.
    /// </summary>
    public LevelsNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates levels adjustments over the input height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float iMin = AssociatedResource != null ? AssociatedResource.InputMin : 0.0f;
        float iMax = AssociatedResource != null ? AssociatedResource.InputMax : 1.0f;
        float oMin = AssociatedResource != null ? AssociatedResource.OutputMin : 0.0f;
        float oMax = AssociatedResource != null ? AssociatedResource.OutputMax : 1.0f;
        float gamma = AssociatedResource != null ? AssociatedResource.Gamma : 1.0f;
        bool enableClamping = AssociatedResource != null ? AssociatedResource.EnableClamping : true;

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
            float iRangeNull = iMax - iMin;
            float invRangeNull = MathF.Abs(iRangeNull) > 1e-6f ? 1.0f / iRangeNull : 0.0f;
            float gammaClamped = Math.Clamp(gamma, 0.001f, 1.999f);
            float exponentNull = (gammaClamped < 1.0f) ? gammaClamped : (1.0f / (2.0f - gammaClamped));
            bool isLinearNull = MathF.Abs(exponentNull - 1.0f) < 1e-5f;

            float v = 0.0f;
            float vClamped = enableClamping ? Math.Clamp(v, Math.Min(iMin, iMax), Math.Max(iMin, iMax)) : Math.Max(v, Math.Min(iMin, iMax));
            float vScaled = (vClamped - iMin) * invRangeNull;
            if (enableClamping) vScaled = Math.Clamp(vScaled, 0.0f, 1.0f);
            else vScaled = Math.Max(vScaled, 0.0f);

            float vGamma = isLinearNull ? vScaled : MathF.Pow(vScaled, exponentNull);
            float constValue = oMin + vGamma * (oMax - oMin);

            hm.AsSpan().Fill(constValue);
            return hm;
        }

        // Precompute division factors to avoid inner loop overhead
        float iRange = iMax - iMin;
        float invRange = MathF.Abs(iRange) > 1e-6f ? 1.0f / iRange : 0.0f;
        
        // Symmetrical gamma exponent precomputation
        gamma = Math.Clamp(gamma, 0.001f, 1.999f); // Avoid division-by-zero or infinite values
        float exponent = (gamma < 1.0f) ? gamma : (1.0f / (2.0f - gamma));

        ReadOnlySpan<float> spanIn = inputHM.AsReadOnlySpan();
        Span<float> spanOut = hm.AsSpan();
        int total = hm.Width * hm.Height;
        int width = hm.Width;

        // Fast-path: Symmetrical gamma exponent is 1.0f (or close to it)
        bool isLinear = MathF.Abs(exponent - 1.0f) < 1e-5f;

        if (isLinear && Vector256.IsHardwareAccelerated)
        {
            var vIMin = Vector256.Create(iMin);
            var vOMin = Vector256.Create(oMin);
            var vOMaxMinusOMin = Vector256.Create(oMax - oMin);
            var vInvRange = Vector256.Create(invRange);
            var vZero = Vector256<float>.Zero;
            var vOne = Vector256.Create(1.0f);
            
            var vLimitMin = Vector256.Create(Math.Min(iMin, iMax));
            var vLimitMax = Vector256.Create(Math.Max(iMin, iMax));

            int i = 0;
            for (; i <= total - 8; i += 8)
            {
                if (i % width == 0) ctx.CancellationToken.ThrowIfCancellationRequested();

                var v = Vector256.LoadUnsafe(ref Unsafe.AsRef(in spanIn[i]));
                
                Vector256<float> vScaledClamped;
                if (enableClamping)
                {
                    var vClamped = Vector256.Min(Vector256.Max(v, vLimitMin), vLimitMax);
                    var vScaled = Vector256.Multiply(Vector256.Subtract(vClamped, vIMin), vInvRange);
                    vScaledClamped = Vector256.Min(Vector256.Max(vScaled, vZero), vOne);
                }
                else
                {
                    var vClamped = Vector256.Max(v, vLimitMin);
                    vScaledClamped = Vector256.Max(Vector256.Multiply(Vector256.Subtract(vClamped, vIMin), vInvRange), vZero);
                }

                var outVal = Vector256.Add(vOMin, Vector256.Multiply(vScaledClamped, vOMaxMinusOMin));
                Vector256.StoreUnsafe(outVal, ref spanOut[i]);
            }

            // Scalar tail
            for (; i < total; i++)
            {
                if (i % width == 0) ctx.CancellationToken.ThrowIfCancellationRequested();

                float v = spanIn[i];
                float vClamped = enableClamping ? Math.Clamp(v, Math.Min(iMin, iMax), Math.Max(iMin, iMax)) : Math.Max(v, Math.Min(iMin, iMax));
                float vScaled = (vClamped - iMin) * invRange;
                if (enableClamping) vScaled = Math.Clamp(vScaled, 0.0f, 1.0f);
                else vScaled = Math.Max(vScaled, 0.0f);

                spanOut[i] = oMin + vScaled * (oMax - oMin);
            }
        }
        else
        {
            // Scalar path
            for (int i = 0; i < total; i++)
            {
                if (i % width == 0)
                {
                    ctx.CancellationToken.ThrowIfCancellationRequested();
                }

                float v = spanIn[i];
                float vClamped = enableClamping ? Math.Clamp(v, Math.Min(iMin, iMax), Math.Max(iMin, iMax)) : Math.Max(v, Math.Min(iMin, iMax));
                float vScaled = (vClamped - iMin) * invRange;
                if (enableClamping) vScaled = Math.Clamp(vScaled, 0.0f, 1.0f);
                else vScaled = Math.Max(vScaled, 0.0f);

                float vGamma = isLinear ? vScaled : MathF.Pow(vScaled, exponent);
                spanOut[i] = oMin + vGamma * (oMax - oMin);
            }
        }



        return hm;
    }
}

#endregion
