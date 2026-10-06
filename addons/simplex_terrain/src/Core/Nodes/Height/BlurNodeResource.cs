using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Blur height modifier node.
/// </summary>
[GlobalClass]
[Tool]
public partial class BlurNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the binomial blur sweep parameter beta in range (0, 1].
    /// </summary>
    [Export]
    public float Beta { get; set; } = 0.5f;

    /// <summary>
    /// Gets or sets the number of sequential blur passes.
    /// </summary>
    [Export]
    public int Iterations { get; set; } = 1;

    /// <summary>
    /// Initializes a new instance of the <see cref="BlurNodeResource"/> class.
    /// </summary>
    public BlurNodeResource()
    {
        NodeType = nameof(BlurNode);
    }
}
