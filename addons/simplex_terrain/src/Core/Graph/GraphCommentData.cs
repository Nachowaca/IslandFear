using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Serializable resource representing a standalone visual text comment box in the node graph.
/// </summary>
[GlobalClass]
[Tool]
public partial class GraphCommentData : Resource
{
    /// <summary>
    /// Gets or sets the comment title.
    /// </summary>
    [Export]
    public string Title { get; set; } = "Comment";

    /// <summary>
    /// Gets or sets the text body.
    /// </summary>
    [Export]
    public string Text { get; set; } = "Enter comment here...";

    /// <summary>
    /// Gets or sets the grid position of the comment box.
    /// </summary>
    [Export]
    public Vector2 Position { get; set; } = Vector2.Zero;

    /// <summary>
    /// Gets or sets the visual size of the comment box.
    /// </summary>
    [Export]
    public Vector2 Size { get; set; } = new Vector2(180, 100);
}
