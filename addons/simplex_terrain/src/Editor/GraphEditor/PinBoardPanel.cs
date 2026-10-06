using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

/// <summary>
/// A modern interactive popup panel overlay for managing chunk pinning (locking) and bypassing (disabling) manually.
/// </summary>
[Tool]
public partial class PinBoardPanel : ColorRect
{
    private TerrainManager _activeManager;
    private PanelContainer _dialog;
    private GridContainer _grid;
    private Label _infoLabel;
    
    private int _centerChunkX = 0;
    private int _centerChunkZ = 0;
    
    private readonly List<Button> _cellButtons = new List<Button>();
    private readonly Dictionary<Button, ChunkCoordinate> _buttonCoords = new Dictionary<Button, ChunkCoordinate>();
    private Button _closeBtn;
    private Button _centerBtn;
    private Button _clearBtn;
    private Button _applyBtn;
    private bool _isCleanedUp = false;

    public PinBoardPanel()
    {
        // Dark translucent overlay background
        Color = new Color(0, 0, 0, 0.45f);
        SetAnchorsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Stop;
    }

    public override void _Ready()
    {
        // Build the dialog window programmatically
        _dialog = new PanelContainer();
        _dialog.CustomMinimumSize = new Vector2(480, 520);
        _dialog.SizeFlagsHorizontal = SizeFlags.ShrinkCenter;
        _dialog.SizeFlagsVertical = SizeFlags.ShrinkCenter;
        AddChild(_dialog);

        // Modern glassy dark theme stylebox
        var bgStyle = new StyleBoxFlat();
        bgStyle.BgColor = new Color(0.12f, 0.12f, 0.14f, 0.96f);
        bgStyle.BorderWidthLeft = 1;
        bgStyle.BorderWidthRight = 1;
        bgStyle.BorderWidthTop = 1;
        bgStyle.BorderWidthBottom = 1;
        bgStyle.BorderColor = new Color(0.24f, 0.24f, 0.28f, 0.8f);
        bgStyle.CornerRadiusTopLeft = 8;
        bgStyle.CornerRadiusTopRight = 8;
        bgStyle.CornerRadiusBottomLeft = 8;
        bgStyle.CornerRadiusBottomRight = 8;
        bgStyle.ContentMarginLeft = 16;
        bgStyle.ContentMarginRight = 16;
        bgStyle.ContentMarginTop = 16;
        bgStyle.ContentMarginBottom = 16;
        _dialog.AddThemeStyleboxOverride("panel", bgStyle);

        var mainVbox = new VBoxContainer();
        mainVbox.AddThemeConstantOverride("separation", 12);
        _dialog.AddChild(mainVbox);

        // 1. Header Row
        var header = new HBoxContainer();
        mainVbox.AddChild(header);

        var title = new Label();
        title.Text = "MANAGE CHUNK PIN BOARD";
        title.AddThemeFontSizeOverride("font_size", 13);
        title.AddThemeColorOverride("font_color", new Color(0.9f, 0.9f, 0.95f));
        header.AddChild(title);

        var spacer = new Control();
        spacer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        header.AddChild(spacer);

        _closeBtn = new Button();
        _closeBtn.Text = " X ";
        _closeBtn.Flat = true;
        _closeBtn.Pressed += HidePanel;
        _closeBtn.AddThemeColorOverride("font_color", new Color(0.7f, 0.7f, 0.7f));
        _closeBtn.AddThemeFontSizeOverride("font_size", 12);
        header.AddChild(_closeBtn);

        // 2. Instructions Label
        _infoLabel = new Label();
        _infoLabel.Text = "Click cells to toggle: Left-Click = Pin/Lock | Right-Click = Bypass/Disable | Shift-Click = Clear";
        _infoLabel.AddThemeFontSizeOverride("font_size", 10);
        _infoLabel.AddThemeColorOverride("font_color", new Color(0.6f, 0.6f, 0.65f));
        _infoLabel.AutowrapMode = TextServer.AutowrapMode.Word;
        mainVbox.AddChild(_infoLabel);

        // 3. Grid Container (11 x 11)
        var gridScroll = new ScrollContainer();
        gridScroll.SizeFlagsVertical = SizeFlags.ExpandFill;
        mainVbox.AddChild(gridScroll);

        var gridCenter = new CenterContainer();
        gridCenter.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        gridCenter.SizeFlagsVertical = SizeFlags.ExpandFill;
        gridScroll.AddChild(gridCenter);

        _grid = new GridContainer();
        _grid.Columns = 11;
        _grid.AddThemeConstantOverride("h_separation", 3);
        _grid.AddThemeConstantOverride("v_separation", 3);
        gridCenter.AddChild(_grid);

        // Create 121 cells
        for (int i = 0; i < 121; i++)
        {
            var btn = new Button();
            btn.CustomMinimumSize = new Vector2(34, 34);
            btn.MouseFilter = MouseFilterEnum.Stop;
            btn.AddThemeFontSizeOverride("font_size", 8);
            
            // Store cell index in metadata for lookup by shared handler (no lambda capture)
            btn.SetMeta("cell_index", i);
            btn.GuiInput += OnCellGuiInputShared;
            
            _grid.AddChild(btn);
            _cellButtons.Add(btn);
        }

        // 4. Legend area
        var legend = new HBoxContainer();
        legend.Alignment = BoxContainer.AlignmentMode.Center;
        legend.AddThemeConstantOverride("separation", 16);
        mainVbox.AddChild(legend);

        legend.AddChild(CreateLegendItem("Unloaded", new Color(0.18f, 0.18f, 0.2f, 0.4f)));
        legend.AddChild(CreateLegendItem("Loaded", new Color(0.2f, 0.6f, 0.3f, 0.4f)));
        legend.AddChild(CreateLegendItem("Locked", new Color(0.15f, 0.4f, 0.8f, 0.8f)));
        legend.AddChild(CreateLegendItem("Bypassed", new Color(0.8f, 0.15f, 0.15f, 0.8f)));

        // 5. Actions row
        var actions = new HBoxContainer();
        actions.Alignment = BoxContainer.AlignmentMode.End;
        actions.AddThemeConstantOverride("separation", 10);
        mainVbox.AddChild(actions);

        _centerBtn = new Button();
        _centerBtn.Text = "Center on Camera";
        _centerBtn.Pressed += RecenterOnCamera;
        _centerBtn.AddThemeFontSizeOverride("font_size", 11);
        actions.AddChild(_centerBtn);

        _clearBtn = new Button();
        _clearBtn.Text = "Clear All Pins";
        _clearBtn.Pressed += ClearAllPins;
        _clearBtn.AddThemeFontSizeOverride("font_size", 11);
        actions.AddChild(_clearBtn);

        _applyBtn = new Button();
        _applyBtn.Text = "Apply & Rebuild";
        _applyBtn.Pressed += ApplyAndRebuild;
        _applyBtn.AddThemeFontSizeOverride("font_size", 11);
        actions.AddChild(_applyBtn);

        // Layout alignment
        ReshapeOverlay();
        Resized += ReshapeOverlay;
    }

    private void ReshapeOverlay()
    {
        if (_dialog != null)
        {
            _dialog.Position = (Size - _dialog.Size) / 2.0f;
        }
    }

    private Control CreateLegendItem(string labelText, Color color)
    {
        var hbox = new HBoxContainer();
        hbox.AddThemeConstantOverride("separation", 4);
        
        var swatch = new ColorRect();
        swatch.CustomMinimumSize = new Vector2(10, 10);
        swatch.Color = color;
        hbox.AddChild(swatch);

        var label = new Label();
        label.Text = labelText;
        label.AddThemeFontSizeOverride("font_size", 9);
        label.AddThemeColorOverride("font_color", new Color(0.75f, 0.75f, 0.75f));
        hbox.AddChild(label);

        return hbox;
    }

    /// <summary>
    /// Configures the active manager and initializes the grid coordinates.
    /// </summary>
    public void Open(TerrainManager manager)
    {
        _activeManager = manager;
        Visible = true;
        
        // Find camera position to center on
        _centerChunkX = 0;
        _centerChunkZ = 0;
        
        if (manager != null)
        {
            NodePath camPath = manager.CameraNodePath;
            Camera3D camera = null;
            if (camPath != null && !camPath.IsEmpty)
            {
                camera = manager.GetNodeOrNull<Camera3D>(camPath);
            }
            if (camera == null)
            {
                camera = manager.GetViewport().GetCamera3D();
            }

            if (camera != null)
            {
                Vector3 camPos = camera.GlobalPosition;
                _centerChunkX = Mathf.FloorToInt(camPos.X / manager.ChunkWorldSize);
                _centerChunkZ = Mathf.FloorToInt(camPos.Z / manager.ChunkWorldSize);
            }
        }

        RefreshGrid();
        ReshapeOverlay();
    }

    private void RefreshGrid()
    {
        _buttonCoords.Clear();
        int btnIndex = 0;

        for (int r = 0; r < 11; r++)
        {
            for (int c = 0; c < 11; c++)
            {
                int coordX = _centerChunkX + (c - 5);
                int coordZ = _centerChunkZ + (5 - r); // north is positive Z or negative Z? Typically positive Z is south, so north is negative Z.
                
                var coord = new ChunkCoordinate(coordX, coordZ);
                var btn = _cellButtons[btnIndex];
                
                _buttonCoords[btn] = coord;
                btn.Text = $"{coordX}\n{coordZ}";
                
                UpdateButtonVisual(btn, coord);
                btnIndex++;
            }
        }
    }

    private void UpdateButtonVisual(Button btn, ChunkCoordinate coord)
    {
        var style = new StyleBoxFlat();
        style.BorderWidthLeft = 1;
        style.BorderWidthRight = 1;
        style.BorderWidthTop = 1;
        style.BorderWidthBottom = 1;
        style.CornerRadiusTopLeft = 3;
        style.CornerRadiusTopRight = 3;
        style.CornerRadiusBottomLeft = 3;
        style.CornerRadiusBottomRight = 3;

        if (_activeManager != null && _activeManager.PinnedChunks.Contains(coord))
        {
            // Locked / Pinned: Premium blue accent
            style.BgColor = new Color(0.15f, 0.4f, 0.8f, 0.8f);
            style.BorderColor = new Color(0.3f, 0.6f, 1.0f, 0.9f);
            btn.TooltipText = $"Chunk [{coord.X}, {coord.Z}]: LOCKED (Pinned)";
        }
        else if (_activeManager != null && _activeManager.BypassedChunks.Contains(coord))
        {
            // Bypassed: Crimson red accent
            style.BgColor = new Color(0.8f, 0.15f, 0.15f, 0.8f);
            style.BorderColor = new Color(1.0f, 0.3f, 0.3f, 0.9f);
            btn.TooltipText = $"Chunk [{coord.X}, {coord.Z}]: BYPASSED (Disabled)";
        }
        else if (_activeManager != null && IsChunkLoaded(coord))
        {
            // Loaded but not pinned: Subtle green accent
            style.BgColor = new Color(0.2f, 0.6f, 0.3f, 0.4f);
            style.BorderColor = new Color(0.3f, 0.8f, 0.4f, 0.6f);
            btn.TooltipText = $"Chunk [{coord.X}, {coord.Z}]: LOADED (Dynamic)";
        }
        else
        {
            // Unloaded: Sleek dark slate
            style.BgColor = new Color(0.18f, 0.18f, 0.2f, 0.4f);
            style.BorderColor = new Color(0.25f, 0.25f, 0.3f, 0.3f);
            btn.TooltipText = $"Chunk [{coord.X}, {coord.Z}]: UNLOADED";
        }

        btn.AddThemeStyleboxOverride("normal", style);
        btn.AddThemeStyleboxOverride("hover", CreateHoverStyle(style));
        btn.AddThemeStyleboxOverride("pressed", style);
    }

    private StyleBoxFlat CreateHoverStyle(StyleBoxFlat baseStyle)
    {
        var hover = (StyleBoxFlat)baseStyle.Duplicate();
        hover.BgColor = baseStyle.BgColor + new Color(0.08f, 0.08f, 0.08f, 0.1f);
        hover.BorderColor = baseStyle.BorderColor + new Color(0.15f, 0.15f, 0.15f, 0.1f);
        return hover;
    }

    private bool IsChunkLoaded(ChunkCoordinate coord)
    {
        if (_activeManager == null) return false;
        
        // Use reflection to access private _loadedChunks if needed, or query public properties.
        // Since we are in the same namespace, let's see: _loadedChunks is private but we can use reflection.
        var field = _activeManager.GetType().GetField("_loadedChunks", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        if (field != null)
        {
            var dict = field.GetValue(_activeManager) as Dictionary<ChunkCoordinate, HeightMatrix>;
            return dict != null && dict.ContainsKey(coord);
        }
        return false;
    }

    /// <summary>
    /// Shared handler for all cell button GuiInput signals.
    /// Retrieves the cell index from button metadata to identify which cell was interacted with.
    /// </summary>
    private void OnCellGuiInputShared(InputEvent @event)
    {
        if (@event is InputEventMouseButton mb && mb.Pressed)
        {
            // Find the button that emitted this signal by checking which button has focus or was clicked
            Button btn = null;
            foreach (var cellBtn in _cellButtons)
            {
                if (GodotObject.IsInstanceValid(cellBtn) && cellBtn.HasMeta("cell_index"))
                {
                    // Check if this button's rect contains the mouse position relative to the button
                    var localPos = cellBtn.GetLocalMousePosition();
                    if (new Rect2(Vector2.Zero, cellBtn.Size).HasPoint(localPos))
                    {
                        btn = cellBtn;
                        break;
                    }
                }
            }

            if (btn == null) return;
            if (!_buttonCoords.TryGetValue(btn, out var coord)) return;
            if (_activeManager == null) return;

            bool isShiftPressed = Input.IsKeyPressed(Key.Shift);

            if (isShiftPressed)
            {
                // Clear pin/bypass
                _activeManager.PinnedChunks.Remove(coord);
                _activeManager.BypassedChunks.Remove(coord);
            }
            else if (mb.ButtonIndex == MouseButton.Left)
            {
                // Left click: Toggle Lock/Pin
                if (_activeManager.PinnedChunks.Contains(coord))
                {
                    _activeManager.PinnedChunks.Remove(coord);
                }
                else
                {
                    _activeManager.PinnedChunks.Add(coord);
                    _activeManager.BypassedChunks.Remove(coord);
                }
            }
            else if (mb.ButtonIndex == MouseButton.Right)
            {
                // Right click: Toggle Bypass
                if (_activeManager.BypassedChunks.Contains(coord))
                {
                    _activeManager.BypassedChunks.Remove(coord);
                }
                else
                {
                    _activeManager.BypassedChunks.Add(coord);
                    _activeManager.PinnedChunks.Remove(coord);
                }
            }

            UpdateButtonVisual(btn, coord);
            GetViewport().SetInputAsHandled();
        }
    }

    private void RecenterOnCamera()
    {
        if (_activeManager == null) return;
        
        NodePath camPath = _activeManager.CameraNodePath;
        Camera3D camera = null;
        if (camPath != null && !camPath.IsEmpty)
        {
            camera = _activeManager.GetNodeOrNull<Camera3D>(camPath);
        }
        if (camera == null)
        {
            camera = _activeManager.GetViewport().GetCamera3D();
        }

        if (camera != null)
        {
            Vector3 camPos = camera.GlobalPosition;
            _centerChunkX = Mathf.FloorToInt(camPos.X / _activeManager.ChunkWorldSize);
            _centerChunkZ = Mathf.FloorToInt(camPos.Z / _activeManager.ChunkWorldSize);
            RefreshGrid();
        }
    }

    private void ClearAllPins()
    {
        if (_activeManager == null) return;
        _activeManager.PinnedChunks.Clear();
        _activeManager.BypassedChunks.Clear();
        RefreshGrid();
    }

    private void ApplyAndRebuild()
    {
        if (_activeManager == null) return;
        
        GD.Print("[PinBoardPanel] Applying pins and force-rebuilding terrain...");
        _activeManager.RebuildTerrain();
        
        // Notify parent graph of changes
        HidePanel();
    }

    private void HidePanel()
    {
        Visible = false;
    }

    private void CleanUp()
    {
        if (_isCleanedUp) return;
        _isCleanedUp = true;

        if (_closeBtn != null && GodotObject.IsInstanceValid(_closeBtn))
        {
            if (_closeBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.HidePanel)))
            {
                try
                {
                    _closeBtn.Pressed -= HidePanel;
                }
                catch { }
            }
        }
        if (_centerBtn != null && GodotObject.IsInstanceValid(_centerBtn))
        {
            if (_centerBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.RecenterOnCamera)))
            {
                try
                {
                    _centerBtn.Pressed -= RecenterOnCamera;
                }
                catch { }
            }
        }
        if (_clearBtn != null && GodotObject.IsInstanceValid(_clearBtn))
        {
            if (_clearBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.ClearAllPins)))
            {
                try
                {
                    _clearBtn.Pressed -= ClearAllPins;
                }
                catch { }
            }
        }
        if (_applyBtn != null && GodotObject.IsInstanceValid(_applyBtn))
        {
            if (_applyBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.ApplyAndRebuild)))
            {
                try
                {
                    _applyBtn.Pressed -= ApplyAndRebuild;
                }
                catch { }
            }
        }
            
        if (IsConnected(SignalName.Resized, new Callable(this, MethodName.ReshapeOverlay)))
        {
            try
            {
                Resized -= ReshapeOverlay;
            }
            catch { }
        }

        // Disconnect shared handler from all cell buttons (no lambdas to track)
        foreach (var btn in _cellButtons)
        {
            if (GodotObject.IsInstanceValid(btn))
            {
                if (btn.IsConnected(Control.SignalName.GuiInput, new Callable(this, MethodName.OnCellGuiInputShared)))
                {
                    try
                    {
                        btn.GuiInput -= OnCellGuiInputShared;
                    }
                    catch { }
                }
            }
        }

        _activeManager = null;
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
}
