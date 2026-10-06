using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Curve height modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class CurveNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the custom Godot Curve used to deform input height values.
    /// </summary>
    [Export]
    public Curve CurveToApply { get; set; }

    /// <summary>
    /// If true, uses early extrapolation to bypass flat shoulders near boundaries.
    /// If false, uses normal interpolation inside [0, 1] and only extrapolates outside.
    /// </summary>
    [Export]
    public bool BypassShoulders { get; set; } = true;

    /// <summary>
    /// Initializes a new instance of the <see cref="CurveNodeResource"/> class.
    /// </summary>
    public CurveNodeResource()
    {
        NodeType = nameof(CurveNode);
    }
}
