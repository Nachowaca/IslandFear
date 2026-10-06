using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a LoopInputNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class LoopInputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the data type of the loop variable.
    /// </summary>
    [Export]
    public PortType PortType { get; set; } = PortType.Height;

    /// <summary>
    /// Initializes a new instance of the <see cref="LoopInputNodeResource"/> class.
    /// </summary>
    public LoopInputNodeResource()
    {
        NodeType = nameof(LoopInputNode);
    }
}
