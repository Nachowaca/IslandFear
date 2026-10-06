using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a PrimitiveFormNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class PrimitiveFormNodeResource : TerrainNodeResource
{
    [Export]
    public FormType FormType { get; set; } = FormType.Cone;

    [Export]
    public TilingMode TilingMode { get; set; } = TilingMode.Clamp;

    [Export]
    public float HeightMin { get; set; } = 0.0f;

    [Export]
    public float HeightMax { get; set; } = 1.0f;

    [Export]
    public float TileCount { get; set; } = 1.0f;

    public PrimitiveFormNodeResource()
    {
        NodeType = nameof(PrimitiveFormNode);
    }
}
