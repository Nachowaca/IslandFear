using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SpotNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SpotNodeResource : TerrainNodeResource
{
    [Export]
    public float Radius { get; set; } = 256.0f;

    [Export]
    public float Hardness { get; set; } = 0.5f;

    [Export]
    public float Height { get; set; } = 1.0f;

    [Export]
    public float CenterX { get; set; } = 0.5f;

    [Export]
    public float CenterZ { get; set; } = 0.5f;

    public SpotNodeResource()
    {
        NodeType = nameof(SpotNode);
    }
}
