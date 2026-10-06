using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Levels contrast and gamma modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class LevelsNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the input range minimum limit.
    /// </summary>
    [Export]
    public float InputMin { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the input range maximum limit.
    /// </summary>
    [Export]
    public float InputMax { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the target output range minimum bound.
    /// </summary>
    [Export]
    public float OutputMin { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the target output range maximum bound.
    /// </summary>
    [Export]
    public float OutputMax { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the symmetrical gamma contrast correction curve power factor.
    /// </summary>
    [Export]
    public float Gamma { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets whether height values are clamped to the Input limits.
    /// </summary>
    [Export]
    public bool EnableClamping { get; set; } = true;

    /// <summary>
    /// Initializes a new instance of the <see cref="LevelsNodeResource"/> class.
    /// </summary>
    public LevelsNodeResource()
    {
        NodeType = nameof(LevelsNode);
    }
}
