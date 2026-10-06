using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a ProximityDecimationNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ProximityDecimationNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the minimum allowed distance between any two surviving objects.
    /// </summary>
    [Export]
    public float ExclusionRadius { get; set; } = 5.0f;

    /// <summary>
    /// Gets or sets the scale-influence weight factor (0 = scale ignored, 1 = scale fully scales exclusion radius).
    /// </summary>
    [Export]
    public float SizeFactor { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the decimation sorting priority strategy.
    /// </summary>
    [Export]
    public DecimationPriority Priority { get; set; } = DecimationPriority.Random;

    /// <summary>
    /// Initializes a new instance of the <see cref="ProximityDecimationNodeResource"/> class.
    /// </summary>
    public ProximityDecimationNodeResource()
    {
        NodeType = nameof(ProximityDecimationNode);
    }
}
