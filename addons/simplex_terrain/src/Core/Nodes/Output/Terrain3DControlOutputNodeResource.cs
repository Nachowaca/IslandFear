using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Terrain3D control map output node.
/// </summary>
[GlobalClass]
[Tool]
public partial class Terrain3DControlOutputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the path to the Terrain3D node in the scene tree.
    /// </summary>
    [Export]
    public NodePath TerrainNodePath { get; set; } = new NodePath("");

    /// <summary>
    /// Initializes a new instance of the <see cref="Terrain3DControlOutputNodeResource"/> class.
    /// </summary>
    public Terrain3DControlOutputNodeResource()
    {
        NodeType = nameof(Terrain3DControlOutputNode);
    }
}
