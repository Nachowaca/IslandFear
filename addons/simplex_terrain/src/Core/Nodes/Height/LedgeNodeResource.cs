using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Ledge (Contour Cliff) generation node.
/// </summary>
[GlobalClass]
[Tool]
public partial class LedgeNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the height value at which the ledge plateau forms.
    /// </summary>
    [Export]
    public float ContourLevel { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the width of the smooth Hermite blend at the top edge of the cliff.
    /// </summary>
    [Export]
    public float TopShoulder { get; set; } = 0.15f;

    /// <summary>
    /// Gets or sets the width of the smooth Hermite blend at the base of the cliff.
    /// </summary>
    [Export]
    public float BottomShoulder { get; set; } = 0.1f;

    /// <summary>
    /// Gets or sets the total vertical drop of the ledge.
    /// </summary>
    [Export]
    public float CliffHeight { get; set; } = 0.3f;

    /// <summary>
    /// Gets or sets the steepness of the cliff face transition.
    /// </summary>
    [Export]
    public float Steepness { get; set; } = 20.0f;

    /// <summary>
    /// Gets or sets the number of binomial smoothing iterations for the contour guide.
    /// </summary>
    [Export]
    public int BlurIterations { get; set; } = 2;

    /// <summary>
    /// Gets or sets the beta factor for binomial smoothing.
    /// </summary>
    [Export]
    public float BlurBeta { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the blur radius for contour guide H_mask.
    /// </summary>
    [Export]
    public float BlurRadius { get; set; } = 2.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="LedgeNodeResource"/> class.
    /// </summary>
    public LedgeNodeResource()
    {
        NodeType = nameof(LedgeNode);
    }
}

