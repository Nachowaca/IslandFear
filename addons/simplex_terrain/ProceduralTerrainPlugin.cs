#if TOOLS
using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Entry point for the SimpleXTerrain Editor Plugin.
/// Handles initialization and cleanup of editor UI, inspectors, and custom terrain gizmos.
/// </summary>
[Tool]
#pragma warning disable CS0618
public partial class ProceduralTerrainPlugin : EditorPlugin
{
    [System.NonSerialized] private static TerrainGraphEditor _graphEditor;
    [System.NonSerialized] private static NodePropertyDrawer _inspectorPlugin;
    [System.NonSerialized] private TerrainGraphResource _activeGraph;
    private string _activeGraphPath;

    // Stroke state fields for 3D viewport painting
    private bool _isStrokeActive = false;
    private Vector3 _prevPaintPos = Vector3.Zero;
    private float _strokeAccumulator = 0f;
    private int _stampsApplied = 0;
    private float _targetFlattenHeight = 0f;
    [System.NonSerialized] private TerrainManager _activeManager;
    [System.NonSerialized] private Godot.Collections.Dictionary<Vector2I, Image> _beforeState;

    private void OnAssemblyUnloading(System.Runtime.Loader.AssemblyLoadContext alc)
    {
        GD.Print("[ProceduralTerrainPlugin] OnAssemblyUnloading event triggered! Cleaning up editor plugin...");
        try
        {
            var context = System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(ProceduralTerrainPlugin).Assembly);
            if (context != null)
            {
                context.Unloading -= OnAssemblyUnloading;
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] Exception in OnAssemblyUnloading -=: {ex.Message}");
        }
        CleanUpPlugin();
    }

    protected override void Dispose(bool disposing)
    {
        GD.Print($"[ProceduralTerrainPlugin] Dispose called (disposing={disposing})");
        if (disposing)
        {
            try
            {
                var context = System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(ProceduralTerrainPlugin).Assembly);
                if (context != null)
                {
                    context.Unloading -= OnAssemblyUnloading;
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[ProceduralTerrainPlugin] Exception in Dispose -=: {ex.Message}");
            }
            CleanUpPlugin();
        }
        base.Dispose(disposing);
    }

    /// <summary>
    /// Called when the plugin is enabled in the Godot Editor.
    /// Registers custom types, dock panels, and inspector plugins.
    /// </summary>
    private bool _hasSubscribedToUnloading = false;

    private void EnsureInitialized()
    {
        if (_graphEditor == null || !GodotObject.IsInstanceValid(_graphEditor) ||
            _inspectorPlugin == null || !GodotObject.IsInstanceValid(_inspectorPlugin))
        {
            GD.Print("[ProceduralTerrainPlugin] EnsureInitialized: Static fields are null or invalid. Re-initializing Editor Plugin dynamically...");
            InitializePlugin();
        }
    }

    private void InitializePlugin()
    {
        try
        {
            GD.Print("SimpleXTerrain: Initializing Editor Plugin");

            // Initialize GPU compute on the true main thread and warm the Device
            GpuTerrain.InitializeMainThread();
            _ = GpuTerrain.Device;

            // Register assembly unloading hook to ensure clean unload
            if (!_hasSubscribedToUnloading)
            {
                try
                {
                    var context = System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(ProceduralTerrainPlugin).Assembly);
                    if (context == null)
                    {
                        GD.PrintErr("[ProceduralTerrainPlugin] Failed to retrieve AssemblyLoadContext! It was null.");
                    }
                    else
                    {
                        GD.Print($"[ProceduralTerrainPlugin] Retrieved AssemblyLoadContext: {context.Name}. Subscribing to Unloading event...");
                        context.Unloading += OnAssemblyUnloading;
                        _hasSubscribedToUnloading = true;
                        GD.Print("[ProceduralTerrainPlugin] Successfully subscribed to AssemblyLoadContext.Unloading.");
                    }
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[ProceduralTerrainPlugin] Failed to register ALC Unloading event: {ex.Message}");
                }
            }

            // 1. Create and add bottom panel editor
            if (_graphEditor == null || !GodotObject.IsInstanceValid(_graphEditor))
            {
                _graphEditor = new TerrainGraphEditor(this);
                AddControlToBottomPanel(_graphEditor, "Terrain Graph");
                _graphEditor.NodeSelected += OnNodeSelected;
                _graphEditor.GraphModified += OnGraphModified;
                GD.Print("[ProceduralTerrainPlugin] Bottom panel editor initialized.");
            }

            // 2. Setup Inspector link
            if (_inspectorPlugin == null || !GodotObject.IsInstanceValid(_inspectorPlugin))
            {
                _inspectorPlugin = new NodePropertyDrawer(this, OnSaveAndRebuild);
                AddInspectorPlugin(_inspectorPlugin);
                GD.Print("[ProceduralTerrainPlugin] Inspector plugin registered.");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] Error in InitializePlugin(): {ex}");
        }
    }

    public override void _EnterTree()
    {
        InitializePlugin();
    }

    /// <summary>
    /// Called when the plugin is disabled or the editor is closed.
    /// Performs cleanup of all registered resources and UI elements.
    /// </summary>
    public override void _ExitTree()
    {
        GD.Print("SimpleXTerrain: Cleaning up Editor Plugin via _ExitTree");
        try
        {
            var context = System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(ProceduralTerrainPlugin).Assembly);
            if (context != null)
            {
                context.Unloading -= OnAssemblyUnloading;
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] Exception in _ExitTree -=: {ex.Message}");
        }
        CleanUpPlugin();
    }

    private void CleanUpPlugin()
    {
        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin() started...");
        bool isPluginValid = GodotObject.IsInstanceValid(this);
        GD.Print($"[ProceduralTerrainPlugin] CleanUpPlugin - isPluginValid (this): {isPluginValid}");
        _hasSubscribedToUnloading = false;

        // Clean up inspector plugin
        if (_inspectorPlugin != null)
        {
            GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _inspectorPlugin is NOT null. Cleaning up...");
            if (GodotObject.IsInstanceValid(_inspectorPlugin))
            {
                try
                {
                    _inspectorPlugin.CleanUp();
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _inspectorPlugin.CleanUp() completed.");
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during _inspectorPlugin.CleanUp(): {ex.Message}");
                }

                if (isPluginValid && !_inspectorPlugin.IsRemovedFromInspector)
                {
                    try
                    {
                        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Removing inspector plugin...");
                        RemoveInspectorPlugin(_inspectorPlugin);
                        _inspectorPlugin.IsRemovedFromInspector = true;
                        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Inspector plugin removed successfully.");
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during RemoveInspectorPlugin(): {ex.Message}");
                    }
                }
                else
                {
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Skipped RemoveInspectorPlugin because 'this' is invalid or plugin already removed.");
                }

                try
                {
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Disposing _inspectorPlugin...");
                    _inspectorPlugin.Dispose();
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _inspectorPlugin.Dispose() completed.");
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during _inspectorPlugin.Dispose(): {ex.Message}");
                }
            }
            else
            {
                GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _inspectorPlugin is already disposed or invalid.");
            }
            _inspectorPlugin = null;
        }

        // Clean up bottom panel editor
        if (_graphEditor != null)
        {
            GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _graphEditor is NOT null. Cleaning up...");
            if (GodotObject.IsInstanceValid(_graphEditor))
            {
                try
                {
                    _graphEditor.NodeSelected -= OnNodeSelected;
                    _graphEditor.GraphModified -= OnGraphModified;
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Disconnected _graphEditor events.");
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception disconnecting _graphEditor events: {ex.Message}");
                }

                if (isPluginValid && !_graphEditor.IsRemovedFromBottomPanel)
                {
                    try
                    {
                        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Removing control from bottom panel...");
                        RemoveControlFromBottomPanel(_graphEditor);
                        _graphEditor.IsRemovedFromBottomPanel = true;
                        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Control removed from bottom panel successfully.");
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during RemoveControlFromBottomPanel(): {ex.Message}");
                    }
                }
                else
                {
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Skipped RemoveControlFromBottomPanel because 'this' is invalid or control already removed.");
                }

                try
                {
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - Freeing _graphEditor...");
                    _graphEditor.Free();
                    GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _graphEditor.Free() completed.");
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during _graphEditor.Free(): {ex.Message}");
                }
            }
            else
            {
                GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin - _graphEditor is already disposed or invalid.");
            }
            _graphEditor = null;
        }

        _activeManager = null;
        _activeGraph = null;
        _beforeState = null;

        try
        {
            GpuTerrain.CleanUp();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] CleanUpPlugin - Exception during GpuTerrain.CleanUp(): {ex.Message}");
        }

        GD.Print("[ProceduralTerrainPlugin] CleanUpPlugin() completed.");
    }

    public override bool _Handles(GodotObject @object)
    {
        EnsureInitialized();
        return @object is TerrainGraphResource || @object is TerrainManager;
    }

    public override void _Edit(GodotObject @object)
    {
        EnsureInitialized();

        if (_graphEditor == null || !GodotObject.IsInstanceValid(_graphEditor))
        {
            GD.Print("[ProceduralTerrainPlugin] _Edit called but _graphEditor is null or invalid.");
            return;
        }

        if (@object is TerrainGraphResource graph)
        {
            _activeGraph = graph;
            _activeGraphPath = graph.ResourcePath;
            _graphEditor.LoadGraph(_activeGraph, _activeGraphPath);
            FindActiveManager();
            _graphEditor.SetActiveManager(_activeManager);
        }
        else if (@object is TerrainManager manager)
        {
            _activeManager = manager;
            _graphEditor.SetActiveManager(_activeManager);
            if (manager.Graph != null)
            {
                _activeGraph = manager.Graph;
                _activeGraphPath = manager.Graph.ResourcePath;
                _graphEditor.LoadGraph(_activeGraph, _activeGraphPath);
            }
            else
            {
                // Clear active graph if manager doesn't have one
                _activeGraph = null;
                _activeGraphPath = string.Empty;
                _graphEditor.Canvas?.ClearCanvas();
            }
        }
    }

    public override void _MakeVisible(bool visible)
    {
        EnsureInitialized();
        if (_graphEditor != null && GodotObject.IsInstanceValid(_graphEditor))
        {
            if (visible)
            {
                MakeBottomPanelItemVisible(_graphEditor);
            }
            else
            {
                HideBottomPanel();
            }
        }
    }

    private void OnNodeSelected(TerrainNodeResource nodeResource)
    {
        if (nodeResource != null)
        {
            EditorInterface.Singleton.InspectObject(nodeResource);
        }
    }

    private void OnGraphModified()
    {
        RebuildActiveTerrain();
    }

    private void OnSaveAndRebuild()
    {
        if (_graphEditor != null && GodotObject.IsInstanceValid(_graphEditor) && _graphEditor.Canvas != null)
        {
            _graphEditor.Canvas.SaveGraph();
        }
    }

    private void RebuildActiveTerrain()
    {
        if (_activeGraph == null) return;

        var root = EditorInterface.Singleton.GetEditedSceneRoot();
        if (root == null) return;

        RebuildTerrainManagersInNode(root);
    }

    private void RebuildTerrainManagersInNode(Node node)
    {
        if (node is TerrainManager manager)
        {
            if (manager.Graph == _activeGraph)
            {
                GD.Print($"[ProceduralTerrainPlugin] Rebuilding TerrainManager for graph: {manager.Graph.ResourcePath}");
                manager.RebuildTerrain();
            }
        }

        foreach (Node child in node.GetChildren())
        {
            RebuildTerrainManagersInNode(child);
        }
    }

    private void FindActiveManager()
    {
        _activeManager = null;
        var root = EditorInterface.Singleton.GetEditedSceneRoot();
        if (root == null) return;
        _activeManager = FindManagerInNode(root);
        if (_graphEditor != null && GodotObject.IsInstanceValid(_graphEditor))
        {
            _graphEditor.SetActiveManager(_activeManager);
        }
    }

    private TerrainManager FindManagerInNode(Node node)
    {
        if (node is TerrainManager manager)
        {
            if (_activeGraph == null || manager.Graph == _activeGraph)
            {
                return manager;
            }
        }

        foreach (Node child in node.GetChildren())
        {
            var found = FindManagerInNode(child);
            if (found != null) return found;
        }

        return null;
    }

    public override int _Forward3DGuiInput(Camera3D camera, InputEvent @event)
    {
        if (_graphEditor == null || !GodotObject.IsInstanceValid(_graphEditor) || !_graphEditor.PaintModeEnabled)
        {
            return (int)AfterGuiInput.Pass;
        }

        if (Input.IsMouseButtonPressed(MouseButton.Right) || Input.IsMouseButtonPressed(MouseButton.Middle))
        {
            return (int)AfterGuiInput.Pass;
        }

        if (_activeManager == null)
        {
            FindActiveManager();
        }
        if (_activeManager == null)
        {
            return (int)AfterGuiInput.Pass;
        }

        Node terrainNode = _activeManager.GetNodeOrNull(_activeManager.Terrain3DNodePath);
        if (terrainNode == null)
        {
            return (int)AfterGuiInput.Pass;
        }

        var dataVar = terrainNode.Get("data");
        if (dataVar.Obj == null)
        {
            return (int)AfterGuiInput.Pass;
        }
        GodotObject dataObject = dataVar.As<GodotObject>();

        if (@event is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left)
        {
            if (mb.Pressed)
            {
                if (GetTerrainIntersection(camera, @event, terrainNode, out Vector3 startPos))
                {
                    _isStrokeActive = true;
                    _prevPaintPos = startPos;
                    _strokeAccumulator = 0f;
                    _stampsApplied = 0;

                    _beforeState = CaptureTerrainState(dataObject);

                    if (_graphEditor.BrushType == "Flatten")
                    {
                        _targetFlattenHeight = dataObject.Call("get_height", startPos).As<float>();
                    }

                    ApplyBrushStamp(dataObject, terrainNode, startPos, _graphEditor.BrushRadius, _graphEditor.BrushStrength, _graphEditor.BrushType);
                    _stampsApplied = 1;
                    dataObject.Call("update_maps");

                    return (int)AfterGuiInput.Stop;
                }
            }
            else if (_isStrokeActive)
            {
                _isStrokeActive = false;

                var afterState = CaptureTerrainState(dataObject);

                var undoRedo = GetUndoRedo();
                if (undoRedo != null)
                {
                    undoRedo.CreateAction("Terrain Paint");
                    undoRedo.AddDoMethod(this, nameof(RestoreRegionImages), afterState);
                    undoRedo.AddUndoMethod(this, nameof(RestoreRegionImages), _beforeState);
                    undoRedo.CommitAction();
                }

                _beforeState = null;
                return (int)AfterGuiInput.Stop;
            }
        }
        else if (@event is InputEventMouseMotion mm && _isStrokeActive)
        {
            if (GetTerrainIntersection(camera, @event, terrainNode, out Vector3 currPos))
            {
                float radius = _graphEditor.BrushRadius;
                float spacing = _graphEditor.BrushSpacing;
                float dSpace = radius * spacing;

                float dx = currPos.X - _prevPaintPos.X;
                float dz = currPos.Z - _prevPaintPos.Z;
                float dSeg = Mathf.Sqrt(dx * dx + dz * dz);

                if (dSeg >= 0.0001f)
                {
                    Vector3 moveDir = (currPos - _prevPaintPos) / dSeg;
                    float L_old = _strokeAccumulator;
                    float L_new = L_old + dSeg;

                    int N_should = Mathf.FloorToInt(L_new / dSpace) + 1;
                    int N_new = N_should - _stampsApplied;

                    if (N_new > 0)
                    {
                        for (int i = 0; i < N_new; i++)
                        {
                            float d_i = i * dSpace - (L_old - _stampsApplied * dSpace);
                            Vector3 stampPos = _prevPaintPos + moveDir * d_i;
                            ApplyBrushStamp(dataObject, terrainNode, stampPos, radius, _graphEditor.BrushStrength, _graphEditor.BrushType);
                            _stampsApplied++;
                        }
                        dataObject.Call("update_maps");
                    }

                    _prevPaintPos = currPos;
                    _strokeAccumulator = L_new;
                }

                return (int)AfterGuiInput.Stop;
            }
        }

        return (int)AfterGuiInput.Pass;
    }

    private bool GetTerrainIntersection(Camera3D camera, InputEvent @event, Node terrainNode, out Vector3 intersectionPoint)
    {
        intersectionPoint = Vector3.Zero;

        Vector2 mousePos = Vector2.Zero;
        if (@event is InputEventMouse mouseEvent)
        {
            mousePos = mouseEvent.Position;
        }
        else
        {
            return false;
        }

        Vector3 cameraPos = camera.ProjectRayOrigin(mousePos);
        Vector3 cameraDir = camera.ProjectRayNormal(mousePos);

        try
        {
            var ret = terrainNode.Call("get_intersection", cameraPos, cameraDir, true);
            if (ret.VariantType == Variant.Type.Vector3)
            {
                Vector3 p = ret.As<Vector3>();
                if (p.Z <= 3.4e38f && !float.IsNaN(p.X) && !float.IsNaN(p.Y) && !float.IsNaN(p.Z))
                {
                    intersectionPoint = p;
                    return true;
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] get_intersection call failed: {ex.Message}");
        }

        try
        {
            var spaceState = camera.GetWorld3D().DirectSpaceState;
            var query = PhysicsRayQueryParameters3D.Create(cameraPos, cameraPos + cameraDir * 2000f);
            var result = spaceState.IntersectRay(query);
            if (result.Count > 0 && result.ContainsKey("position"))
            {
                intersectionPoint = (Vector3)result["position"];
                return true;
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] Physics raycast failed: {ex.Message}");
        }

        return false;
    }

    private Godot.Collections.Dictionary<Vector2I, Image> CaptureTerrainState(GodotObject dataObject)
    {
        var state = new Godot.Collections.Dictionary<Vector2I, Image>();
        try
        {
            var locations = dataObject.Call("get_region_locations").As<Godot.Collections.Array>();
            var maps = dataObject.Call("get_maps", 0).As<Godot.Collections.Array>();

            int count = Math.Min(locations.Count, maps.Count);
            for (int i = 0; i < count; i++)
            {
                Vector2I loc = locations[i].As<Vector2I>();
                Image img = maps[i].As<Image>();
                if (img != null)
                {
                    Image copy = new Image();
                    copy.CopyFrom(img);
                    state[loc] = copy;
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] CaptureTerrainState failed: {ex.Message}");
        }
        return state;
    }

    public void RestoreRegionImages(Godot.Collections.Dictionary<Vector2I, Image> state)
    {
        try
        {
            if (_activeManager == null) FindActiveManager();
            if (_activeManager == null) return;
            Node terrainNode = _activeManager.GetNodeOrNull(_activeManager.Terrain3DNodePath);
            if (terrainNode == null) return;
            var dataVar = terrainNode.Get("data");
            if (dataVar.Obj == null) return;
            GodotObject dataObject = dataVar.As<GodotObject>();

            int regionSize = terrainNode.HasMethod("get_region_size") ? terrainNode.Call("get_region_size").As<int>() : 1024;
            float vertexSpacing = terrainNode.HasMethod("get_vertex_spacing") ? terrainNode.Call("get_vertex_spacing").As<float>() : 1.0f;
            float regionWorldSize = regionSize * vertexSpacing;

            foreach (var kvp in state)
            {
                Vector2I loc = kvp.Key;
                Image img = kvp.Value;

                var imagesArray = new Godot.Collections.Array();
                imagesArray.Resize(3);
                imagesArray[0] = img;
                imagesArray[1] = new Variant();
                imagesArray[2] = new Variant();

                Vector3 globalPos = new Vector3(loc.X * regionWorldSize, 0, loc.Y * regionWorldSize);
                dataObject.Call("import_images", imagesArray, globalPos, 0.0f, 1.0f);
            }

            dataObject.Call("update_maps");
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] RestoreRegionImages failed: {ex.Message}");
        }
    }

    private void ApplyBrushStamp(GodotObject dataObject, Node terrainNode, Vector3 center, float radius, float strength, string brushType)
    {
        try
        {
            float vertexSpacing = terrainNode.HasMethod("get_vertex_spacing") ? terrainNode.Call("get_vertex_spacing").As<float>() : 1.0f;
            float step = Math.Max(0.1f, vertexSpacing);

            float minX = Mathf.Floor(center.X - radius);
            float maxX = Mathf.Ceil(center.X + radius);
            float minZ = Mathf.Floor(center.Z - radius);
            float maxZ = Mathf.Ceil(center.Z + radius);

            for (float z = minZ; z <= maxZ; z += step)
            {
                for (float x = minX; x <= maxX; x += step)
                {
                    float dx = x - center.X;
                    float dz = z - center.Z;
                    float dist = Mathf.Sqrt(dx * dx + dz * dz);
                    if (dist > radius) continue;

                    float t = dist / radius;
                    float falloff = 1.0f - 3.0f * t * t + 2.0f * t * t * t;

                    Vector3 samplePos = new Vector3(x, 0f, z);
                    float currentHeight = dataObject.Call("get_height", samplePos).As<float>();
                    float newHeight = currentHeight;

                    if (brushType == "Raise")
                    {
                        newHeight = currentHeight + strength * falloff;
                    }
                    else if (brushType == "Lower")
                    {
                        newHeight = currentHeight - strength * falloff;
                    }
                    else if (brushType == "Flatten")
                    {
                        newHeight = Mathf.Lerp(currentHeight, _targetFlattenHeight, strength * falloff);
                    }
                    else if (brushType == "Smooth")
                    {
                        float sum = 0f;
                        int count = 0;
                        for (int nz = -1; nz <= 1; nz++)
                        {
                            for (int nx = -1; nx <= 1; nx++)
                            {
                                Vector3 neighborPos = new Vector3(x + nx * step, 0f, z + nz * step);
                                sum += dataObject.Call("get_height", neighborPos).As<float>();
                                count++;
                            }
                        }
                        float neighborhoodAverage = sum / count;
                        newHeight = Mathf.Lerp(currentHeight, neighborhoodAverage, strength * falloff);
                    }

                    dataObject.Call("set_height", samplePos, newHeight);
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[ProceduralTerrainPlugin] ApplyBrushStamp failed: {ex.Message}");
        }
    }
}
#pragma warning restore CS0618
#endif
