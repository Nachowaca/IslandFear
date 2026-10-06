using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineSubdivideNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineSubdivideNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the maximum allowed segment length in world units.
    /// </summary>
    [Export]
    public float MaxSegmentLength { get; set; } = 50.0f;

    /// <summary>
    /// Gets or sets the maximum recursive subdivision depth.
    /// </summary>
    [Export]
    public int Iterations { get; set; } = 1;

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineSubdivideNodeResource"/> class.
    /// </summary>
    public SplineSubdivideNodeResource()
    {
        NodeType = nameof(SplineSubdivideNode);
    }
}
