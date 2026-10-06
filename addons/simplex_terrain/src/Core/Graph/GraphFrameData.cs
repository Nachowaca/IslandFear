using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Serializable resource representing a visual grouping frame backdrop in the node graph.
/// </summary>
[GlobalClass]
[Tool]
public partial class GraphFrameData : Resource
{
    /// <summary>
    /// Gets or sets the frame title.
    /// </summary>
    [Export]
    public string Title { get; set; } = "New Group Frame";

    /// <summary>
    /// Gets or sets the grid position of the frame.
    /// </summary>
    [Export]
    public Vector2 Position { get; set; } = Vector2.Zero;

    /// <summary>
    /// Gets or sets the visual size of the frame.
    /// </summary>
    [Export]
    public Vector2 Size { get; set; } = new Vector2(250, 200);

    /// <summary>
    /// Gets or sets the background border/tint color.
    /// </summary>
    [Export]
    public Color FrameColor { get; set; } = new Color(0.2f, 0.25f, 0.3f, 0.35f);

    /// <summary>
    /// Gets or sets the list of node IDs grouped inside this frame.
    /// </summary>
    [Export]
    public Godot.Collections.Array<string> NodeIds { get; set; } = new Godot.Collections.Array<string>();
}
