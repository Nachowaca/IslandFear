namespace SimpleXTerrain;

using Godot;
using System;

/// <summary>
/// Static utility functions to map coordinates between world space and pixel/index space on the height/mask matrices.
/// </summary>
public static class CoordinateMapping
{
    /// <summary>
    /// Converts a world-space position into a 2D pixel coordinate (X, Z) on the padded grid.
    /// </summary>
    public static Vector2 WorldToPixel(Vector3 worldPos, GenerationContext ctx)
    {
        float uCore = (worldPos.X - ctx.WorldOrigin.X) / ctx.WorldSize;
        float vCore = (worldPos.Z - ctx.WorldOrigin.Z) / ctx.WorldSize;

        float px = ctx.Padding + uCore * ctx.Resolution;
        float pz = ctx.Padding + vCore * ctx.Resolution;

        return new Vector2(px, pz);
    }

    /// <summary>
    /// Converts a 2D pixel coordinate on the padded grid back into a world-space position.
    /// </summary>
    public static Vector3 PixelToWorld(Vector2 pixelPos, GenerationContext ctx)
    {
        float uCore = (pixelPos.X - ctx.Padding) / ctx.Resolution;
        float vCore = (pixelPos.Y - ctx.Padding) / ctx.Resolution;

        float wx = ctx.WorldOrigin.X + uCore * ctx.WorldSize;
        float wz = ctx.WorldOrigin.Z + vCore * ctx.WorldSize;

        return new Vector3(wx, ctx.WorldOrigin.Y, wz);
    }

    /// <summary>
    /// Performs bilinear sampling of the HeightMatrix using a world-space position.
    /// </summary>
    public static float SampleBilinearWorld(HeightMatrix matrix, Vector3 worldPos, GenerationContext ctx)
    {
        Vector2 pixelPos = WorldToPixel(worldPos, ctx);
        float normX = pixelPos.X / (matrix.Width - 1);
        float normZ = pixelPos.Y / (matrix.Height - 1);

        return matrix.SampleBilinear(normX, normZ);
    }
}
