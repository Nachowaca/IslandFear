using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Splat partition-of-unity normalization node.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplatNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the number of weight layers to normalize.
    /// </summary>
    [Export]
    public int LayerCount { get; set; } = 2;

    /// <summary>
    /// Gets or sets the list of Terrain3DTextureAsset indices mapping to each layer.
    /// </summary>
    [Export]
    public Godot.Collections.Array<int> TextureIds { get; set; } = new Godot.Collections.Array<int> { 0, 1 };

    /// <summary>
    /// Gets or sets the list of Terrain3DTextureAsset names mapping to each layer.
    /// </summary>
    [Export]
    public Godot.Collections.Array<string> TextureNames { get; set; } = new Godot.Collections.Array<string>();

    /// <summary>
    /// Initializes a new instance of the <see cref="SplatNodeResource"/> class.
    /// </summary>
    public SplatNodeResource()
    {
        NodeType = nameof(SplatNode);
    }
}
