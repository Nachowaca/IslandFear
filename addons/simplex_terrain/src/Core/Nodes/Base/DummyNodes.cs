namespace SimpleXTerrain;

using Godot;
using System;

#region Resources



#endregion

#region Nodes

/// <summary>
/// Runtime node that outputs a fixed scalar float value.
/// </summary>
public partial class DummyConstantNode : TerrainNode
{
    /// <summary>
    /// The associated resource holding parameters.
    /// </summary>
    public DummyConstantNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="DummyConstantNode"/> class.
    /// </summary>
    public DummyConstantNode()
    {
        Outputs.Add(new Port("Value", PortType.Scalar, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the constant node, returning the value configured in the parameter resource.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        // Keep track of how many times Evaluate is called for test assertions
        EvaluateCallCount++;

        float val = AssociatedResource != null ? AssociatedResource.Value : 1.0f;
        return val;
    }

    /// <summary>
    /// Counter tracking the number of times this node has run its evaluation math (for caching assertions).
    /// </summary>
    public int EvaluateCallCount { get; private set; }

    /// <summary>
    /// Resets the evaluation call counter.
    /// </summary>
    public void ResetCallCount()
    {
        EvaluateCallCount = 0;
    }
}

/// <summary>
/// Runtime node that takes an input and passes it directly through to its output.
/// </summary>
public partial class DummyPassthroughNode : TerrainNode
{
    /// <summary>
    /// The associated resource holding parameters.
    /// </summary>
    public DummyPassthroughNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="DummyPassthroughNode"/> class.
    /// </summary>
    public DummyPassthroughNode()
    {
        Inputs.Add(new Port("Input", PortType.Scalar, PortDirection.Input));
        Outputs.Add(new Port("Output", PortType.Scalar, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the passthrough node by pulling data from its upstream source node.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        EvaluateCallCount++;

        var link = InputLinks[0];
        if (link.SourceNode != null)
        {
            // Pull data from upstream
            return link.SourceNode.PullData(ctx, link.SourcePortIndex);
        }

        return 0.0f; // Default fallback
    }

    /// <summary>
    /// Counter tracking the number of times this node has run its evaluation math.
    /// </summary>
    public int EvaluateCallCount { get; private set; }

    /// <summary>
    /// Resets the evaluation call counter.
    /// </summary>
    public void ResetCallCount()
    {
        EvaluateCallCount = 0;
    }
}

#endregion
