using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineStrokeNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineStrokeNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the full stroke width in world units.
    /// </summary>
    [Export]
    public float Width { get; set; } = 20.0f;

    /// <summary>
    /// Gets or sets the hardness factor (0 = soft, 1 = hard) controlling the power-curve falloff.
    /// </summary>
    [Export]
    public float Hardness { get; set; } = 0.8f;

    /// <summary>
    /// Gets or sets the custom falloff curve.
    /// </summary>
    [Export]
    public Curve FalloffCurve { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineStrokeNodeResource"/> class.
    /// </summary>
    public SplineStrokeNodeResource()
    {
        NodeType = nameof(SplineStrokeNode);
    }
}
