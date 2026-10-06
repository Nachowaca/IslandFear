using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource for a dummy constant node that outputs a fixed scalar value.
/// </summary>
[GlobalClass]
[Tool]
public partial class DummyConstantNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the constant scalar value.
    /// </summary>
    [Export]
    public float Value { get; set; } = 1.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="DummyConstantNodeResource"/> class.
    /// </summary>
    public DummyConstantNodeResource()
    {
        NodeType = nameof(DummyConstantNode);
    }
}
