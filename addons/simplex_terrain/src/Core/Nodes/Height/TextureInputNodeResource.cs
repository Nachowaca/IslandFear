using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a TextureInputNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class TextureInputNodeResource : TerrainNodeResource
{
    [Export]
    public Texture2D Texture { get; set; }

    [Export]
    public TextureChannel Channel { get; set; } = TextureChannel.Red;

    public TextureInputNodeResource()
    {
        NodeType = nameof(TextureInputNode);
    }
}
