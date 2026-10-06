using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Perlin noise node.
/// </summary>
[GlobalClass]
[Tool]
public partial class PerlinNoiseNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the random seed for the LCG hash chain.
    /// </summary>
    [Export]
    public int Seed { get; set; } = 1337;

    /// <summary>
    /// Gets or sets the spatial frequency of the base octave.
    /// </summary>
    [Export]
    public float Frequency { get; set; } = 0.01f;

    /// <summary>
    /// Gets or sets the directional stretch factor along the X axis.
    /// </summary>
    [Export]
    public float ScaleX { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the directional stretch factor along the Z axis.
    /// </summary>
    [Export]
    public float ScaleZ { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the mapped output height minimum.
    /// </summary>
    [Export]
    public float OutputMin { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the mapped output height maximum.
    /// </summary>
    [Export]
    public float OutputMax { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="PerlinNoiseNodeResource"/> class.
    /// </summary>
    public PerlinNoiseNodeResource()
    {
        NodeType = nameof(PerlinNoiseNode);
    }
}
