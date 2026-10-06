using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources




#endregion

#region Nodes

/// <summary>
/// Runtime node that iteratively runs a sub-graph for a specified number of passes.
/// </summary>
public partial class LoopNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public LoopNodeResource AssociatedResource { get; set; }

    private readonly object _lock = new();
    private Dictionary<string, TerrainNode> _subGraphNodes = null;
    private LoopInputNode _loopInput = null;
    private LoopOutputNode _loopOutput = null;

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopNode"/> class.
    /// </summary>
    public LoopNode()
    {
        Inputs.Add(new Port("input", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("output", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Configures input and output ports dynamically.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        Outputs.Clear();
        PortType type = AssociatedResource != null ? AssociatedResource.PortType : PortType.Height;
        Inputs.Add(new Port("input", type, PortDirection.Input));
        Outputs.Add(new Port("output", type, PortDirection.Output));
        InitializePorts();
    }

    private void InitializeSubGraph()
    {
        lock (_lock)
        {
            if (_subGraphNodes != null) return;
            var subGraph = AssociatedResource?.SubGraph;
            if (subGraph == null) return;

            try
            {
                _subGraphNodes = GraphEvaluator.InstantiateGraphNodes(subGraph);
                foreach (var node in _subGraphNodes.Values)
                {
                    if (node is LoopInputNode inNode)
                        _loopInput = inNode;
                    else if (node is LoopOutputNode outNode)
                        _loopOutput = outNode;
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[LoopNode] Error instantiating sub-graph: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Evaluates the node by running the sub-graph loop.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        InitializeSubGraph();

        object currentVal = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            currentVal = link.SourceNode.PullData(ctx, link.SourcePortIndex);
        }

        if (_loopInput == null || _loopOutput == null || _subGraphNodes == null)
        {
            return currentVal;
        }

        int iterations = AssociatedResource != null ? AssociatedResource.Iterations : 3;
        iterations = Math.Max(0, iterations);

        for (int i = 0; i < iterations; i++)
        {
            ctx.CancellationToken.ThrowIfCancellationRequested();
            _loopInput.CurrentValue = currentVal;
            
            currentVal = _loopOutput.PullData(ctx, 0);

            // Clear sub-graph cache for the next iteration
            foreach (var node in _subGraphNodes.Values)
            {
                node.ClearCache();
            }
        }

        return currentVal;
    }

    /// <summary>
    /// Clears the cache of the parent node and the child sub-graph nodes.
    /// </summary>
    public override void ClearCache()
    {
        base.ClearCache();
        lock (_lock)
        {
            if (_subGraphNodes != null)
            {
                foreach (var node in _subGraphNodes.Values)
                {
                    node.ClearCache();
                }
            }
        }
    }
}

/// <summary>
/// Runtime node that acts as the starting variable injector for graph loops.
/// </summary>
public partial class LoopInputNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public LoopInputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Gets or sets the current iteration value injected by the loop supervisor.
    /// </summary>
    public object CurrentValue { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopInputNode"/> class.
    /// </summary>
    public LoopInputNode()
    {
        Outputs.Add(new Port("output", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Configures ports dynamically.
    /// </summary>
    public void OnResourceSet()
    {
        Outputs.Clear();
        PortType type = AssociatedResource != null ? AssociatedResource.PortType : PortType.Height;
        Outputs.Add(new Port("output", type, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates by returning the current loop state value.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        return CurrentValue;
    }
}

/// <summary>
/// Runtime node that acts as the terminal loop variable collector inside graph loops.
/// </summary>
public partial class LoopOutputNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public LoopOutputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopOutputNode"/> class.
    /// </summary>
    public LoopOutputNode()
    {
        Inputs.Add(new Port("input", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("output", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Configures ports dynamically.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        Outputs.Clear();
        PortType type = AssociatedResource != null ? AssociatedResource.PortType : PortType.Height;
        Inputs.Add(new Port("input", type, PortDirection.Input));
        Outputs.Add(new Port("output", type, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates by pulling the upstream loop terminal result.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            return link.SourceNode.PullData(ctx, link.SourcePortIndex);
        }
        return null;
    }
}

#endregion
