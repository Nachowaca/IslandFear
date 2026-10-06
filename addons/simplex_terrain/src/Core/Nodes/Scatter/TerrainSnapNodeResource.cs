using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a TerrainSnapNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class TerrainSnapNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets how much to rotate the object up-vector to match the terrain normal (0 = stay upright, 1 = full align).
    /// </summary>
    [Export]
    public float NormalAlign { get; set; } = 1.0f;

    /// <summary>
    /// Gets or sets the vertical offset applied after snapping (for partially buried or hovering objects).
    /// </summary>
    [Export]
    public float HeightOffset { get; set; } = 0.0f;

    /// <summary>
    /// Gets or sets the global vertical terrain height scale multiplier in meters.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainSnapNodeResource"/> class.
    /// </summary>
    public TerrainSnapNodeResource()
    {
        NodeType = nameof(TerrainSnapNode);
    }
}
