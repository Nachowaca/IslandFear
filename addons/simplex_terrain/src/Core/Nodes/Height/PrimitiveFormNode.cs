using Godot;
using System;

namespace SimpleXTerrain;

#region Resources

public enum FormType
{
    GradientX,
    GradientZ,
    Pyramid,
    Cone
}

public enum TilingMode
{
    Clamp,
    Tile,
    PingPong
}


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates base geometric heightfields using parametric forms with tiling.
/// </summary>
public partial class PrimitiveFormNode : TerrainNode
{
    public PrimitiveFormNodeResource AssociatedResource { get; set; }

    public PrimitiveFormNode()
    {
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        FormType formType = AssociatedResource != null ? AssociatedResource.FormType : FormType.Cone;
        TilingMode tilingMode = AssociatedResource != null ? AssociatedResource.TilingMode : TilingMode.Clamp;
        float heightMin = AssociatedResource != null ? AssociatedResource.HeightMin : 0.0f;
        float heightMax = AssociatedResource != null ? AssociatedResource.HeightMax : 1.0f;
        float tileCount = AssociatedResource != null ? Math.Max(0.001f, AssociatedResource.TileCount) : 1.0f;

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;

        // Size of one tiling period in world units
        float tileSize = ctx.WorldSize / tileCount;

        for (int z = 0; z < hm.Height; z++)
        {
            float worldZ = ctx.WorldOrigin.Z + (z - ctx.Padding) * step;
            for (int x = 0; x < hm.Width; x++)
            {
                float worldX = ctx.WorldOrigin.X + (x - ctx.Padding) * step;

                // 1. Translate to coordinates relative to chunk origin
                float localX = worldX - ctx.WorldOrigin.X;
                float localZ = worldZ - ctx.WorldOrigin.Z;

                // 2. Apply tiling calculations
                float px = ApplyTiling(localX, tileSize, tilingMode);
                float pz = ApplyTiling(localZ, tileSize, tilingMode);

                // 3. Compute base shape value v in [0, 1]
                float v = 0.0f;
                float r = tileSize / 2.0f; // Radius for cone/pyramid

                switch (formType)
                {
                    case FormType.GradientX:
                        v = px / tileSize;
                        break;

                    case FormType.GradientZ:
                        v = pz / tileSize;
                        break;

                    case FormType.Pyramid:
                        float vx = px / tileSize;
                        float vz = pz / tileSize;
                        float vxPrime = MathF.Min(vx, 1.0f - vx);
                        float vzPrime = MathF.Min(vz, 1.0f - vz);
                        v = 2.0f * MathF.Min(vxPrime, vzPrime);
                        break;

                    case FormType.Cone:
                        float dx = px - r;
                        float dz = pz - r;
                        float dist = MathF.Sqrt(dx * dx + dz * dz);
                        v = MathF.Max(0.0f, 1.0f - dist / r);
                        break;
                }

                // 4. Map, clamp, and store height
                float mappedHeight = heightMin + v * (heightMax - heightMin);
                hm[x, z] = mappedHeight;
            }
        }

        return hm;
    }

    private static float ApplyTiling(float val, float size, TilingMode mode)
    {
        switch (mode)
        {
            case TilingMode.Clamp:
                return Math.Clamp(val, 0.0f, size);

            case TilingMode.Tile:
                float t = val % size;
                if (t < 0.0f) t += size;
                return t;

            case TilingMode.PingPong:
                float p = val % (2.0f * size);
                if (p < 0.0f) p += 2.0f * size;
                if (p >= size) return 2.0f * size - p;
                return p;

            default:
                return Math.Clamp(val, 0.0f, size);
        }
    }
}

#endregion
