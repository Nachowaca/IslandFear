using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a ScatterNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ScatterNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the overall scatter density (objects per unit area).
    /// </summary>
    [Export]
    public float Density { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the random seed for deterministic placement.
    /// </summary>
    [Export]
    public int Seed { get; set; } = 1;

    /// <summary>
    /// Gets or sets the number of candidate positions tested per placed object.
    /// </summary>
    [Export]
    public int Candidates { get; set; } = 5;

    /// <summary>
    /// Gets or sets the minimum world-space distance between any two objects.
    /// </summary>
    [Export]
    public float MinSpacing { get; set; } = 2.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="ScatterNodeResource"/> class.
    /// </summary>
    public ScatterNodeResource()
    {
        NodeType = nameof(ScatterNode);
    }
}
