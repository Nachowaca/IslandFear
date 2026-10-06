using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Voronoi cellular node.
/// </summary>
[GlobalClass]
[Tool]
public partial class VoronoiNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the random seed for the LCG hash chain.
    /// </summary>
    [Export]
    public int Seed { get; set; } = 42;

    /// <summary>
    /// Gets or sets the dimension of each cell in world space meters.
    /// </summary>
    [Export]
    public float CellSize { get; set; } = 128.0f;

    /// <summary>
    /// Gets or sets the random scatter jitter factor (0 = regular grid, 1 = full random).
    /// </summary>
    [Export]
    public float Jitter { get; set; } = 0.9f;

    /// <summary>
    /// Gets or sets the cellular distance blending equation type.
    /// </summary>
    [Export]
    public VoronoiBlendType BlendType { get; set; } = VoronoiBlendType.Cellular;

    /// <summary>
    /// Gets or sets the mapped output height minimum.
    /// </summary>
    [Export]
    public float OutputMin { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the mapped output height maximum.
    /// </summary>
    [Export]
    public float OutputMax { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the user intensity modifier factor.
    /// </summary>
    [Export]
    public float Intensity { get; set; } = 1.0f;

    /// <summary>
    /// Scaling stretch factor along the X axis.
    /// </summary>
    [Export]
    public float StretchX { get; set; } = 1.0f;

    /// <summary>
    /// Scaling stretch factor along the Z axis.
    /// </summary>
    [Export]
    public float StretchZ { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="VoronoiNodeResource"/> class.
    /// </summary>
    public VoronoiNodeResource()
    {
        NodeType = nameof(VoronoiNode);
    }
}
