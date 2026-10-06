using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for an ExcavationNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ExcavationNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the radius of the flattened area in world units.
    /// </summary>
    [Export]
    public float Radius { get; set; } = 3.0f;

    /// <summary>
    /// Gets or sets the width of the Hermite blend transition at the flat zone edge.
    /// </summary>
    [Export]
    public float BlendEdge { get; set; } = 1.5f;

    /// <summary>
    /// Gets or sets the deformation mode.
    /// </summary>
    [Export]
    public ExcavationMode Mode { get; set; } = ExcavationMode.Flatten;

    /// <summary>
    /// Gets or sets the global vertical terrain height scale multiplier in meters.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="ExcavationNodeResource"/> class.
    /// </summary>
    public ExcavationNodeResource()
    {
        NodeType = nameof(ExcavationNode);
    }
}
