using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Editor visual element representing a text comment node in the graph.
/// </summary>
[Tool]
public partial class TerrainGraphComment : GraphNode
{
    private TextEdit _textEdit;
    private Button _closeBtn;
    private bool _isCleanedUp = false;

    /// <summary>
    /// Signal emitted when the close button of the node is clicked.
    /// </summary>
    public event Action<TerrainGraphComment> NodeCloseRequested;

    /// <summary>
    /// Gets the serialized resource representing this comment's configuration.
    /// </summary>
    public GraphCommentData Resource { get; private set; }

    /// <summary>
    /// Initializes the visual comment node from its serialized resource.
    /// </summary>
    /// <param name="res">The serialized comment data.</param>
    public void Initialize(GraphCommentData res)
    {
        Resource = res;
        Title = res.Title;
        PositionOffset = res.Position;
        Size = res.Size;
        Resizable = true;

        // Clear ports
        ClearAllSlots();

        // Add custom close button programmatically in Godot 4
        var titleBar = GetTitlebarHBox();
        if (titleBar != null)
        {
            _closeBtn = new Button { Text = "x", Flat = true };
            _closeBtn.Pressed += OnCloseRequest;
            titleBar.AddChild(_closeBtn);
        }

        // Modern visual styling
        var bg = new StyleBoxFlat();
        bg.BgColor = new Color(0.15f, 0.15f, 0.12f, 0.9f); // yellowish/parchment tint comment node
        bg.BorderWidthLeft = 1;
        bg.BorderWidthRight = 1;
        bg.BorderWidthTop = 1;
        bg.BorderWidthBottom = 1;
        bg.BorderColor = new Color(0.35f, 0.35f, 0.25f, 0.6f);
        bg.CornerRadiusTopLeft = 4;
        bg.CornerRadiusTopRight = 4;
        bg.CornerRadiusBottomLeft = 4;
        bg.CornerRadiusBottomRight = 4;
        AddThemeStyleboxOverride("panel", bg);

        _textEdit = new TextEdit();
        _textEdit.Text = res.Text;
        _textEdit.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        _textEdit.SizeFlagsVertical = SizeFlags.ExpandFill;
        _textEdit.CustomMinimumSize = new Vector2(160, 80);
        _textEdit.TextChanged += OnTextChanged;
        
        AddChild(_textEdit);

        PositionOffsetChanged += OnPositionChanged;
        ResizeEnd += OnResizeEnd;
    }

    private void CleanUp()
    {
        if (_isCleanedUp) return;
        _isCleanedUp = true;

        if (_closeBtn != null && GodotObject.IsInstanceValid(_closeBtn))
        {
            if (_closeBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.OnCloseRequest)))
            {
                try
                {
                    _closeBtn.Pressed -= OnCloseRequest;
                }
                catch { }
            }
        }
        if (_textEdit != null && GodotObject.IsInstanceValid(_textEdit))
        {
            if (_textEdit.IsConnected(TextEdit.SignalName.TextChanged, new Callable(this, MethodName.OnTextChanged)))
            {
                try
                {
                    _textEdit.TextChanged -= OnTextChanged;
                }
                catch { }
            }
        }
        if (IsConnected(GraphElement.SignalName.PositionOffsetChanged, new Callable(this, MethodName.OnPositionChanged)))
        {
            try
            {
                PositionOffsetChanged -= OnPositionChanged;
            }
            catch { }
        }
        if (IsConnected(GraphNode.SignalName.ResizeEnd, new Callable(this, MethodName.OnResizeEnd)))
        {
            try
            {
                ResizeEnd -= OnResizeEnd;
            }
            catch { }
        }

        NodeCloseRequested = null;
        CommentModified = null;
    }

    /// <summary>
    /// Called when the node leaves the scene tree.
    /// Cleans up signal delegates to prevent interop leaks.
    /// </summary>
    public override void _ExitTree()
    {
        CleanUp();
        base._ExitTree();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            CleanUp();
            try
            {
                QueueFree();
            }
            catch { }
        }
        base.Dispose(disposing);
    }

    private void OnCloseRequest()
    {
        NodeCloseRequested?.Invoke(this);
    }

    /// <summary>
    /// Event emitted when the comment position, size, or text is modified.
    /// </summary>
    public event Action<TerrainGraphComment> CommentModified;

    private void OnTextChanged()
    {
        if (Resource != null && _textEdit != null)
        {
            Resource.Text = _textEdit.Text;
            CommentModified?.Invoke(this);
        }
    }

    private void OnPositionChanged()
    {
        if (Resource != null)
        {
            Resource.Position = PositionOffset;
            CommentModified?.Invoke(this);
        }
    }

    private void OnResizeEnd(Vector2 newSize)
    {
        if (Resource != null)
        {
            Resource.Size = newSize;
            CommentModified?.Invoke(this);
        }
    }
}
