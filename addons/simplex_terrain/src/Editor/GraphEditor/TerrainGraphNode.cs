using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

/// <summary>
/// Visual representation of a terrain graph node in the editor canvas.
/// Inherits from Godot's GraphNode and binds dynamically to its backing TerrainNodeResource.
/// </summary>
[Tool]
public partial class TerrainGraphNode : GraphNode
{
    /// <summary>
    /// Gets the serialized resource carrying this node's parameters.
    /// </summary>
    public TerrainNodeResource NodeResource { get; private set; }

    /// <summary>
    /// Gets the runtime C# execution wrapper instance of the node.
    /// </summary>
    public TerrainNode RuntimeNode { get; private set; }

    private Button _closeBtn;
    private bool _isCleanedUp = false;

    /// <summary>
    /// Signal emitted when the node is dragged in the canvas workspace.
    /// </summary>
    public event Action<TerrainGraphNode, Vector2> NodeDragged;

    /// <summary>
    /// Signal emitted when the close button of the node is clicked.
    /// </summary>
    public event Action<TerrainGraphNode> NodeCloseRequested;

    /// <summary>
    /// Signal emitted when this node is clicked/selected by the user.
    /// </summary>
    public event Action<TerrainGraphNode> NodeSelectedEvent;

    /// <summary>
    /// Parameterless constructor required by Godot engine serialization.
    /// </summary>
    public TerrainGraphNode()
    {
    }

    /// <summary>
    /// Initializes the visual node with its associated resource and runtime representation.
    /// </summary>
    /// <param name="nodeResource">The backing serialized resource.</param>
    /// <param name="runtimeNode">The runtime executor node.</param>
    public void Initialize(TerrainNodeResource nodeResource, TerrainNode runtimeNode)
    {
        NodeResource = nodeResource ?? throw new ArgumentNullException(nameof(nodeResource));
        RuntimeNode = runtimeNode ?? throw new ArgumentNullException(nameof(runtimeNode));
        
        Name = nodeResource.NodeId;
        
        // Process node class name into human-readable Title (e.g. PerlinNoiseNode -> Perlin Noise)
        string displayName = runtimeNode.GetType().Name.Replace("Node", "");
        Title = System.Text.RegularExpressions.Regex.Replace(displayName, "(\\B[A-Z])", " $1");
        
        PositionOffset = nodeResource.EditorPosition;

        // Add custom close button programmatically in Godot 4
        var titleBar = GetTitlebarHBox();
        if (titleBar != null)
        {
            _closeBtn = new Button { Text = "x", Flat = true };
            _closeBtn.Pressed += OnCloseRequest;
            titleBar.AddChild(_closeBtn);
        }

        // Connect events
        Dragged += OnDragged;
        NodeSelected += OnNodeSelected;

        BuildSlots();
        ApplyStyle();
    }

    /// <summary>
    private void CleanUp()
    {
        if (_isCleanedUp) return;
        _isCleanedUp = true;

        if (IsConnected(SignalName.Dragged, new Callable(this, MethodName.OnDragged)))
        {
            try
            {
                Dragged -= OnDragged;
            }
            catch { }
        }
        if (IsConnected(SignalName.NodeSelected, new Callable(this, MethodName.OnNodeSelected)))
        {
            try
            {
                NodeSelected -= OnNodeSelected;
            }
            catch { }
        }

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

        NodeDragged = null;
        NodeCloseRequested = null;
        NodeSelectedEvent = null;
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

    /// <summary>
    /// Dynamically builds input and output slot layouts.
    /// </summary>
    private void BuildSlots()
    {
        // Remove any existing children
        foreach (var child in GetChildren())
        {
            child.QueueFree();
        }

        int slotCount = Math.Max(RuntimeNode.Inputs.Count, RuntimeNode.Outputs.Count);

        for (int i = 0; i < slotCount; i++)
        {
            var row = new HBoxContainer();
            row.CustomMinimumSize = new Vector2(160, 24);
            row.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            row.MouseFilter = MouseFilterEnum.Pass;

            // Left side: Input Port Label
            if (i < RuntimeNode.Inputs.Count)
            {
                var inputPort = RuntimeNode.Inputs[i];
                var label = new Label();
                label.Text = inputPort.Name;
                label.HorizontalAlignment = HorizontalAlignment.Left;
                label.SizeFlagsHorizontal = SizeFlags.ExpandFill;
                label.AddThemeFontSizeOverride("font_size", 11);
                label.AddThemeColorOverride("font_color", new Color(0.85f, 0.85f, 0.85f));
                row.AddChild(label);
            }
            else
            {
                // Spacer if no input port
                var spacer = new Control();
                spacer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
                spacer.MouseFilter = MouseFilterEnum.Pass;
                row.AddChild(spacer);
            }

            // Right side: Output Port Label
            if (i < RuntimeNode.Outputs.Count)
            {
                var outputPort = RuntimeNode.Outputs[i];
                var label = new Label();
                label.Text = outputPort.Name;
                label.HorizontalAlignment = HorizontalAlignment.Right;
                label.SizeFlagsHorizontal = SizeFlags.ExpandFill;
                label.AddThemeFontSizeOverride("font_size", 11);
                label.AddThemeColorOverride("font_color", new Color(0.85f, 0.85f, 0.85f));
                row.AddChild(label);
            }
            else
            {
                // Spacer if no output port
                var spacer = new Control();
                spacer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
                spacer.MouseFilter = MouseFilterEnum.Pass;
                row.AddChild(spacer);
            }

            AddChild(row);

            // Configure slot ports
            bool enableLeft = i < RuntimeNode.Inputs.Count;
            PortType leftType = enableLeft ? RuntimeNode.Inputs[i].Type : PortType.Height;
            Color leftColor = enableLeft ? GetPortColor(leftType) : new Color(1, 1, 1, 0);

            bool enableRight = i < RuntimeNode.Outputs.Count;
            PortType rightType = enableRight ? RuntimeNode.Outputs[i].Type : PortType.Height;
            Color rightColor = enableRight ? GetPortColor(rightType) : new Color(1, 1, 1, 0);

            SetSlot(
                i, 
                enableLeft, 
                (int)leftType, 
                leftColor, 
                enableRight, 
                (int)rightType, 
                rightColor
            );
        }
    }

    /// <summary>
    /// Applies high-fidelity visual styling reflecting the node's functional category.
    /// </summary>
    private void ApplyStyle()
    {
        Color categoryColor = GetCategoryColor(RuntimeNode.GetType().Name);

        // Header style
        var titleBar = new StyleBoxFlat();
        titleBar.BgColor = categoryColor;
        titleBar.ContentMarginLeft = 10;
        titleBar.ContentMarginRight = 10;
        titleBar.ContentMarginTop = 6;
        titleBar.ContentMarginBottom = 6;
        titleBar.CornerRadiusTopLeft = 4;
        titleBar.CornerRadiusTopRight = 4;
        AddThemeStyleboxOverride("titlebar", titleBar);
        AddThemeColorOverride("title_color", new Color(1f, 1f, 1f));

        // Normal Body Style
        var panelStyle = new StyleBoxFlat();
        panelStyle.BgColor = new Color(0.12f, 0.12f, 0.14f, 0.9f); // Dark glassmorphic background
        panelStyle.BorderWidthLeft = 1;
        panelStyle.BorderWidthRight = 1;
        panelStyle.BorderWidthTop = 1;
        panelStyle.BorderWidthBottom = 1;
        panelStyle.BorderColor = categoryColor.Darkened(0.2f);
        panelStyle.CornerRadiusTopLeft = 6;
        panelStyle.CornerRadiusTopRight = 6;
        panelStyle.CornerRadiusBottomLeft = 6;
        panelStyle.CornerRadiusBottomRight = 6;
        panelStyle.ContentMarginLeft = 12;
        panelStyle.ContentMarginRight = 12;
        panelStyle.ContentMarginTop = 8;
        panelStyle.ContentMarginBottom = 8;
        AddThemeStyleboxOverride("panel", panelStyle);

        // Selected Body Style
        var panelSelectedStyle = panelStyle.Duplicate() as StyleBoxFlat;
        panelSelectedStyle.BorderColor = categoryColor.Lightened(0.3f); // Glowing colored border for selection
        panelSelectedStyle.BorderWidthLeft = 2;
        panelSelectedStyle.BorderWidthRight = 2;
        panelSelectedStyle.BorderWidthTop = 2;
        panelSelectedStyle.BorderWidthBottom = 2;
        AddThemeStyleboxOverride("panel_selected", panelSelectedStyle);
    }

    /// <summary>
    /// Maps a port type to its corresponding visual color coding.
    /// </summary>
    public static Color GetPortColor(PortType type)
    {
        return type switch
        {
            PortType.Height => new Color(0.2f, 0.7f, 1.0f),      // Neon Cyan
            PortType.Mask => new Color(1.0f, 0.7f, 0.2f),        // Warm Amber
            PortType.Splat => new Color(1.0f, 0.4f, 0.2f),       // Radiant Orange
            PortType.Spline => new Color(0.2f, 0.8f, 0.5f),      // Emerald Green
            PortType.Instance => new Color(0.8f, 0.3f, 1.0f),    // Electric Violet
            PortType.Scalar => new Color(0.8f, 0.8f, 0.8f),      // Soft Gray
            _ => new Color(1.0f, 1.0f, 1.0f)
        };
    }

    /// <summary>
    /// Detects and returns a color corresponding to a node's functional category.
    /// </summary>
    public static Color GetCategoryColor(string nodeType)
    {
        if (nodeType.Contains("Noise") || nodeType.Contains("Constant") || nodeType.Contains("PrimitiveForm") || nodeType.Contains("Spot") || nodeType.Contains("Voronoi"))
        {
            return new Color(0.15f, 0.4f, 0.8f); // Blue for Generators
        }
        if (nodeType.Contains("Biome"))
        {
            return new Color(0.1f, 0.6f, 0.3f); // Emerald for Biomes
        }
        if (nodeType.Contains("Spline") || nodeType.Contains("Gabriel") || nodeType.Contains("Dijkstra") || nodeType.Contains("Path"))
        {
            return new Color(0.1f, 0.5f, 0.6f); // Teal for Splines
        }
        if (nodeType.Contains("Scatter") || nodeType.Contains("Prune") || nodeType.Contains("Decimation") || nodeType.Contains("Snap") || nodeType.Contains("Dispersal") || nodeType.Contains("Excavation") || nodeType.Contains("Forest") || nodeType.Contains("Particle") || nodeType.Contains("Sliding"))
        {
            return new Color(0.9f, 0.45f, 0.1f); // Orange for Scatter
        }
        if (nodeType.Contains("Output") || nodeType.Contains("Export"))
        {
            return new Color(0.8f, 0.15f, 0.15f); // Crimson for Outputs
        }

        // Fallback / Modifiers
        return new Color(0.5f, 0.2f, 0.8f); // Purple for Modifiers
    }

    private void OnDragged(Vector2 from, Vector2 to)
    {
        if (NodeResource != null)
        {
            NodeResource.EditorPosition = to;
            NodeDragged?.Invoke(this, to);
        }
    }

    private void OnCloseRequest()
    {
        NodeCloseRequested?.Invoke(this);
    }

    private void OnNodeSelected()
    {
        NodeSelectedEvent?.Invoke(this);
    }
}
