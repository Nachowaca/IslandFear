using Godot;
using System;

namespace SimpleXTerrain;

#region Resources



#endregion

#region Nodes

/// <summary>
/// Runtime node that transmits data wirelessly across the graph by exposing its output to receiver nodes.
/// </summary>
public partial class PortalTransmitterNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public PortalTransmitterNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="PortalTransmitterNode"/> class.
    /// </summary>
    public PortalTransmitterNode()
    {
        Inputs.Add(new Port("input", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("output", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Re-initializes inputs and outputs when the resource configuration is set.
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
    /// Evaluates the node by forwarding the connected input.
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

/// <summary>
/// Runtime node that receives data wirelessly from a matching transmitter node.
/// </summary>
public partial class PortalReceiverNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public PortalReceiverNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="PortalReceiverNode"/> class.
    /// </summary>
    public PortalReceiverNode()
    {
        Inputs.Add(new Port("transmitter_in", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("output", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Re-initializes inputs and outputs when the resource configuration is set.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        Outputs.Clear();
        PortType type = AssociatedResource != null ? AssociatedResource.PortType : PortType.Height;
        Inputs.Add(new Port("transmitter_in", type, PortDirection.Input));
        Outputs.Add(new Port("output", type, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the node by pulling data from the wired wireless transmitter.
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
