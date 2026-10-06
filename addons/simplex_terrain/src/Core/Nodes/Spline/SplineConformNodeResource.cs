using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineConformNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineConformNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the distance from spline centerline over which terrain blends.
    /// </summary>
    [Export]
    public float BlendWidth { get; set; } = 30.0f;

    /// <summary>
    /// Gets or sets the cross-sectional profile curve.
    /// </summary>
    [Export]
    public Curve BlendProfile { get; set; }

    /// <summary>
    /// Gets or sets the vertical offset applied to the spline height before conforming.
    /// </summary>
    [Export]
    public float HeightOffset { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets whether high-frequency terrain details are preserved.
    /// </summary>
    [Export]
    public bool PreserveDetail { get; set; } = true;

    /// <summary>
    /// Gets or sets the global vertical terrain height scale multiplier in meters.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineConformNodeResource"/> class.
    /// </summary>
    public SplineConformNodeResource()
    {
        NodeType = nameof(SplineConformNode);
    }
}
