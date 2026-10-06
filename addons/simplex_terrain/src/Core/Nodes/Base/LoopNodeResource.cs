using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a LoopNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class LoopNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the sub-graph to execute iteratively.
    /// </summary>
    [Export]
    public TerrainGraphResource SubGraph { get; set; }

    /// <summary>
    /// Gets or sets the number of loop iterations.
    /// </summary>
    [Export]
    public int Iterations { get; set; } = 3;

    /// <summary>
    /// Gets or sets the data type carried and processed by the loop.
    /// </summary>
    [Export]
    public PortType PortType { get; set; } = PortType.Height;

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopNodeResource"/> class.
    /// </summary>
    public LoopNodeResource()
    {
        NodeType = nameof(LoopNode);
    }
}
