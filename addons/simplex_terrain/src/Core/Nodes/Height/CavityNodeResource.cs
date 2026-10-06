using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Cavity Laplacian curvature selector node.
/// </summary>
[GlobalClass]
[Tool]
public partial class CavityNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the feature extraction mode: Concave, Convex, or Both.
    /// </summary>
    [Export]
    public CavityMode Mode { get; set; } = CavityMode.Concave;

    /// <summary>
    /// Gets or sets the multiplier applied to the Laplacian result before clamping to 0-1.
    /// </summary>
    [Export]
    public float Strength { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="CavityNodeResource"/> class.
    /// </summary>
    public CavityNodeResource()
    {
        NodeType = nameof(CavityNode);
    }
}
