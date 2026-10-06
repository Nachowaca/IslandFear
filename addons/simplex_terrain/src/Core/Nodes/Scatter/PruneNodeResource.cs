using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a PruneNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class PruneNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the random seed used for stochastic rejection sampling.
    /// </summary>
    [Export]
    public int Seed { get; set; } = 2;

    /// <summary>
    /// Initializes a new instance of the <see cref="PruneNodeResource"/> class.
    /// </summary>
    public PruneNodeResource()
    {
        NodeType = nameof(PruneNode);
    }
}
