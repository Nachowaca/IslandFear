using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Hydraulic and Soil Erosion modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class ErosionNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the soil friction or resistance factor [0, 1). Higher values resist erosion.
    /// </summary>
    [Export]
    public float Durability { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the global erosion strength multiplier.
    /// </summary>
    [Export]
    public float ErosionStrength { get; set; } = 0.3f;

    /// <summary>
    /// Gets or sets the sediment carrying density (ratio of eroded soil that becomes mudflow).
    /// </summary>
    [Export]
    public float SedimentDensity { get; set; } = 0.1f;

    /// <summary>
    /// Gets or sets the iteration count for sediment spreading sweeps (fluidity/viscosity control).
    /// </summary>
    [Export]
    public int Fluidity { get; set; } = 5;

    /// <summary>
    /// Gets or sets the outer iteration count (number of generation passes).
    /// </summary>
    [Export]
    public int Iterations { get; set; } = 10;

    /// <summary>
    /// Initializes a new instance of the <see cref="ErosionNodeResource"/> class.
    /// </summary>
    public ErosionNodeResource()
    {
        NodeType = nameof(ErosionNode);
    }
}
