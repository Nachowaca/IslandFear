using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a BiomeBlendNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class BiomeBlendNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the number of biomes to blend.
    /// </summary>
    [Export]
    public int BiomeCount { get; set; } = 2;

    /// <summary>
    /// Initializes a new instance of the <see cref="BiomeBlendNodeResource"/> class.
    /// </summary>
    public BiomeBlendNodeResource()
    {
        NodeType = nameof(BiomeBlendNode);
    }
}
