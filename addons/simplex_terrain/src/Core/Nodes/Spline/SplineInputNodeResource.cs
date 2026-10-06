using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineInputNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineInputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the path in the scene tree to the Path3D node to read from.
    /// </summary>
    [Export]
    public NodePath PathNode { get; set; } = new NodePath("");

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineInputNodeResource"/> class.
    /// </summary>
    public SplineInputNodeResource()
    {
        NodeType = nameof(SplineInputNode);
    }
}
