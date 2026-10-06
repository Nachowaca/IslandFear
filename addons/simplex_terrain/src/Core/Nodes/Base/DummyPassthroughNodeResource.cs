using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource for a dummy passthrough node that passes through its input data.
/// </summary>
[GlobalClass]
[Tool]
public partial class DummyPassthroughNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Initializes a new instance of the <see cref="DummyPassthroughNodeResource"/> class.
    /// </summary>
    public DummyPassthroughNodeResource()
    {
        NodeType = nameof(DummyPassthroughNode);
    }
}
