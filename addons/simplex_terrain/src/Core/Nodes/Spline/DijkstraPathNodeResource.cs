using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a DijkstraPathNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class DijkstraPathNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the normalized start X coordinate (0.0 to 1.0).
    /// </summary>
    [Export]
    public float StartX { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the normalized start Z coordinate (0.0 to 1.0).
    /// </summary>
    [Export]
    public float StartZ { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the normalized end X coordinate (0.0 to 1.0).
    /// </summary>
    [Export]
    public float EndX { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the normalized end Z coordinate (0.0 to 1.0).
    /// </summary>
    [Export]
    public float EndZ { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the penalty multiplier per degree of slope incline.
    /// </summary>
    [Export]
    public float SlopeCost { get; set; } = 2.0f;

    /// <summary>
    /// Gets or sets the penalty for direction changes.
    /// </summary>
    [Export]
    public float TurnCost { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the global vertical terrain height scale multiplier in meters.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="DijkstraPathNodeResource"/> class.
    /// </summary>
    public DijkstraPathNodeResource()
    {
        NodeType = nameof(DijkstraPathNode);
    }
}
