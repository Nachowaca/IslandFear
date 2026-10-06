using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Beach and Shoreline generation node.
/// </summary>
[GlobalClass]
[Tool]
public partial class BeachNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the height threshold that defines the waterline.
    /// </summary>
    [Export]
    public float SeaLevel { get; set; } = 0.3f;

    /// <summary>
    /// Gets or sets the height range above sea level that receives beach profiling.
    /// </summary>
    [Export]
    public float BeachWidth { get; set; } = 0.05f;

    /// <summary>
    /// Gets or sets how steeply the beach rises from the waterline (as a fraction of default slope, typically 0 to 1).
    /// </summary>
    [Export]
    public float BeachSlope { get; set; } = 0.3f;

    /// <summary>
    /// Gets or sets the height range below sea level that receives sandy deposition.
    /// </summary>
    [Export]
    public float UnderwaterSandDepth { get; set; } = 0.05f;

    /// <summary>
    /// Gets or sets the shoreline relaxation inland rate factor.
    /// </summary>
    [Export]
    public float ShoreRelax { get; set; } = 5.0f;

    /// <summary>
    /// Gets or sets the outward beach size in pixels.
    /// </summary>
    [Export]
    public float BeachSize { get; set; } = 10.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="BeachNodeResource"/> class.
    /// </summary>
    public BeachNodeResource()
    {
        NodeType = nameof(BeachNode);
    }
}
