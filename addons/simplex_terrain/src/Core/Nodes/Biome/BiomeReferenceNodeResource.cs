using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a BiomeReferenceNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class BiomeReferenceNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the nested sub-graph defining this biome.
    /// </summary>
    [Export]
    public TerrainGraphResource SubGraph { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="BiomeReferenceNodeResource"/> class.
    /// </summary>
    public BiomeReferenceNodeResource()
    {
        NodeType = nameof(BiomeReferenceNode);
    }
}
