using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for an OceanLevelNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class OceanLevelNodeResource : TerrainNodeResource
{
    [Export]
    public float WaterLevel { get; set; } = 0.3f;

    [Export]
    public bool ClampHeights { get; set; } = true;

    [Export]
    public float ShorelineWidth { get; set; } = 0.05f;

    [Export]
    public float OceanDepthScale { get; set; } = 2.0f;

    public OceanLevelNodeResource()
    {
        NodeType = nameof(OceanLevelNode);
    }
}
