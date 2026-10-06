using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that analyzes local height field gradients and selects slopes matching an angular target range.
/// </summary>
public partial class SlopeNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SlopeNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SlopeNode"/> class.
    /// </summary>
    public SlopeNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Mask", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates slope range selection and outputs a [0, 1] weight mask.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float minAngle = AssociatedResource != null ? AssociatedResource.MinAngle : 0.0f;
        float maxAngle = AssociatedResource != null ? AssociatedResource.MaxAngle : 90.0f;
        float smoothAngle = AssociatedResource != null ? AssociatedResource.SmoothAngle : 5.0f;
        float pixelSize = ctx.WorldSize / (float)ctx.Resolution;
        float heightScale = ctx.HeightScale;

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

        // Prevent division-by-zero on scale parameters
        float hScale = MathF.Abs(heightScale) > 1e-6f ? heightScale : 1.0f;
        float ratioFactor = pixelSize / hScale;

        // Compute angle boundaries in degrees clamped strictly to [0, 90]
        float thetaA = Math.Clamp(minAngle - smoothAngle / 2.0f, 0.0f, 90.0f);
        float thetaB = Math.Clamp(minAngle + smoothAngle / 2.0f, 0.0f, 90.0f);
        float thetaC = Math.Clamp(maxAngle - smoothAngle / 2.0f, 0.0f, 90.0f);
        float thetaD = Math.Clamp(maxAngle + smoothAngle / 2.0f, 0.0f, 90.0f);

        // Convert angles to radians and project to tangents
        float dMin0 = MathF.Tan(thetaA * MathF.PI / 180.0f) * ratioFactor;
        float dMin1 = (thetaB >= 89.9f) ? float.MaxValue : MathF.Tan(thetaB * MathF.PI / 180.0f) * ratioFactor;
        float dMax0 = (thetaC >= 89.9f) ? float.MaxValue : MathF.Tan(thetaC * MathF.PI / 180.0f) * ratioFactor;
        float dMax1 = (thetaD >= 89.9f) ? float.MaxValue : MathF.Tan(thetaD * MathF.PI / 180.0f) * ratioFactor;

        bool disableMinLimit = minAngle <= 0.0f;

        // We require at least 3x3 dimension to perform neighbor analysis
        if (width < 3 || height < 3)
        {
            return hm; // Output flat zero mask
        }

        ReadOnlySpan<float> spanIn = inputHM.AsReadOnlySpan();
        Span<float> spanOut = hm.AsSpan();

        for (int z = 0; z < height; z++)
        {
            // Replicate boundary derivatives: clamp neighbors internally
            int cz = Math.Clamp(z, 1, height - 2);
            int rowOffset = cz * width;
            int rowPrev = (cz - 1) * width;
            int rowNext = (cz + 1) * width;

            for (int x = 0; x < width; x++)
            {
                int cx = Math.Clamp(x, 1, width - 2);

                float centerH = spanIn[rowOffset + cx];

                // Four orthogonal neighbors at clamped inner coordinate
                float hLeft = spanIn[rowOffset + (cx - 1)];
                float hRight = spanIn[rowOffset + (cx + 1)];
                float hUp = spanIn[rowPrev + cx];
                float hDown = spanIn[rowNext + cx];

                // Central difference gradient calculation for smooth, anti-aliased slope gradients
                float dx = (hRight - hLeft) * 0.5f;
                float dz = (hDown - hUp) * 0.5f;
                float dDelta = MathF.Sqrt(dx * dx + dz * dz);

                // Range Selection Filter
                float mSlope = 0.0f;
                if (disableMinLimit)
                {
                    if (dDelta > dMax1)
                    {
                        mSlope = 0.0f;
                    }
                    else if (dDelta < dMax0)
                    {
                        mSlope = 1.0f;
                    }
                    else // between dMax0 and dMax1
                    {
                        float range = dMax1 - dMax0;
                        float pMax = (range > 1e-6f) ? 1.0f - (dDelta - dMax0) / range : 0.0f;
                        mSlope = Math.Clamp(pMax, 0.0f, 1.0f);
                    }
                }
                else
                {
                    if (dDelta < dMin0 || dDelta > dMax1)
                    {
                        mSlope = 0.0f;
                    }
                    else if (dDelta > dMin1 && dDelta < dMax0)
                    {
                        mSlope = 1.0f;
                    }
                    else if (dDelta >= dMin0 && dDelta <= dMin1)
                    {
                        float range = dMin1 - dMin0;
                        float pMin = (range > 1e-6f) ? (dDelta - dMin0) / range : 1.0f;
                        mSlope = Math.Clamp(pMin, 0.0f, 1.0f);
                    }
                    else if (dDelta >= dMax0 && dDelta <= dMax1)
                    {
                        float range = dMax1 - dMax0;
                        float pMax = (range > 1e-6f) ? 1.0f - (dDelta - dMax0) / range : 0.0f;
                        mSlope = Math.Clamp(pMax, 0.0f, 1.0f);
                    }
                }

                spanOut[z * width + x] = mSlope;
            }
        }

        return hm;
    }
}

#endregion
