using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Terrace height modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class TerraceNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the number of flat steps/stairs to generate.
    /// </summary>
    [Export]
    public int Steps { get; set; } = 8;

    /// <summary>
    /// Gets or sets the step steepness contrast intensity [0, 1].
    /// </summary>
    [Export]
    public float Steepness { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the step spacing uniformity factor [0, 1]. 1.0 is perfectly uniform, 0.0 is fully jittered.
    /// </summary>
    [Export]
    public float Uniformity { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the seed used for deterministic step jittering.
    /// </summary>
    [Export]
    public int JitterSeed { get; set; } = 42;

    /// <summary>
    /// Initializes a new instance of the <see cref="TerraceNodeResource"/> class.
    /// </summary>
    public TerraceNodeResource()
    {
        NodeType = nameof(TerraceNode);
    }
}
