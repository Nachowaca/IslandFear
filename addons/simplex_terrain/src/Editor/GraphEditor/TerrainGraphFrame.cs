using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Editor visual element representing a node frame backdrop for organizing node groups.
/// </summary>
[Tool]
public partial class TerrainGraphFrame : GraphFrame
{
    /// <summary>
    /// Gets the serialized resource representing this frame's configuration.
    /// </summary>
    public GraphFrameData Resource { get; private set; }

    private Button _closeBtn;
    private bool _isCleanedUp = false;

    /// <summary>
    /// Signal emitted when the close button of the frame is clicked.
    /// </summary>
    public event Action<TerrainGraphFrame> NodeCloseRequested;

    /// <summary>
    /// Initializes the visual frame from its serialized resource.
    /// </summary>
    /// <param name="res">The serialized frame data.</param>
    public void Initialize(GraphFrameData res)
    {
        Resource = res;
        Title = res.Title;
        PositionOffset = res.Position;
        Size = res.Size;
        
        // Set tint color
        TintColor = res.FrameColor;

        // Add custom close button programmatically in Godot 4
        var titleBar = GetTitlebarHBox();
        if (titleBar != null)
        {
            _closeBtn = new Button { Text = "x", Flat = true };
            _closeBtn.Pressed += OnCloseRequest;
            titleBar.AddChild(_closeBtn);
        }
        
        // Connect dragged/resized signals to update the resource in real-time
        PositionOffsetChanged += OnPositionChanged;
        NodeSelected += OnFrameSelected;
    }

    /// <summary>
    /// Called when the node leaves the scene tree.
    /// Cleans up signal delegates to prevent interop leaks.
    /// </summary>
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
        if (IsConnected(GraphElement.SignalName.PositionOffsetChanged, new Callable(this, MethodName.OnPositionChanged)))
        {
            try
            {
                PositionOffsetChanged -= OnPositionChanged;
            }
            catch { }
        }
        if (IsConnected(SignalName.NodeSelected, new Callable(this, MethodName.OnFrameSelected)))
        {
            try
            {
                NodeSelected -= OnFrameSelected;
            }
            catch { }
        }

        NodeCloseRequested = null;
        FrameDragged = null;
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
    /// Event emitted when the frame is dragged or resized.
    /// </summary>
    public event Action<TerrainGraphFrame> FrameDragged;

    private void OnPositionChanged()
    {
        if (Resource != null)
        {
            Resource.Position = PositionOffset;
            Resource.Size = Size;
            FrameDragged?.Invoke(this);
        }
    }

    private void OnFrameSelected()
    {
        // Highlight in inspector
        if (Resource != null)
        {
            // We can emit a signal or inspect
        }
    }
}
