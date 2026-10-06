using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that clamps terrain heights below sea level and compiles shoreline & water masks.
/// </summary>
public partial class OceanLevelNode : TerrainNode
{
    public OceanLevelNodeResource AssociatedResource { get; set; }

    private readonly Dictionary<ChunkCoordinate, HeightMatrix[]> _localCache = new();
    private readonly object _localCacheLock = new();

    public OceanLevelNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("shore_mask", PortType.Mask, PortDirection.Output));
        Outputs.Add(new Port("water_mask", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(ctx.Coord, out var cached))
            {
                if (outputPortIndex == 0) return cached[0].Clone();
                if (outputPortIndex == 1) return cached[1].Clone();
                if (outputPortIndex == 2) return cached[2].Clone();
                return null;
            }
        }

        float waterLevel = AssociatedResource != null ? AssociatedResource.WaterLevel : 0.3f;
        bool clampHeights = AssociatedResource != null ? AssociatedResource.ClampHeights : true;
        float shorelineWidth = AssociatedResource != null ? AssociatedResource.ShorelineWidth : 0.05f;
        float oceanDepthScale = AssociatedResource != null ? AssociatedResource.OceanDepthScale : 2.0f;

        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix heightOut = ctx.AllocateHeightMatrix();
        HeightMatrix shoreMask = ctx.AllocateHeightMatrix();
        HeightMatrix waterMask = ctx.AllocateHeightMatrix();

        if (inputHM == null)
        {
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, shoreMask, waterMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            if (outputPortIndex == 1) return shoreMask.Clone();
            return waterMask.Clone();
        }

        int width = inputHM.Width;
        int height = inputHM.Height;
        float sWidth = Math.Max(0.0001f, shorelineWidth);

        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                float h = inputHM[x, z];

                // 1. Water mask: 1.0 if below sea level, 0.0 otherwise
                waterMask[x, z] = (h < waterLevel) ? 1.0f : 0.0f;

                // 2. Shoreline mask: 1.0 at water level, falling off to 0.0
                float dShore = MathF.Abs(h - waterLevel);
                float wShore = 0.0f;
                if (dShore <= sWidth)
                {
                    float t = 1.0f - (dShore / sWidth);
                    // Hermite cubic smoothstep
                    wShore = 3.0f * t * t - 2.0f * t * t * t;
                }
                shoreMask[x, z] = wShore;

                // 3. Height clamping & carving
                if (h < waterLevel)
                {
                    heightOut[x, z] = clampHeights ? waterLevel : waterLevel - (waterLevel - h) * oceanDepthScale;
                }
                else
                {
                    heightOut[x, z] = h;
                }
            }
        }

        lock (_localCacheLock)
        {
            _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, shoreMask, waterMask };
        }

        if (outputPortIndex == 0) return heightOut.Clone();
        if (outputPortIndex == 1) return shoreMask.Clone();
        return waterMask.Clone();
    }
    public override void ClearCache()
    {
        base.ClearCache();
        lock (_localCacheLock)
        {
            foreach (var kvp in _localCache)
            {
                if (kvp.Value != null)
                {
                    foreach (var hm in kvp.Value)
                    {
                        hm?.Dispose();
                    }
                }
            }
            _localCache.Clear();
        }
    }

    public override void ClearCacheForChunk(ChunkCoordinate coord)
    {
        base.ClearCacheForChunk(coord);
        lock (_localCacheLock)
        {
            if (_localCache.TryGetValue(coord, out var matrices))
            {
                if (matrices != null)
                {
                    foreach (var hm in matrices)
                    {
                        hm?.Dispose();
                    }
                }
                _localCache.Remove(coord);
            }
        }
    }
}

#endregion
