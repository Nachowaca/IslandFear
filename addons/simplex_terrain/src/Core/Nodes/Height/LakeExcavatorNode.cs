using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that carves lake beds into local terrain depressions using Planchon-Darboux sink filling.
/// </summary>
public partial class LakeExcavatorNode : TerrainNode
{
    private struct Cell
    {
        public int X;
        public int Z;
        public Cell(int x, int z)
        {
            X = x;
            Z = z;
        }
    }

    public LakeExcavatorNodeResource AssociatedResource { get; set; }

    private readonly Dictionary<ChunkCoordinate, HeightMatrix[]> _localCache = new();
    private readonly object _localCacheLock = new();

    public LakeExcavatorNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("mask_in", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("lake_mask", PortType.Mask, PortDirection.Output));
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
                return null;
            }
        }

        float excavationDepth = AssociatedResource != null ? AssociatedResource.ExcavationDepth : 0.05f;
        float depthScale = AssociatedResource != null ? AssociatedResource.DepthScale : 0.02f;

        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix maskIn = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            maskIn = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix heightOut = ctx.AllocateHeightMatrix();
        HeightMatrix lakeMask = ctx.AllocateHeightMatrix();

        if (inputHM == null)
        {
            lock (_localCacheLock)
            {
                _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, lakeMask };
            }
            if (outputPortIndex == 0) return heightOut.Clone();
            return lakeMask.Clone();
        }

        int width = inputHM.Width;
        int height = inputHM.Height;
        float dScale = Math.Max(0.0001f, depthScale);

        // 1. Planchon-Darboux Sink Filling
        float[] water = new float[width * height];
        bool[] visited = new bool[width * height];
        var pq = new PriorityQueue<Cell, float>();

        // Initialize boundaries as sinks
        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                int idx = z * width + x;
                if (x == 0 || x == width - 1 || z == 0 || z == height - 1)
                {
                    water[idx] = inputHM[x, z];
                    pq.Enqueue(new Cell(x, z), inputHM[x, z]);
                    visited[idx] = true;
                }
                else
                {
                    water[idx] = float.MaxValue;
                }
            }
        }

        // Moore neighborhood directions (8-directional)
        int[] dxs = { -1, 1, 0, 0, -1, 1, -1, 1 };
        int[] dzs = { 0, 0, -1, 1, -1, -1, 1, 1 };

        while (pq.Count > 0)
        {
            Cell curr = pq.Dequeue();
            int currIdx = curr.Z * width + curr.X;
            float currWater = water[currIdx];

            for (int i = 0; i < 8; i++)
            {
                int nx = curr.X + dxs[i];
                int nz = curr.Z + dzs[i];

                if (nx >= 0 && nx < width && nz >= 0 && nz < height)
                {
                    int nIdx = nz * width + nx;
                    if (!visited[nIdx])
                    {
                        float cand = Math.Max(inputHM[nx, nz], currWater);
                        if (cand < water[nIdx])
                        {
                            water[nIdx] = cand;
                            pq.Enqueue(new Cell(nx, nz), cand);
                            visited[nIdx] = true;
                        }
                    }
                }
            }
        }

        // 2. Perform excavation
        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                int idx = z * width + x;
                float depth = water[idx] - inputHM[x, z];
                float mLake = 0.0f;

                if (depth > 0.0f)
                {
                    mLake = Math.Min(1.0f, depth / dScale);
                    if (maskIn != null)
                    {
                        mLake *= maskIn[x, z];
                    }
                }

                lakeMask[x, z] = mLake;
                heightOut[x, z] = inputHM[x, z] - excavationDepth * mLake;
            }
        }

        lock (_localCacheLock)
        {
            _localCache[ctx.Coord] = new HeightMatrix[] { heightOut, lakeMask };
        }

        if (outputPortIndex == 0) return heightOut.Clone();
        return lakeMask.Clone();
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
