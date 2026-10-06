using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Fractal octave stacking node.
/// </summary>
[GlobalClass]
[Tool]
public partial class FractalNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the number of fractal summation layers (octaves).
    /// </summary>
    [Export]
    public int Octaves { get; set; } = 8;

    /// <summary>
    /// Gets or sets the amplitude reduction factor per octave (geometric ratio).
    /// </summary>
    [Export]
    public float Persistence { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the frequency multiplier per octave.
    /// </summary>
    [Export]
    public float Lacunarity { get; set; } = 2.0f;

    /// <summary>
    /// Gets or sets the base spatial frequency of the fractal noise.
    /// </summary>
    [Export]
    public float Frequency { get; set; } = 0.005f;

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
    /// Initializes a new instance of the <see cref="FractalNodeResource"/> class.
    /// </summary>
    public FractalNodeResource()
    {
        NodeType = nameof(FractalNode);
    }
}
