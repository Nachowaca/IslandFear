using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a RiverGeneratorNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class RiverGeneratorNodeResource : TerrainNodeResource
{
    [Export]
    public float RiverWidth { get; set; } = 20.0f;

    [Export]
    public float RiverDepth { get; set; } = 4.0f;

    [Export]
    public float BankWidth { get; set; } = 10.0f;

    [Export]
    public float HeightScale { get; set; } = 500.0f;

    public RiverGeneratorNodeResource()
    {
        NodeType = nameof(RiverGeneratorNode);
    }
}
