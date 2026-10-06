using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Terrain3D height output node.
/// </summary>
[GlobalClass]
[Tool]
public partial class HeightOutputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the path to the Terrain3D node in the scene tree.
    /// </summary>
    [Export]
    public NodePath TerrainNodePath { get; set; } = new NodePath("");

    /// <summary>
    /// Gets or sets the world-space height scale factor.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="HeightOutputNodeResource"/> class.
    /// </summary>
    public HeightOutputNodeResource()
    {
        NodeType = nameof(HeightOutputNode);
    }
}
