using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Slope selector modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class SlopeNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the minimum slope inclination threshold angle in degrees [0, 90].
    /// </summary>
    [Export]
    public float MinAngle { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the maximum slope inclination threshold angle in degrees [0, 90].
    /// </summary>
    [Export]
    public float MaxAngle { get; set; } = 90.0f;

    /// <summary>
    /// Gets or sets the smoothing transition angle span in degrees.
    /// </summary>
    [Export]
    public float SmoothAngle { get; set; } = 5.0f;

    /// <summary>
    /// Gets or sets the physical horizontal cell spacing distance in meters.
    /// </summary>
    [Export]
    public float PixelSize { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the global vertical terrain height scale multiplier in meters.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SlopeNodeResource"/> class.
    /// </summary>
    public SlopeNodeResource()
    {
        NodeType = nameof(SlopeNode);
    }
}
