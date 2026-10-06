using Godot;
using System;

namespace SimpleXTerrain;

#region Resources

public enum ParallaxInterpolationMode
{
    Nearest,
    Bilinear,
    Transition
}


#endregion

#region Nodes

/// <summary>
/// Runtime node that displaces heightmap coordinate lookups along a directional offset vector.
/// </summary>
public partial class ParallaxDisplacementNode : TerrainNode
{
    public ParallaxDisplacementNodeResource AssociatedResource { get; set; }

    public ParallaxDisplacementNode()
    {
        Inputs.Add(new Port("Height In", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("Intensity Mask", PortType.Mask, PortDirection.Input)); // Optional
        Outputs.Add(new Port("Height Out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var hLink = InputLinks[0];
        if (hLink.SourceNode == null)
        {
            return ctx.AllocateHeightMatrix();
        }

        var hmIn = hLink.SourceNode.PullReadOnlyHeight(ctx, hLink.SourcePortIndex);
        if (hmIn == null)
        {
            return ctx.AllocateHeightMatrix();
        }

        // Retrieve optional intensity mask
        HeightMatrix mask = null;
        var mLink = InputLinks[1];
        if (mLink.SourceNode != null)
        {
            mask = mLink.SourceNode.PullReadOnlyHeight(ctx, mLink.SourcePortIndex);
        }

        float dirX = AssociatedResource != null ? AssociatedResource.DirectionX : 1.0f;
        float dirZ = AssociatedResource != null ? AssociatedResource.DirectionZ : 0.0f;
        float maxOffset = AssociatedResource != null ? AssociatedResource.MaxOffset : 16.0f;
        ParallaxInterpolationMode interp = AssociatedResource != null ? AssociatedResource.Interpolation : ParallaxInterpolationMode.Bilinear;

        // Normalize direction vector
        float dirLen = MathF.Sqrt(dirX * dirX + dirZ * dirZ);
        float dx = 0.0f;
        float dz = 0.0f;
        if (dirLen > 0.0001f)
        {
            dx = (dirX / dirLen) * maxOffset;
            dz = (dirZ / dirLen) * maxOffset;
        }

        HeightMatrix hmOut = ctx.AllocateHeightMatrix();

        for (int z = 0; z < hmOut.Height; z++)
        {
            for (int x = 0; x < hmOut.Width; x++)
            {
                // Bilinear-interpolated mask intensity (or 1.0 if unconnected)
                float intensity = 1.0f;
                if (mask != null)
                {
                    intensity = mask.GetValue(x, z);
                }

                // Compute displaced source coordinates in pixel space (Ref: 13_ADVANCED_TERRAIN_MODIFIERS.md §3.B)
                float srcX = x + dx * intensity;
                float srcZ = z + dz * intensity;

                // Sample the input heightmap using the chosen interpolation mode
                float displacedHeight = 0.0f;
                switch (interp)
                {
                    case ParallaxInterpolationMode.Nearest:
                        int nx = (int)MathF.Round(srcX);
                        int nz = (int)MathF.Round(srcZ);
                        displacedHeight = hmIn.GetValue(nx, nz, HeightMatrix.BoundaryMode.Clamp);
                        break;

                    case ParallaxInterpolationMode.Bilinear:
                        displacedHeight = SampleBilinear(hmIn, srcX, srcZ);
                        break;

                    case ParallaxInterpolationMode.Transition:
                        // Apply bilinear only when crossing boundary, else nearest to preserve details
                        float fx = srcX - MathF.Floor(srcX);
                        float fz = srcZ - MathF.Floor(srcZ);
                        if (MathF.Abs(fx) < 1e-4f && MathF.Abs(fz) < 1e-4f)
                        {
                            displacedHeight = hmIn.GetValue((int)MathF.Round(srcX), (int)MathF.Round(srcZ), HeightMatrix.BoundaryMode.Clamp);
                        }
                        else
                        {
                            displacedHeight = SampleBilinear(hmIn, srcX, srcZ);
                        }
                        break;
                }

                hmOut[x, z] = displacedHeight;
            }
        }

        return hmOut;
    }

    private static float SampleBilinear(HeightMatrix hm, float px, float pz)
    {
        int x0 = (int)MathF.Floor(px);
        int z0 = (int)MathF.Floor(pz);
        int x1 = x0 + 1;
        int z1 = z0 + 1;

        float tx = px - x0;
        float tz = pz - z0;

        float h00 = hm.GetValue(x0, z0, HeightMatrix.BoundaryMode.Clamp);
        float h10 = hm.GetValue(x1, z0, HeightMatrix.BoundaryMode.Clamp);
        float h01 = hm.GetValue(x0, z1, HeightMatrix.BoundaryMode.Clamp);
        float h11 = hm.GetValue(x1, z1, HeightMatrix.BoundaryMode.Clamp);

        float hBottom = h00 * (1.0f - tx) + h10 * tx;
        float hTop = h01 * (1.0f - tx) + h11 * tx;

        return hBottom * (1.0f - tz) + hTop * tz;
    }
}

#endregion
