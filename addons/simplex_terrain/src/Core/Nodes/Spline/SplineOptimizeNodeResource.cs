using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineOptimizeNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineOptimizeNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the maximum allowed spatial deviation in world units.
    /// </summary>
    [Export]
    public float DeviationThreshold { get; set; } = 0.5f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineOptimizeNodeResource"/> class.
    /// </summary>
    public SplineOptimizeNodeResource()
    {
        NodeType = nameof(SplineOptimizeNode);
    }
}
