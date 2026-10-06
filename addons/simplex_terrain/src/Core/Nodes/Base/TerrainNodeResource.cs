namespace SimpleXTerrain;

using Godot;

/// <summary>
/// Serializable Godot Resource holding parameter state and editor metadata for a single node.
/// Subclasses of this resource define specific parameters for concrete node types.
/// </summary>
[GlobalClass]
[Tool]
public partial class TerrainNodeResource : Resource
{
    /// <summary>
    /// Gets or sets the unique identifier for this node instance in the graph (typically a GUID).
    /// </summary>
    [Export]
    public string NodeId { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the type name of the node (matches a registered node implementation).
    /// </summary>
    [Export]
    public string NodeType { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the position of this node in the visual graph editor workspace.
    /// </summary>
    [Export]
    public Vector2 EditorPosition { get; set; } = Vector2.Zero;

    /// <summary>
    /// Gets or sets the shared variables reference mapped to this node.
    /// </summary>
    [Export]
    public SharedVariablesResource SharedVariables { get; set; }

    /// <summary>
    /// Gets or sets whether to use GPU compute acceleration for this node (if supported).
    /// </summary>
    [Export]
    public bool UseGpu { get; set; } = false;

    /// <summary>
    /// Resolves the value of a shared variable by name, falling back to a default value if not found.
    /// </summary>
    /// <param name="varName">The name of the shared variable to look up.</param>
    /// <param name="defaultValue">The fallback value if the variable is not defined or is empty.</param>
    /// <returns>The resolved float value.</returns>
    public float GetSharedValue(string varName, float defaultValue)
    {
        if (SharedVariables == null || string.IsNullOrWhiteSpace(varName))
        {
            return defaultValue;
        }

        foreach (var entry in SharedVariables.Variables)
        {
            if (entry != null && entry.Name == varName)
            {
                return entry.Value;
            }
        }

        return defaultValue;
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainNodeResource"/> class.
    /// </summary>
    public TerrainNodeResource()
    {
    }
}
