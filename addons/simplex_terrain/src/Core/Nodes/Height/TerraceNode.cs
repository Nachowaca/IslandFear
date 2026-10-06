using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that quantizes continuous slopes into flat horizontal steps with smooth transitions.
/// </summary>
public partial class TerraceNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public TerraceNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="TerraceNode"/> class.
    /// </summary>
    public TerraceNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    private static float LcgRandom(ref uint state)
    {
        state = 214013u * state + 2531011u;
        return ((state >> 16) & 0x7FFFu) / 32768.0f;
    }

    /// <summary>
    /// Evaluates terracing over the input height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int steps = AssociatedResource != null ? AssociatedResource.Steps : 8;
        float steepness = AssociatedResource != null ? AssociatedResource.Steepness : 0.5f;
        float uniformity = AssociatedResource != null ? AssociatedResource.Uniformity : 1.0f;
        int seed = AssociatedResource != null ? AssociatedResource.JitterSeed : 42;

        steps = Math.Clamp(steps, 2, 256);
        steepness = Math.Clamp(steepness, 0.0f, 1.0f);
        uniformity = Math.Clamp(uniformity, 0.0f, 1.0f);

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

        // 1. Generate Uniform and Jittered Step Array on Stack
        Span<float> tSteps = stackalloc float[steps];
        for (int k = 0; k < steps; k++)
        {
            tSteps[k] = (float)k / (steps - 1);
        }

        if (uniformity < 1.0f)
        {
            uint state = (uint)seed;
            // Apply single sweep pass of deterministic jittering
            for (int k = 1; k < steps - 1; k++)
            {
                float rJitter = LcgRandom(ref state);
                float jitteredVal = tSteps[k - 1] + rJitter * (tSteps[k + 1] - tSteps[k - 1]);
                tSteps[k] = tSteps[k] * uniformity + jitteredVal * (1.0f - uniformity);
            }
        }

        // Blend intensity factor
        float blendIntensity = MathF.Sqrt(steepness);

        var spanIn = inputHM.AsReadOnlySpan();
        var spanOut = hm.AsSpan();
        int total = hm.Width * hm.Height;

        for (int i = 0; i < total; i++)
        {
            if (i % hm.Width == 0)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
            }

            float v = spanIn[i];

            // 2. Find interval k containing v
            int k = 0;
            for (int j = 0; j < steps - 1; j++)
            {
                if (v >= tSteps[j] && v <= tSteps[j + 1])
                {
                    k = j;
                    break;
                }
            }
            if (v > tSteps[steps - 1])
            {
                k = steps - 2;
            }
            else if (v < tSteps[0])
            {
                k = 0;
            }

            float tK = tSteps[k];
            float tK1 = tSteps[k + 1];

            // 3. Compute relative position
            float range = tK1 - tK;
            float xRel = range > 1e-6f ? (v - tK) / range : 0.0f;
            xRel = Math.Clamp(xRel, 0.0f, 1.0f);

            // 4. Smooth Hermite cubic spline fade
            float p = xRel * xRel * (3.0f - 2.0f * xRel);

            // 5. Shift and scale to centered range [-1, 1]
            float pCentered = 2.0f * p - 1.0f;

            // 6. Apply steepness contrast parameter S_steep
            float pScaled;
            if (MathF.Abs(pCentered) < 1e-7f)
            {
                pScaled = 0.0f;
            }
            else
            {
                pScaled = MathF.Sign(pCentered) * MathF.Pow(MathF.Abs(pCentered), 1.0f - steepness);
            }

            // 7. Remap back to interval [0, 1]
            float pFinal = 0.5f * pScaled + 0.5f;

            // 8. Interpolate the terraced target height
            float vTarget = tK * (1.0f - pFinal) + tK1 * pFinal;

            // 9. Blend with original value
            spanOut[i] = vTarget * blendIntensity + v * (1.0f - blendIntensity);
        }

        return hm;
    }
}

#endregion
