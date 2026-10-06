using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a WhittakerLookupNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class WhittakerLookupNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the 2D Whittaker diagram lookup image.
    /// </summary>
    [Export]
    public Texture2D WhittakerDiagram { get; set; }

    /// <summary>
    /// Gets or sets the softness boundary width (0 = hard transitions, 1 = maximum blur).
    /// </summary>
    [Export]
    public float Softness { get; set; } = 0.2f;

    /// <summary>
    /// Gets or sets the number of unique biomes defined in the Whittaker diagram.
    /// </summary>
    [Export]
    public int BiomeCount { get; set; } = 2;

    /// <summary>
    /// Gets or sets the contrast sharpness threshold (0 = normal soft blending, 1 = maximum sharpness).
    /// </summary>
    [Export]
    public float Sharpness { get; set; } = 0.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="WhittakerLookupNodeResource"/> class.
    /// </summary>
    public WhittakerLookupNodeResource()
    {
        NodeType = nameof(WhittakerLookupNode);
    }
}
