using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a RadialDispersalNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class RadialDispersalNodeResource : TerrainNodeResource
{
    [Export]
    public int ChildrenPerParent { get; set; } = 5;

    [Export]
    public float MinRadius { get; set; } = 2.0f;

    [Export]
    public float MaxRadius { get; set; } = 15.0f;

    [Export]
    public int Seed { get; set; } = 3;

    public RadialDispersalNodeResource()
    {
        NodeType = nameof(RadialDispersalNode);
    }
}
