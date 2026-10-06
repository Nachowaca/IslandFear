using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a GabrielGraphNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class GabrielGraphNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the maximum edge length for connections in world units.
    /// </summary>
    [Export]
    public float MaxEdgeLength { get; set; } = 500.0f;

    /// <summary>
    /// Gets or sets the maximum number of connections allowed per point.
    /// </summary>
    [Export]
    public int MaxLinks { get; set; } = 4;

    /// <summary>
    /// Initializes a new instance of the <see cref="GabrielGraphNodeResource"/> class.
    /// </summary>
    public GabrielGraphNodeResource()
    {
        NodeType = nameof(GabrielGraphNode);
    }
}
