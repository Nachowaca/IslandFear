using Godot;
using System;
using SimpleXTerrain;

/// <summary>
/// A first-person fly camera that controls like Minecraft's Creative Mode flight.
/// WASD moves horizontally relative to the look direction.
/// Space flies vertically up, Shift flies vertically down.
/// Ctrl boosts movement speed (sprinting).
/// Mouse click captures the mouse for looking around, Escape releases it.
/// Also implements an in-scene Minecraft-style F3 debug overlay showing spatial/terrain metrics.
/// </summary>
public partial class FlyCamera : Camera3D
{
    [Export]
    public float BaseSpeed { get; set; } = 30.0f;

    [Export]
    public float BoostMultiplier { get; set; } = 3.0f;

    [Export]
    public float MouseSensitivity { get; set; } = 0.002f;

    private float _yaw = 0.0f;
    private float _pitch = 0.0f;
    private bool _isMouseCaptured = false;

    // F3 Debug HUD State
    private CanvasLayer _hudLayer;
    private PanelContainer _hudPanel;
    private RichTextLabel _hudLabel;
    private bool _isHudVisible = false;
    private double _hudUpdateTimer = 0.0;
    private const double HUD_UPDATE_INTERVAL = 0.05; // 20 FPS updates for the HUD metrics

    private TerrainManager _manager;

    public override void _Ready()
    {
        // Start with mouse captured to allow looking around immediately on startup
        CaptureMouse();

        // Initialize yaw and pitch based on current rotation
        Vector3 rotation = Rotation;
        _yaw = rotation.Y;
        _pitch = rotation.Z; // Pitch is around X in Godot, but let's calculate properly from basis
        
        // Extract pitch and yaw from transform basis to be safe and accurate
        Vector3 direction = -GlobalTransform.Basis.Z;
        _yaw = MathF.Atan2(direction.X, direction.Z);
        _pitch = MathF.Asin(direction.Y);
    }

    public override void _ExitTree()
    {
        DestroyHud();
        base._ExitTree();
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseBtn)
        {
            if (mouseBtn.Pressed && mouseBtn.ButtonIndex == MouseButton.Left)
            {
                CaptureMouse();
            }
        }
        else if (@event is InputEventKey keyEvent)
        {
            if (keyEvent.Pressed && !keyEvent.Echo)
            {
                if (keyEvent.Keycode == Key.Escape)
                {
                    ReleaseMouse();
                }
                else if (keyEvent.Keycode == Key.F3)
                {
                    ToggleDebugHud();
                }
                else if (keyEvent.Keycode == Key.F5 || keyEvent.Keycode == Key.F12)
                {
                    CaptureScreenshot();
                }
            }
        }
        else if (@event is InputEventMouseMotion mouseMotion && _isMouseCaptured)
        {
            // Update yaw (horizontal rotation, left-right) and pitch (vertical rotation, up-down)
            _yaw -= mouseMotion.Relative.X * MouseSensitivity;
            _pitch -= mouseMotion.Relative.Y * MouseSensitivity;

            // Clamp pitch to prevent flipping upside down (Minecraft/Creative clamps it)
            _pitch = Mathf.Clamp(_pitch, -Mathf.Pi / 2.0f + 0.01f, Mathf.Pi / 2.0f - 0.01f);

            // Re-apply rotation
            Rotation = new Vector3(_pitch, _yaw, 0.0f);
        }
    }

    public override void _Process(double delta)
    {
        // Update debug HUD if visible
        if (_isHudVisible)
        {
            _hudUpdateTimer += delta;
            if (_hudUpdateTimer >= HUD_UPDATE_INTERVAL)
            {
                _hudUpdateTimer = 0.0;
                UpdateHudText();
            }
        }

        // Don't move if mouse is not captured (helps when navigating UI or menus)
        if (!_isMouseCaptured)
        {
            return;
        }

        Vector3 direction = Vector3.Zero;

        // Get horizontal forward/right vectors relative to camera orientation
        Vector3 forward = -GlobalTransform.Basis.Z;
        Vector3 right = GlobalTransform.Basis.X;

        // Project onto horizontal plane (XZ) to match Minecraft creative flight behavior
        forward.Y = 0.0f;
        right.Y = 0.0f;

        if (forward.LengthSquared() > 0.0001f)
        {
            forward = forward.Normalized();
        }
        if (right.LengthSquared() > 0.0001f)
        {
            right = right.Normalized();
        }

        // WASD key polling
        if (Input.IsKeyPressed(Key.W))
        {
            direction += forward;
        }
        if (Input.IsKeyPressed(Key.S))
        {
            direction -= forward;
        }
        if (Input.IsKeyPressed(Key.D))
        {
            direction += right;
        }
        if (Input.IsKeyPressed(Key.A))
        {
            direction -= right;
        }

        if (direction.LengthSquared() > 0.0001f)
        {
            direction = direction.Normalized();
        }

        // Space/Shift for vertical flight (global coordinates)
        if (Input.IsKeyPressed(Key.Space))
        {
            direction.Y += 1.0f;
        }
        if (Input.IsKeyPressed(Key.Shift))
        {
            direction.Y -= 1.0f;
        }

        // Speed calculation (Base vs Boosted)
        float currentSpeed = BaseSpeed;
        if (Input.IsKeyPressed(Key.Ctrl))
        {
            currentSpeed *= BoostMultiplier;
        }

        // Apply movement frame-rate independently
        GlobalPosition += direction * currentSpeed * (float)delta;
    }

    private void CaptureMouse()
    {
        Input.MouseMode = Input.MouseModeEnum.Captured;
        _isMouseCaptured = true;
    }

    private void ReleaseMouse()
    {
        Input.MouseMode = Input.MouseModeEnum.Visible;
        _isMouseCaptured = false;
    }

    // ==========================================
    // Minecraft-Style F3 Debug HUD Overlay
    // ==========================================

    private void ToggleDebugHud()
    {
        _isHudVisible = !_isHudVisible;
        if (_isHudVisible)
        {
            CreateHud();
            UpdateHudText(); // Force immediate update
        }
        else
        {
            DestroyHud();
        }
    }

    private void CreateHud()
    {
        if (_hudLayer != null) return;

        // Create CanvasLayer for high rendering priority
        _hudLayer = new CanvasLayer();
        _hudLayer.Layer = 100;
        AddChild(_hudLayer);

        // Premium Dark Glassmorphism container panel
        _hudPanel = new PanelContainer();
        _hudPanel.Position = new Vector2(20, 20);
        
        var styleBox = new StyleBoxFlat();
        styleBox.BgColor = new Color(0.04f, 0.05f, 0.08f, 0.82f); // Deep obsidian blue-black
        styleBox.BorderColor = new Color(0.25f, 0.4f, 0.65f, 0.5f); // Neon sci-fi border highlight
        styleBox.SetBorderWidthAll(2);
        styleBox.CornerRadiusTopLeft = 8;
        styleBox.CornerRadiusTopRight = 8;
        styleBox.CornerRadiusBottomLeft = 8;
        styleBox.CornerRadiusBottomRight = 8;
        styleBox.ContentMarginLeft = 16;
        styleBox.ContentMarginTop = 16;
        styleBox.ContentMarginRight = 16;
        styleBox.ContentMarginBottom = 16;
        
        _hudPanel.AddThemeStyleboxOverride("panel", styleBox);
        _hudLayer.AddChild(_hudPanel);

        // RichTextLabel for formatted colorful metrics
        _hudLabel = new RichTextLabel();
        _hudLabel.BbcodeEnabled = true;
        _hudLabel.FitContent = true;
        _hudLabel.CustomMinimumSize = new Vector2(420, 320);
        
        // Load Monospace system font dynamically to look like F3 console/terminal
        _hudLabel.AddThemeFontOverride("normal_font", GetMonospaceFont());
        _hudLabel.AddThemeFontSizeOverride("normal_font_size", 14);

        _hudPanel.AddChild(_hudLabel);
    }

    private void DestroyHud()
    {
        if (_hudLayer != null)
        {
            _hudLayer.QueueFree();
            _hudLayer = null;
            _hudPanel = null;
            _hudLabel = null;
        }
    }

    private Font GetMonospaceFont()
    {
        try
        {
            var systemFont = new SystemFont();
            systemFont.FontNames = new string[] { "Consolas", "Courier New", "Courier", "Monospace", "DejaVu Sans Mono", "Fira Code" };
            return systemFont;
        }
        catch
        {
            return ThemeDB.FallbackFont;
        }
    }

    private TerrainManager FindTerrainManager()
    {
        if (_manager != null && GodotObject.IsInstanceValid(_manager))
        {
            return _manager;
        }

        // 1. Sibling lookup
        var parent = GetParent();
        if (parent != null)
        {
            _manager = parent.GetNodeOrNull<TerrainManager>("TerrainManager");
            if (_manager != null) return _manager;

            foreach (var child in parent.GetChildren())
            {
                if (child is TerrainManager tm)
                {
                    _manager = tm;
                    return _manager;
                }
            }
        }

        // 2. Global search fallback
        var root = GetTree()?.Root;
        if (root != null)
        {
            _manager = FindNodeOfType<TerrainManager>(root);
        }

        return _manager;
    }

    private T FindNodeOfType<T>(Node node) where T : Node
    {
        if (node is T match) return match;
        foreach (var child in node.GetChildren())
        {
            var res = FindNodeOfType<T>(child);
            if (res != null) return res;
        }
        return null;
    }

    private GodotObject GetTerrain3DData()
    {
        var tm = FindTerrainManager();
        if (tm == null) return null;
        
        var path = tm.Terrain3DNodePath;
        if (path.IsEmpty) return null;
        
        var node = tm.GetNodeOrNull(path);
        if (node == null) return null;
        
        return node.Get("data").As<GodotObject>();
    }

    private void UpdateHudText()
    {
        if (_hudLabel == null || !GodotObject.IsInstanceValid(_hudLabel)) return;

        // 1. System Info
        double fps = Engine.GetFramesPerSecond();
        double frameTimeMs = 1000.0 / Math.Max(fps, 1.0);
        ulong staticMem = OS.GetStaticMemoryUsage();
        double staticMemMb = staticMem / (1024.0 * 1024.0);

        // 2. Spatial Calculations
        Vector3 camPos = GlobalPosition;
        var tm = FindTerrainManager();
        float chunkWorldSize = tm != null ? tm.ChunkWorldSize : 512.0f;
        int chunkRes = tm != null ? tm.ChunkResolution : 512;
        string activeGraph = "None";
        if (tm != null && tm.Graph != null)
        {
            activeGraph = System.IO.Path.GetFileName(tm.Graph.ResourcePath);
            if (string.IsNullOrEmpty(activeGraph))
            {
                activeGraph = tm.Graph.ResourceName;
            }
            if (string.IsNullOrEmpty(activeGraph))
            {
                activeGraph = "Unnamed Graph";
            }
        }

        int chunkX = Mathf.FloorToInt(camPos.X / chunkWorldSize);
        int chunkZ = Mathf.FloorToInt(camPos.Z / chunkWorldSize);
        var chunkCoord = new ChunkCoordinate(chunkX, chunkZ);

        int regionX = Mathf.FloorToInt(camPos.X / 256.0f);
        int regionZ = Mathf.FloorToInt(camPos.Z / 256.0f);

        // 3. Terrain3D Height Queries
        float vertexHeight = 0.0f;
        bool heightQueried = false;
        var terrainData = GetTerrain3DData();
        if (terrainData != null && GodotObject.IsInstanceValid(terrainData))
        {
            try
            {
                vertexHeight = terrainData.Call("get_height", camPos).As<float>();
                heightQueried = true;
            }
            catch
            {
                // Soft ignore
            }
        }

        float clearance = camPos.Y - vertexHeight;

        // 4. Chunk & Thread-Safe HeightMatrix Bounds
        int loadedChunks = tm != null ? tm.GetLoadedChunkCount() : 0;
        int activeChunkRes = tm != null ? tm.GetChunkResolution(chunkCoord) : -1;
        float chunkMinHeight = 0.0f;
        float chunkMaxHeight = 0.0f;
        bool hasChunkHeightRange = false;
        if (tm != null)
        {
            hasChunkHeightRange = tm.GetChunkHeightRange(chunkCoord, out chunkMinHeight, out chunkMaxHeight);
        }

        // 5. Render BBCode layout
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("[color=#5cd6ff][b]SimpleXTerrain Real-Time Debug HUD[/b][/color]");
        sb.AppendLine($"[color=#a0a0a0]Engine: Godot v{Engine.GetVersionInfo()["string"]}[/color]");
        sb.AppendLine($"[color=#808080]========================================[/color]");
        
        string fpsColor = fps >= 55 ? "#66ff66" : (fps >= 30 ? "#ffcc00" : "#ff3333");
        sb.AppendLine($"FPS: [color={fpsColor}]{fps:F0}[/color] ({frameTimeMs:F2} ms) | Mem: [color=#cca3ff]{staticMemMb:F1} MB[/color]");

        sb.AppendLine($"XYZ: [color=#ff5555]{camPos.X:F2}[/color] / [color=#55ff55]{camPos.Y:F2}[/color] / [color=#55ffff]{camPos.Z:F2}[/color]");
        sb.AppendLine($"Chunk: [color=#ffd24d]({chunkX}, {chunkZ})[/color]  | World size: [color=#ffd24d]{chunkWorldSize}m[/color]");
        sb.AppendLine($"Region: [color=#ff9933]({regionX}, {regionZ})[/color] | Region size: [color=#ff9933]256m[/color]");

        sb.AppendLine($"[color=#808080]========================================[/color]");
        sb.AppendLine($"Active Graph: [color=#66ffcc]{activeGraph}[/color]");
        sb.AppendLine($"Loaded Chunks: [color=#66ffcc]{loadedChunks}[/color]");
        
        string resStr = activeChunkRes > 0 ? $"{activeChunkRes}x{activeChunkRes}" : "Not Loaded";
        sb.AppendLine($"Current Chunk Res: [color=#ffd24d]{resStr}[/color]");

        if (hasChunkHeightRange)
        {
            sb.AppendLine($"Gen Height Bounds: [color=#cca3ff]{chunkMinHeight:F1}m[/color] to [color=#cca3ff]{chunkMaxHeight:F1}m[/color]");
        }
        else
        {
            sb.AppendLine($"Gen Height Bounds: [color=#cca3ff]N/A (Not Loaded)[/color]");
        }

        if (heightQueried)
        {
            sb.AppendLine($"Vertex Height:     [color=#55ff55]{vertexHeight:F2}m[/color]");
            string clearanceColor = clearance >= 0 ? "#ffd24d" : "#ff5555";
            sb.AppendLine($"Camera Clearance:  [color={clearanceColor}]{clearance:F2}m[/color]");
        }
        else
        {
            sb.AppendLine($"Vertex Height:     [color=#808080]N/A (No Terrain3D Data)[/color]");
            sb.AppendLine($"Camera Clearance:  [color=#808080]N/A[/color]");
        }

        _hudLabel.Text = sb.ToString();
    }

    // ==========================================
    // High-Quality HUD-Free Screenshot System
    // ==========================================

    private async void CaptureScreenshot()
    {
        GD.Print("[Screenshot] Initiating high-quality HUD-free screenshot capture...");
        
        // 1. Temporarily hide F3 debug HUD if it is active
        bool wasHudVisible = _isHudVisible;
        if (_hudLayer != null)
        {
            _hudLayer.Visible = false;
        }

        // 2. Wait for two frames to ensure the HUD is completely removed from the viewport draw buffer
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        try
        {
            // 3. Grab the active viewport's rendered texture image
            Viewport viewport = GetViewport();
            if (viewport != null)
            {
                ViewportTexture texture = viewport.GetTexture();
                if (texture != null)
                {
                    Image image = texture.GetImage();
                    if (image != null)
                    {
                        string dirPath = "res://screenshots";
                        using DirAccess dir = DirAccess.Open("res://");
                        if (dir != null && !dir.DirExists(dirPath))
                        {
                            dir.MakeDir(dirPath);
                        }

                        // Generate timestamped filename
                        string timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
                        string fileName = $"screenshot_{timestamp}.png";
                        string fullPath = $"{dirPath}/{fileName}";

                        // Save image as PNG
                        Error err = image.SavePng(fullPath);
                        if (err == Error.Ok)
                        {
                            GD.Print($"[Screenshot] Successfully saved high-quality screenshot to: {fullPath}");
                            DisplayScreenshotNotification(fileName);
                        }
                        else
                        {
                            GD.PrintErr($"[Screenshot] Failed to save screenshot. Error: {err}");
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[Screenshot] Exception during capture: {ex.Message}");
        }

        // 4. Restore the F3 debug HUD if it was visible
        if (_hudLayer != null && wasHudVisible)
        {
            _hudLayer.Visible = true;
        }
    }

    private async void DisplayScreenshotNotification(string fileName)
    {
        // Create a temporary canvas layer for visual feedback
        CanvasLayer notifLayer = new CanvasLayer();
        notifLayer.Layer = 101; // Draw above the debug HUD
        AddChild(notifLayer);

        PanelContainer panel = new PanelContainer();
        // Place it bottom center
        panel.SetAnchorsPreset(Control.LayoutPreset.CenterBottom);
        panel.GrowHorizontal = Control.GrowDirection.Both;
        panel.GrowVertical = Control.GrowDirection.Begin;
        panel.Position = new Vector2(panel.Position.X, panel.Position.Y - 80);

        StyleBoxFlat styleBox = new StyleBoxFlat();
        styleBox.BgColor = new Color(0.08f, 0.45f, 0.22f, 0.92f); // Forest green success color
        styleBox.SetBorderWidthAll(1);
        styleBox.BorderColor = new Color(0.3f, 0.9f, 0.5f, 0.8f); // Light green highlight
        styleBox.CornerRadiusTopLeft = 6;
        styleBox.CornerRadiusTopRight = 6;
        styleBox.CornerRadiusBottomLeft = 6;
        styleBox.CornerRadiusBottomRight = 6;
        styleBox.ContentMarginLeft = 14;
        styleBox.ContentMarginRight = 14;
        styleBox.ContentMarginTop = 8;
        styleBox.ContentMarginBottom = 8;

        panel.AddThemeStyleboxOverride("panel", styleBox);
        notifLayer.AddChild(panel);

        Label label = new Label();
        label.Text = $"📸 Screenshot saved: res://screenshots/{fileName}";
        label.AddThemeFontSizeOverride("font_size", 14);
        panel.AddChild(label);

        // Flash on screen for 2.5 seconds, then safely dispose
        await ToSignal(GetTree().CreateTimer(2.5), SceneTreeTimer.SignalName.Timeout);
        notifLayer.QueueFree();
    }
}

