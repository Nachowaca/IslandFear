using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Serializable resource representing a single named global variable inside a terrain graph.
/// </summary>
[GlobalClass]
[Tool]
public partial class SharedVariableEntry : Resource
{
    /// <summary>
    /// Gets or sets the variable name used for node bindings.
    /// </summary>
    [Export]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the float value associated with the variable.
    /// </summary>
    [Export]
    public float Value { get; set; } = 0.0f;

    /// <summary>
    /// Initializes a new instance of the <see cref="SharedVariableEntry"/> class.
    /// </summary>
    public SharedVariableEntry()
    {
    }
}

/// <summary>
/// Serializable resource serving as the master database of shared global parameters
/// that can be referenced by node properties in the graph.
/// </summary>
[GlobalClass]
[Tool]
public partial class SharedVariablesResource : Resource
{
    /// <summary>
    /// Gets or sets the list of shared variables.
    /// </summary>
    [Export]
    public Godot.Collections.Array<SharedVariableEntry> Variables { get; set; } = new();

    /// <summary>
    /// Initializes a new instance of the <see cref="SharedVariablesResource"/> class.
    /// </summary>
    public SharedVariablesResource()
    {
    }
}
