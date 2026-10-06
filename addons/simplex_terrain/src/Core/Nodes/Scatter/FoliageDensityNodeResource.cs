using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a FoliageDensityNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class FoliageDensityNodeResource : TerrainNodeResource
{
    [Export]
    public float DensityFactor { get; set; } = 10.0f;

    [Export]
    public int DownscaleFactor { get; set; } = 4;

    [Export]
    public int Seed { get; set; } = 1337;

    [Export]
    public int MeshAssetId { get; set; } = 1;

    [Export]
    public float MinScale { get; set; } = 0.8f;

    [Export]
    public float MaxScale { get; set; } = 1.2f;

    [Export]
    public float MinHeightOffset { get; set; } = 0.0f;

    [Export]
    public float MaxHeightOffset { get; set; } = 0.0f;

    public FoliageDensityNodeResource()
    {
        NodeType = nameof(FoliageDensityNode);
    }
}
