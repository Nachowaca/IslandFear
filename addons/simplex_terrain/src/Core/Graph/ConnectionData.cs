namespace SimpleXTerrain;

using Godot;

/// <summary>
/// Serializable Godot Resource defining a connection link between two node ports in the graph.
/// </summary>
[GlobalClass]
[Tool]
public partial class ConnectionData : Resource
{
    /// <summary>
    /// Gets or sets the unique ID of the upstream source node.
    /// </summary>
    [Export]
    public string FromNodeId { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the index of the output port on the upstream source node.
    /// </summary>
    [Export]
    public int FromPort { get; set; } = 0;

    /// <summary>
    /// Gets or sets the unique ID of the downstream destination node.
    /// </summary>
    [Export]
    public string ToNodeId { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the index of the input port on the downstream destination node.
    /// </summary>
    [Export]
    public int ToPort { get; set; } = 0;

    /// <summary>
    /// Initializes a new instance of the <see cref="ConnectionData"/> class.
    /// </summary>
    public ConnectionData()
    {
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="ConnectionData"/> class with values.
    /// </summary>
    public ConnectionData(string fromNodeId, int fromPort, string toNodeId, int toPort)
    {
        FromNodeId = fromNodeId;
        FromPort = fromPort;
        ToNodeId = toNodeId;
        ToPort = toPort;
    }
}
