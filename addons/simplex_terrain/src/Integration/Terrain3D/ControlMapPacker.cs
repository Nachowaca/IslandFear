using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Service class that packs procedural splat weights into Terrain3D's native 32-bit control map format.
/// </summary>
public static class ControlMapPacker
{
    /// <summary>
    /// Packs a SplatWeightSet into a Godot Image of format Format.Rf.
    /// Uses BitConverter.UInt32BitsToSingle to write packed bits into the Red channel.
    /// </summary>
    public static Image PackToControlMap(SplatWeightSet splat)
    {
        if (splat == null)
        {
            throw new ArgumentNullException(nameof(splat));
        }

        int width = splat.Width;
        int height = splat.Height;
        int layerCount = splat.LayerCount;

        int wh = width * height;
        float[] rawFloats = new float[wh];
        ReadOnlySpan<float> splatSpan = splat.AsReadOnlySpan();

        int[] texIdMap = splat.TextureIdMap;
        bool hasTextureMap = texIdMap != null;

        for (int idx = 0; idx < wh; idx++)
        {
            float wBase = -1.0f;
            int idxBase = 0;
            float wOverlay = -1.0f;
            int idxOverlay = 0;

            // 1. Identify dominant (base) and secondary (overlay) weight layers
            for (int l = 0; l < layerCount; l++)
            {
                float w = splatSpan[l * wh + idx];
                if (w > wBase)
                {
                    wOverlay = wBase;
                    idxOverlay = idxBase;
                    wBase = w;
                    idxBase = l;
                }
                else if (w > wOverlay)
                {
                    wOverlay = w;
                    idxOverlay = l;
                }
            }

            // Map local weight indices to actual Terrain3D asset texture IDs
            int baseTexId = hasTextureMap && idxBase < texIdMap.Length ? texIdMap[idxBase] : idxBase;
            int overlayTexId = hasTextureMap && idxOverlay < texIdMap.Length ? texIdMap[idxOverlay] : idxOverlay;

            // Clamp texture IDs strictly to 5-bit bounds (0 to 31)
            if (baseTexId < 0) baseTexId = 0; else if (baseTexId > 31) baseTexId = 31;
            if (overlayTexId < 0) overlayTexId = 0; else if (overlayTexId > 31) overlayTexId = 31;

            // 2. Compute relative overlay blend ratio
            float blendRatio = 0.0f;
            float denom = wBase + wOverlay;
            if (denom > 1e-6f)
            {
                blendRatio = wOverlay / denom;
            }

            // 3. Map blend ratio [0.0, 1.0] to [0, 255] byte
            int blendByte = (int)MathF.Round(blendRatio * 255.0f);
            if (blendByte < 0) blendByte = 0; else if (blendByte > 255) blendByte = 255;

            // 4. Encode the fields into a 32-bit unsigned integer using Terrain3D's official bit layout:
            // Bits 27-31: Base texture ID (5 bits)
            // Bits 22-26: Overlay texture ID (5 bits)
            // Bits 14-21: Blend weight (8 bits, 0-255)
            // Bits 10-13: UV rotation (4 bits, 0-15)
            // Bits 7-9: UV scale (3 bits, 0-7)
            // Bit 2: Hole flag (1 bit)
            // Bit 1: Navigation flag (1 bit)
            // Bit 0: Auto-shader flag (1 bit)
            uint packedValue = (uint)((baseTexId & 0x1F) << 27) |
                              (uint)((overlayTexId & 0x1F) << 22) |
                              (uint)((blendByte & 0xFF) << 14);

            // 5. Bitcast uint to single-precision float using BCL helper
            float bitcastFloat = BitConverter.UInt32BitsToSingle(packedValue);

            // 6. Write to flat float array
            rawFloats[idx] = bitcastFloat;
        }

        byte[] byteArray = new byte[rawFloats.Length * sizeof(float)];
        Buffer.BlockCopy(rawFloats, 0, byteArray, 0, byteArray.Length);

        return Image.CreateFromData(width, height, false, Image.Format.Rf, byteArray);
    }
}
