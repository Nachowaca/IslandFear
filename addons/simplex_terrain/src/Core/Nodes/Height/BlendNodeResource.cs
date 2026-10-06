using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a multi-heightmap BlendNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class BlendNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the mathematical operation used to combine the two heightfields.
    /// </summary>
    [Export]
    public BlendMode BlendMode { get; set; } = BlendMode.Lerp;

    /// <summary>
    /// Gets or sets the global multiplier applied to the blending weight mask.
    /// </summary>
    [Export]
    public float Strength { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="BlendNodeResource"/> class.
    /// </summary>
    public BlendNodeResource()
    {
        NodeType = nameof(BlendNode);
    }
}
