using Godot;
using System;

namespace SimpleXTerrain;

#region Resources

public enum TextureChannel
{
    Red,
    Green,
    Blue,
    Alpha,
    Luminance
}


#endregion

#region Nodes

/// <summary>
/// Runtime node that reads an external texture asset and extracts color channels as float matrices.
/// </summary>
public partial class TextureInputNode : TerrainNode
{
    public TextureInputNodeResource AssociatedResource { get; set; }

    public TextureInputNode()
    {
        Outputs.Add(new Port("Height Out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("Mask Out", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        Texture2D tex = AssociatedResource != null ? AssociatedResource.Texture : null;
        TextureChannel channel = AssociatedResource != null ? AssociatedResource.Channel : TextureChannel.Red;

        HeightMatrix hmHeight = ctx.AllocateHeightMatrix();
        HeightMatrix hmMask = ctx.AllocateHeightMatrix();

        if (tex == null)
        {
            hmHeight.Fill(0.0f);
            hmMask.Fill(0.0f);
            if (outputPortIndex == 0) return hmHeight;
            return hmMask;
        }

        Image img = null;
        try
        {
            img = tex.GetImage();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TextureInputNode] Failed to get image from texture: {ex.Message}");
        }

        if (img == null)
        {
            hmHeight.Fill(0.0f);
            hmMask.Fill(0.0f);
            if (outputPortIndex == 0) return hmHeight;
            return hmMask;
        }

        int imgW = img.GetWidth();
        int imgH = img.GetHeight();

        float resFactor = ctx.Resolution > 0 ? (float)ctx.Resolution : 1.0f;

        for (int z = 0; z < hmHeight.Height; z++)
        {
            // Normalize coordinate within chunk bounds [0, 1] for core resolution
            float v = (float)(z - ctx.Padding) / resFactor;
            v = Math.Clamp(v, 0.0f, 1.0f);
            int py = (int)MathF.Round(v * (imgH - 1));
            py = Math.Clamp(py, 0, imgH - 1);

            for (int x = 0; x < hmHeight.Width; x++)
            {
                float u = (float)(x - ctx.Padding) / resFactor;
                u = Math.Clamp(u, 0.0f, 1.0f);
                int px = (int)MathF.Round(u * (imgW - 1));
                px = Math.Clamp(px, 0, imgW - 1);

                Color c = img.GetPixel(px, py);

                // Height value channel extraction
                float heightVal = 0.0f;
                switch (channel)
                {
                    case TextureChannel.Red:
                        heightVal = c.R;
                        break;
                    case TextureChannel.Green:
                        heightVal = c.G;
                        break;
                    case TextureChannel.Blue:
                        heightVal = c.B;
                        break;
                    case TextureChannel.Alpha:
                        heightVal = c.A;
                        break;
                    case TextureChannel.Luminance:
                        // Ref: 05_GRID_AND_MATRIX_OPERATIONS.md
                        heightVal = 0.2126f * c.R + 0.7152f * c.G + 0.0722f * c.B;
                        break;
                }

                hmHeight[x, z] = heightVal;
                hmMask[x, z] = c.A;
            }
        }

        if (outputPortIndex == 0)
        {
            hmMask.Dispose(); // We don't need this port's result
            return hmHeight;
        }
        else
        {
            hmHeight.Dispose(); // We don't need this port's result
            return hmMask;
        }
    }
}

#endregion
