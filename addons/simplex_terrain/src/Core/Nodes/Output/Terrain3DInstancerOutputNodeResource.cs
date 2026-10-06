using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a Terrain3DInstancerOutputNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class Terrain3DInstancerOutputNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the path to the Terrain3D node in the scene tree.
    /// </summary>
    [Export]
    public NodePath TerrainNodePath { get; set; } = new NodePath("");

    /// <summary>
    /// Gets or sets which Terrain3DMeshAsset index to use for these instances.
    /// </summary>
    [Export]
    public int MeshAssetId { get; set; } = 0;

    /// <summary>
    /// Gets or sets whether to clear existing instances of the mesh asset before adding new ones.
    /// </summary>
    [Export]
    public bool ClearExisting { get; set; } = true;

    /// <summary>
    /// Initializes a new instance of the <see cref="Terrain3DInstancerOutputNodeResource"/> class.
    /// </summary>
    public Terrain3DInstancerOutputNodeResource()
    {
        NodeType = nameof(Terrain3DInstancerOutputNode);
    }
}
