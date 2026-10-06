using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates an aspect angle light shading mask (hillshading) from an input heightmap.
/// </summary>
public partial class AspectMapperNode : TerrainNode
{
    public AspectMapperNodeResource AssociatedResource { get; set; }

    public AspectMapperNode()
    {
        Inputs.Add(new Port("Height In", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Aspect Out", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            return ctx.AllocateHeightMatrix();
        }

        var hmIn = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        if (hmIn == null)
        {
            return ctx.AllocateHeightMatrix();
        }

        float dxDir = AssociatedResource != null ? AssociatedResource.LightDirX : 0.5f;
        float dyDir = AssociatedResource != null ? AssociatedResource.LightDirY : 1.0f;
        float dzDir = AssociatedResource != null ? AssociatedResource.LightDirZ : 0.5f;
        float wrapVal = AssociatedResource != null ? Math.Clamp(AssociatedResource.Wrap, 0.0f, 1.0f) : 0.5f;
        float lightIntensity = AssociatedResource != null ? AssociatedResource.Intensity : 1.0f;

        // Normalize light direction vector
        Vector3 lightDir = new Vector3(dxDir, dyDir, dzDir);
        if (lightDir.LengthSquared() > 0.0001f)
        {
            lightDir = lightDir.Normalized();
        }
        else
        {
            lightDir = Vector3.Up;
        }

        HeightMatrix aspectOut = ctx.AllocateHeightMatrix();
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;

        // Precompute wrap factor parameters (Ref: 05_GRID_AND_MATRIX_OPERATIONS.md §4.B)
        float w = wrapVal / 2.0f;

        for (int z = 0; z < aspectOut.Height; z++)
        {
            for (int x = 0; x < aspectOut.Width; x++)
            {
                // Calculate surface normal using boundary-clamped central difference gradients (Ref: §3.A)
                float gx = (hmIn.GetValue(x - 1, z) - hmIn.GetValue(x + 1, z)) / (2.0f * step);
                float gz = (hmIn.GetValue(x, z - 1) - hmIn.GetValue(x, z + 1)) / (2.0f * step);
                float gy = 1.0f;

                Vector3 normal = new Vector3(gx, gy, gz);
                if (normal.LengthSquared() > 0.0001f)
                {
                    normal = normal.Normalized();
                }
                else
                {
                    normal = Vector3.Up;
                }

                // Dot product between light direction and normal
                float dot = lightDir.X * normal.X + lightDir.Y * normal.Y + lightDir.Z * normal.Z;

                // Apply wrap shading
                float shadeWrap = dot * (1.0f - w) + w / 2.0f;

                aspectOut[x, z] = Math.Clamp(shadeWrap * lightIntensity, 0.0f, 1.0f);
            }
        }

        return aspectOut;
    }
}

#endregion
