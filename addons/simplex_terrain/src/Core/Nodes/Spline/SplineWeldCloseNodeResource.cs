using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineWeldCloseNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineWeldCloseNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the maximum distance between endpoints or segments to trigger welding.
    /// </summary>
    [Export]
    public float WeldRadius { get; set; } = 10.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineWeldCloseNodeResource"/> class.
    /// </summary>
    public SplineWeldCloseNodeResource()
    {
        NodeType = nameof(SplineWeldCloseNode);
    }
}
