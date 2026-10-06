using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for an IslandMaskNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class IslandMaskNodeResource : TerrainNodeResource
{
    [Export]
    public IslandMode IslandMode { get; set; } = IslandMode.Circular;

    [Export]
    public float CenterX { get; set; } = 0.5f;

    [Export]
    public float CenterZ { get; set; } = 0.5f;

    [Export]
    public float Radius { get; set; } = 256.0f;

    [Export]
    public float Falloff { get; set; } = 128.0f;

    [Export]
    public Curve FalloffCurve { get; set; }

    public IslandMaskNodeResource()
    {
        NodeType = nameof(IslandMaskNode);
    }
}
