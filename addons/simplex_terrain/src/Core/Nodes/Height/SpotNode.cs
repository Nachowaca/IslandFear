using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates a radial hill/crater stamp on the heightmap using a smooth Hermite cubic falloff.
/// </summary>
public partial class SpotNode : TerrainNode
{
    public SpotNodeResource AssociatedResource { get; set; }

    public SpotNode()
    {
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float radius = AssociatedResource != null ? Math.Max(0.001f, AssociatedResource.Radius) : 256.0f;
        float hardness = AssociatedResource != null ? Math.Clamp(AssociatedResource.Hardness, 0.0f, 0.999f) : 0.5f;
        float heightVal = AssociatedResource != null ? AssociatedResource.Height : 1.0f;
        float centerX = AssociatedResource != null ? AssociatedResource.CenterX : 0.5f;
        float centerZ = AssociatedResource != null ? AssociatedResource.CenterZ : 0.5f;

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;

        // Calculate center position in absolute world space
        float cx = centerX;
        float cz = centerZ;

        for (int z = 0; z < hm.Height; z++)
        {
            float worldZ = ctx.WorldOrigin.Z + (z - ctx.Padding) * step;
            for (int x = 0; x < hm.Width; x++)
            {
                float worldX = ctx.WorldOrigin.X + (x - ctx.Padding) * step;

                // Euclidean distance to spot center
                float dx = worldX - cx;
                float dz = worldZ - cz;
                float dist = MathF.Sqrt(dx * dx + dz * dz);
                float u = dist / radius;

                float w = 0.0f;
                if (u <= hardness)
                {
                    w = 1.0f;
                }
                else if (u < 1.0f)
                {
                    w = (1.0f - u) / (1.0f - hardness);
                }

                // Hermite cubic smoothstep: 3w^2 - 2w^3
                float shapeFactor = 3.0f * w * w - 2.0f * w * w * w;

                hm[x, z] = shapeFactor * heightVal;
            }
        }

        return hm;
    }
}

#endregion
