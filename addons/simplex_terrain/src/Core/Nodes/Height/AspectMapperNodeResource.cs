using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for an AspectMapperNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class AspectMapperNodeResource : TerrainNodeResource
{
    [Export]
    public float LightDirX { get; set; } = 0.5f;

    [Export]
    public float LightDirY { get; set; } = 1.0f;

    [Export]
    public float LightDirZ { get; set; } = 0.5f;

    [Export]
    public float Wrap { get; set; } = 0.5f;

    [Export]
    public float Intensity { get; set; } = 1.0f;

    public AspectMapperNodeResource()
    {
        NodeType = nameof(AspectMapperNode);
    }
}
