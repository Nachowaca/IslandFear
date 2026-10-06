using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that executes a nested biome sub-graph dynamically.
/// </summary>
public partial class BiomeReferenceNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public BiomeReferenceNodeResource AssociatedResource { get; set; }

    private readonly object _subGraphLock = new();
    private Dictionary<string, TerrainNode> _subGraphNodes = null;
    private TerrainNode _subGraphHeightOutput = null;
    private TerrainNode _subGraphSplatOutput = null;
    private TerrainNode _subGraphInstanceOutput = null;

    /// <summary>
    /// Initializes a new instance of the <see cref="BiomeReferenceNode"/> class.
    /// </summary>
    public BiomeReferenceNode()
    {
        Inputs.Add(new Port("weight_mask", PortType.Mask, PortDirection.Input));
        
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("splat_out", PortType.Splat, PortDirection.Output));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));

        InitializePorts();
    }

    /// <summary>
    /// Initializes the nested sub-graph runtime nodes in a thread-safe lazy-loaded manner.
    /// </summary>
    private void InitializeSubGraph()
    {
        lock (_subGraphLock)
        {
            if (_subGraphNodes != null) return;

            var subGraph = AssociatedResource?.SubGraph;
            if (subGraph == null) return;

            try
            {
                _subGraphNodes = GraphEvaluator.InstantiateGraphNodes(subGraph);

                // Find terminal outputs in the sub-graph
                foreach (var kvp in _subGraphNodes)
                {
                    var node = kvp.Value;
                    if (node is HeightOutputNode)
                    {
                        _subGraphHeightOutput = node;
                    }
                    else if (node is Terrain3DControlOutputNode)
                    {
                        _subGraphSplatOutput = node;
                    }
                    else if (node is Terrain3DInstancerOutputNode)
                    {
                        _subGraphInstanceOutput = node;
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[BiomeReferenceNode] Error instantiating sub-graph: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Evaluates the sub-graph and applies the spatial weight mask to the output data.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        // 1. Pull the weight mask from our input port 0
        HeightMatrix weightMask = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            weightMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        // Optimization: If the biome weight mask is completely zero, bypass evaluating this biome graph entirely!
        bool isZero = true;
        if (weightMask != null)
        {
            var span = weightMask.AsReadOnlySpan();
            for (int i = 0; i < span.Length; i++)
            {
                if (span[i] > 1e-5f)
                {
                    isZero = false;
                    break;
                }
            }
        }
        else
        {
            isZero = false;
        }

        if (isZero)
        {
            switch (outputPortIndex)
            {
                case 0: // height_out
                    return ctx.AllocateHeightMatrix();
                case 1: // splat_out
                    int fWidth = weightMask != null ? weightMask.Width : ctx.PaddedSize;
                    int fHeight = weightMask != null ? weightMask.Height : ctx.PaddedSize;
                    var fallbackSplat = new SplatWeightSet(fWidth, fHeight, 2);
                    fallbackSplat.TextureIdMap = new int[] { 0, 1 };
                    return fallbackSplat;
                case 2: // instance_out
                    return new InstanceSet();
                default:
                    throw new ArgumentOutOfRangeException(nameof(outputPortIndex), $"Invalid output port index {outputPortIndex}.");
            }
        }

        InitializeSubGraph();

        switch (outputPortIndex)
        {
            case 0: // height_out (PortType.Height)
                // Return raw sub-graph height WITHOUT pre-multiplying by weight mask.
                // BiomeBlendNode handles the weighting via its weight input ports.
                // Pre-multiplying here would cause double-application (w² instead of w).
                if (_subGraphHeightOutput != null && _subGraphHeightOutput.InputLinks.Length > 0 && _subGraphHeightOutput.InputLinks[0].SourceNode != null)
                {
                    var link = _subGraphHeightOutput.InputLinks[0];
                    var rawHeight = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
                    if (rawHeight != null)
                    {
                        // Clone to avoid double-dispose: our cache will Dispose this,
                        // and the sub-graph's cache owns the original.
                        return rawHeight.Clone();
                    }
                }
                // Fallback: return default HeightMatrix (0.0f)
                return ctx.AllocateHeightMatrix();

            case 1: // splat_out (PortType.Splat)
                // Return raw sub-graph splat WITHOUT pre-multiplying by weight mask.
                // BiomeBlendNode handles the weighting via its weight input ports.
                if (_subGraphSplatOutput != null && _subGraphSplatOutput.InputLinks.Length > 0 && _subGraphSplatOutput.InputLinks[0].SourceNode != null)
                {
                    var link = _subGraphSplatOutput.InputLinks[0];
                    var rawSplat = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplatWeightSet;
                    if (rawSplat != null)
                    {
                        // Clone to avoid double-dispose: our cache will Dispose this,
                        // and the sub-graph's cache owns the original.
                        return rawSplat.Clone();
                    }
                }
                // Fallback: return a default 2-layer empty SplatWeightSet
                int fWidth2 = weightMask != null ? weightMask.Width : ctx.PaddedSize;
                int fHeight2 = weightMask != null ? weightMask.Height : ctx.PaddedSize;
                var fallbackSplat2 = new SplatWeightSet(fWidth2, fHeight2, 2);
                fallbackSplat2.TextureIdMap = new int[] { 0, 1 };
                return fallbackSplat2;

            case 2: // instance_out (PortType.Instance)
                if (_subGraphInstanceOutput != null && _subGraphInstanceOutput.InputLinks.Length > 0 && _subGraphInstanceOutput.InputLinks[0].SourceNode != null)
                {
                    var link = _subGraphInstanceOutput.InputLinks[0];
                    var rawInstances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
                    if (rawInstances != null)
                    {
                        var filteredInstances = new InstanceSet();
                        foreach (var inst in rawInstances.Instances)
                        {
                            float w = 1.0f;
                            if (weightMask != null)
                            {
                                w = CoordinateMapping.SampleBilinearWorld(weightMask, inst.Position, ctx);
                            }

                            // Deterministic roll based on instance coordinates hash
                            uint seed = inst.Hash ^ 987654321;
                            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
                            float randVal = (float)seed / 0x7fffffff;
                            if (randVal <= w)
                            {
                                filteredInstances.Add(inst);
                            }
                        }
                        return filteredInstances;
                    }
                }
                // Fallback: return empty InstanceSet
                return new InstanceSet();

            default:
                throw new ArgumentOutOfRangeException(nameof(outputPortIndex), $"Invalid output port index {outputPortIndex}.");
        }
    }

    /// <summary>
    /// Propagates cache clearing to all instantiated sub-graph nodes.
    /// </summary>
    public override void ClearCache()
    {
        base.ClearCache();
        lock (_subGraphLock)
        {
            if (_subGraphNodes != null)
            {
                foreach (var kvp in _subGraphNodes)
                {
                    kvp.Value.ClearCache();
                }
            }
        }
    }

    /// <summary>
    /// Propagates cache clearing for a specific chunk coordinate to all nested sub-graph nodes.
    /// </summary>
    public override void ClearCacheForChunk(ChunkCoordinate coord)
    {
        base.ClearCacheForChunk(coord);
        lock (_subGraphLock)
        {
            if (_subGraphNodes != null)
            {
                foreach (var kvp in _subGraphNodes)
                {
                    kvp.Value.ClearCacheForChunk(coord);
                }
            }
        }
    }
}

#endregion
