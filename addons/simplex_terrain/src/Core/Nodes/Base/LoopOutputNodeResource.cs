using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a LoopOutputNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class LoopOutputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the data type of the loop variable returned.
    /// </summary>
    [Export]
    public PortType PortType { get; set; } = PortType.Height;

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopOutputNodeResource"/> class.
    /// </summary>
    public LoopOutputNodeResource()
    {
        NodeType = nameof(LoopOutputNode);
    }
}
