namespace SimpleXTerrain;

using Godot;

/// <summary>
/// Serializable Godot Resource serving as the master container for a procedural terrain node graph.
/// Contains all serialized nodes and connection paths, enabling saving/loading as a `.tres` file.
/// </summary>
[GlobalClass]
[Tool]
public partial class TerrainGraphResource : Resource
{
    /// <summary>
    /// Gets or sets the collection of serialized nodes in this graph.
    /// </summary>
    [Export]
    public Godot.Collections.Array<TerrainNodeResource> Nodes { get; set; } = new();

    /// <summary>
    /// Gets or sets the collection of connection links between nodes in this graph.
    /// </summary>
    [Export]
    public Godot.Collections.Array<ConnectionData> Connections { get; set; } = new();

    /// <summary>
    /// Gets or sets the shared variables defined in this graph.
    /// </summary>
    [Export]
    public SharedVariablesResource SharedVariables { get; set; }

    /// <summary>
    /// Gets or sets the collection of visual frames in this graph.
    /// </summary>
    [Export]
    public Godot.Collections.Array<GraphFrameData> Frames { get; set; } = new Godot.Collections.Array<GraphFrameData>();

    /// <summary>
    /// Gets or sets the collection of comments in this graph.
    /// </summary>
    [Export]
    public Godot.Collections.Array<GraphCommentData> Comments { get; set; } = new Godot.Collections.Array<GraphCommentData>();

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainGraphResource"/> class.
    /// </summary>
    public TerrainGraphResource()
    {
    }
}
