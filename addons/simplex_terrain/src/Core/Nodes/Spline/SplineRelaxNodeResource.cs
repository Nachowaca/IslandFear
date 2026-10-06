using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineRelaxNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineRelaxNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the number of midpoint relaxation passes.
    /// </summary>
    [Export]
    public int Iterations { get; set; } = 3;

    /// <summary>
    /// Gets or sets the blend strength towards the midpoint per iteration (0 = no change, 1 = full midpoint blend factor of 0.5).
    /// </summary>
    [Export]
    public float Strength { get; set; } = 0.5f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineRelaxNodeResource"/> class.
    /// </summary>
    public SplineRelaxNodeResource()
    {
        NodeType = nameof(SplineRelaxNode);
    }
}
