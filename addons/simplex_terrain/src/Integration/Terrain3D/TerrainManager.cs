using Godot;
using System;
using System.Collections.Generic;
using System.Buffers;
using System.Runtime.InteropServices;

namespace SimpleXTerrain;

/// <summary>
/// Main addon runtime class that automatically manages chunk lifecycles based on Manhattan camera view distance,
/// dispatches background generation to the worker pool, and integrates results into the Terrain3D node.
/// </summary>
[GlobalClass]
[Tool]
public partial class TerrainManager : Node3D
{
    private readonly object _schedulerLock = new();
    private TerrainScheduler _scheduler;
    private TerrainNode _graphRoot;
    private TerrainNode _controlGraphRoot;
    private TerrainNode _instancerGraphRoot;
    private readonly List<TerrainNode> _allGraphNodes = new();
    private readonly Dictionary<ChunkCoordinate, HeightMatrix> _loadedChunks = new();
    private readonly Dictionary<ChunkCoordinate, int> _loadedResolutions = new();
    private readonly HashSet<ChunkCoordinate> _draftCoords = new();
    private bool _didUploadThisFrame = false;
    private float[] _uploadFloatBuffer;
    private readonly HashSet<ChunkCoordinate> _chunksToLoadSet = new();
    private readonly HashSet<ChunkCoordinate> _weldModifiedCoords = new();
    private readonly HashSet<ChunkCoordinate> _pendingReUploads = new();
    private GodotObject _cachedTerrainData;
    private Node _cachedTerrainNode;
    private bool _hasPreCachedSplines = false;
    private double _splineUpdateTimer = 0.0;
    private Dictionary<string, int> _textureNameToIdMap = null;
    private float _cachedActiveHeightScale = 500.0f;

    private GodotObject GetTerrainData()
    {
        Node tn = GetNodeOrNull(Terrain3DNodePath);
        if (tn != _cachedTerrainNode)
        {
            _cachedTerrainNode = tn;
            _cachedTerrainData = tn?.Get("data").As<GodotObject>();
            if (_cachedTerrainData != null)
            {
                try
                {
                    Vector2 hr = new Vector2(-3000f, 3000f);
                    _cachedTerrainData.Set("height_range", hr);
                    GD.Print($"[TerrainManager] Dynamically set Terrain3D height_range to {hr} to support towering mountain ranges.");
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[TerrainManager] Failed to set height_range on Terrain3D storage: {ex.Message}");
                }
            }
        }
        return _cachedTerrainData;
    }

    /// <summary>
    /// Gets the set of manually pinned/locked chunk coordinates.
    /// </summary>
    public HashSet<ChunkCoordinate> PinnedChunks { get; } = new HashSet<ChunkCoordinate>();

    /// <summary>
    /// Gets the set of manually bypassed/disabled chunk coordinates.
    /// </summary>
    public HashSet<ChunkCoordinate> BypassedChunks { get; } = new HashSet<ChunkCoordinate>();

    private int _prevCamChunkX = int.MinValue;
    private int _prevCamChunkZ = int.MinValue;
    private float _cameraStillTimer = 0f;
    private const float REFINE_AFTER_SECONDS = 2.0f;
    private int _loadRadius = 3;
    private int _unloadRadius = 5;

    /// <summary>
    /// Gets or sets the serialized graph resource defining the procedural generation rules.
    /// </summary>
    [Export]
    public TerrainGraphResource Graph { get; set; }

    /// <summary>
    /// Gets or sets the path to the Terrain3D node in the scene tree.
    /// </summary>
    [Export]
    public NodePath Terrain3DNodePath { get; set; } = new NodePath("");

    /// <summary>
    /// Gets or sets the target Camera3D node to follow. If empty, follows the active viewport camera.
    /// </summary>
    [Export]
    public NodePath CameraNodePath { get; set; } = new NodePath("");

    public enum ChunkLoadShape
    {
        Circle,
        Rhombus,
        Square
    }

    private ChunkLoadShape _loadShape = ChunkLoadShape.Circle;

    /// <summary>
    /// Gets or sets the chunk loading pattern shape.
    /// </summary>
    [Export]
    public ChunkLoadShape LoadShape
    {
        get => _loadShape;
        set
        {
            _loadShape = value;
            // Force recalculation in _Process
            _prevCamChunkX = int.MinValue;
            _prevCamChunkZ = int.MinValue;
        }
    }

    /// <summary>
    /// Gets or sets the loading radius in chunk units.
    /// </summary>
    [Export]
    public int LoadRadius
    {
        get => _loadRadius;
        set
        {
            _loadRadius = value;
            if (_unloadRadius <= _loadRadius)
            {
                _unloadRadius = _loadRadius + 2;
            }
        }
    }

    /// <summary>
    /// Gets or sets the unloading radius in chunk units.
    /// </summary>
    [Export]
    public int UnloadRadius
    {
        get => _unloadRadius;
        set => _unloadRadius = Math.Max(value, _loadRadius + 1);
    }

    /// <summary>
    /// Gets or sets the Manhattan view distance in chunk units (for backward compatibility).
    /// </summary>
    [Export]
    public int ViewDistance
    {
        get => LoadRadius;
        set => LoadRadius = value;
    }

    /// <summary>
    /// Gets or sets the grid resolution of each generated chunk (e.g. 512).
    /// </summary>
    [Export]
    public int ChunkResolution { get; set; } = 512;

    /// <summary>
    /// Gets or sets the border padding of each chunk for boundary-aware computations (e.g. 32).
    /// </summary>
    [Export]
    public int ChunkPadding { get; set; } = 32;

    /// <summary>
    /// Gets or sets the physical size of each chunk in world meters.
    /// </summary>
    [Export]
    public float ChunkWorldSize { get; set; } = 512.0f;

    /// <summary>
    /// Gets or sets the height scaling factor applied during float image formatting.
    /// </summary>
    [Export]
    public float HeightScale { get; set; } = 500.0f;

    /// <summary>
    /// Gets or sets the margin in pixels over which boundary welding is propagated.
    /// </summary>
    [Export]
    public int WeldMargin { get; set; } = 10;

    /// <summary>
    /// Gets or sets whether to use the minimum height on mismatched boundaries to prevent popping.
    /// </summary>
    [Export]
    public bool WeldLowerOnMismatch { get; set; } = false;

    /// <summary>
    /// Gets or sets whether to schedule low-resolution draft chunks first for rapid previewing.
    /// </summary>
    [Export]
    public bool EnableDraftPass { get; set; } = false;

    /// <summary>
    /// Gets or sets whether to spawn blue water plane meshes and river meshes in the scene.
    /// </summary>
    [Export]
    public bool SpawnWaterMeshes { get; set; } = false;


    /// <summary>
    /// Force rebuilds the generation DAG from the serialized Graph resource and clears
    /// all cached chunks to trigger complete viewport regeneration.
    /// </summary>
    public void RebuildTerrain()
    {
        if (Graph == null) return;

        lock (_schedulerLock)
        {
            if (_scheduler == null)
            {
                _scheduler = new TerrainScheduler();
            }
            else
            {
                _scheduler.ScheduledCoords.Clear();
            }
        }

        try
        {
            // Instantiate all runtime nodes in the graph to find all output terminals
            var runtimeNodes = GraphEvaluator.InstantiateGraphNodes(Graph);
            _allGraphNodes.Clear();
            _allGraphNodes.AddRange(runtimeNodes.Values);

            _graphRoot = null;
            _controlGraphRoot = null;
            _instancerGraphRoot = null;

            foreach (var node in _allGraphNodes)
            {
                if (node is HeightOutputNode)
                {
                    _graphRoot = node;
                }
                else if (node is Terrain3DControlOutputNode)
                {
                    _controlGraphRoot = node;
                }
                else if (node is Terrain3DInstancerOutputNode)
                {
                    _instancerGraphRoot = node;
                }
            }

            // Fallback for _graphRoot
            if (_graphRoot == null)
            {
                _graphRoot = GraphEvaluator.InstantiateGraph(Graph);
            }

            // Reset cached texture mapping and cache active height scale
            _textureNameToIdMap = null;
            _cachedActiveHeightScale = HeightScale;
            if (_graphRoot != null && _graphRoot.GetType().Name == "HeightOutputNode")
            {
                var prop = _graphRoot.GetType().GetProperty("AssociatedResource");
                if (prop != null)
                {
                    var res = prop.GetValue(_graphRoot);
                    if (res != null)
                    {
                        var scaleProp = res.GetType().GetProperty("HeightScale");
                        if (scaleProp != null)
                        {
                            _cachedActiveHeightScale = (float)scaleProp.GetValue(res);
                        }
                    }
                }
            }

            // Clear water meshes
            ClearWaterMeshes();

            // Dispose of all cached height matrices to recycle float arrays
            foreach (var hm in _loadedChunks.Values)
            {
                hm?.Dispose();
            }
            _loadedChunks.Clear();
            _loadedResolutions.Clear();
            _draftCoords.Clear();

            // Force recalculation in _Process
            _prevCamChunkX = int.MinValue;
            _prevCamChunkZ = int.MinValue;

            // Compile river meshes
            if (SpawnWaterMeshes)
            {
                CompileRiverMeshes();
            }

            // Pre-cache all SplineInputNode splines on the main thread
            int nodeCount = _allGraphNodes.Count;
            for (int i = 0; i < nodeCount; i++)
            {
                if (_allGraphNodes[i] is SplineInputNode splineNode)
                {
                    splineNode.LoadAndCacheSpline();
                }
            }
            _hasPreCachedSplines = true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Rebuild failed: {ex.Message}");
        }
    }

    private void SetupTerrain3DAssets()
    {
        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
        if (terrainNode == null)
        {
            return;
        }

        var assetsVar = terrainNode.Get("assets");
        GodotObject assets = assetsVar.As<GodotObject>();
        if (assets == null)
        {
            assets = ClassDB.Instantiate("Terrain3DAssets").As<GodotObject>();
            terrainNode.Set("assets", assets);
        }
        else
        {
            // Assets are already configured in the editor (e.g., terrain_assets.tres). Do not overwrite!
            GD.Print("[TerrainManager] Custom Terrain3D Assets detected in scene. Bypassing programmatic texture setup.");
            return;
        }

        try
        {
            var textureListVar = assets.Get("texture_list");
            var textureList = textureListVar.AsGodotArray();
            if (textureList.Count > 0)
            {
                return;
            }
        }
        catch
        {
            // Proceed to assign if getting list count fails
        }

        GD.Print("[TerrainManager] Setting up default Terrain3D textures programmatically...");
        
        try
        {
            // Grass texture (slot 0) 
            var tex0 = ClassDB.Instantiate("Terrain3DTextureAsset").As<GodotObject>();
            tex0.Set("name", "Grass");
            tex0.Set("albedo_color", new Color(0.25f, 0.55f, 0.2f));
            assets.Call("set_texture", 0, tex0);

            // Rock texture (slot 1)
            var tex1 = ClassDB.Instantiate("Terrain3DTextureAsset").As<GodotObject>();
            tex1.Set("name", "Rock");
            tex1.Set("albedo_color", new Color(0.45f, 0.4f, 0.35f));
            assets.Call("set_texture", 1, tex1);
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Failed to programmatically configure default textures: {ex.Message}");
        }
    }

    /// <summary>
    /// Called when the node exits the scene tree or the assembly is reloading.
    /// Crucial for stopping background tasks so the C# domain can unload cleanly.
    /// </summary>
    /// <summary>
    public override void _ExitTree()
    {
        GD.Print("[TerrainManager] _ExitTree called");
        base._ExitTree();

        // Disable processing to prevent delegate_handle == nullptr spam during assembly reload
        SetProcess(false);
        SetPhysicsProcess(false);
        SetProcessInput(false);
        SetProcessShortcutInput(false);
        SetProcessUnhandledInput(false);
        SetProcessUnhandledKeyInput(false);

        try
        {
            System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(TerrainManager).Assembly).Unloading -= OnAssemblyUnloading;
        }
        catch { }
        lock (_schedulerLock)
        {
            if (_scheduler != null)
            {
                _scheduler.CancelAll();
                _scheduler.Dispose();
                _scheduler = null;
            }
        }
        _graphRoot = null;
        _loadedChunks.Clear();
        _loadedResolutions.Clear();
        _draftCoords.Clear();
        _cachedTerrainData = null;
        _cachedTerrainNode = null;

        try
        {
            GpuTerrain.CleanUp();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Failed to clean up GPU resources on exit: {ex.Message}");
        }
    }

    protected override void Dispose(bool disposing)
    {
        GD.Print($"[TerrainManager] Dispose called (disposing={disposing})");
        if (disposing)
        {
            try
            {
                System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(TerrainManager).Assembly).Unloading -= OnAssemblyUnloading;
            }
            catch { }
            lock (_schedulerLock)
            {
                if (_scheduler != null)
                {
                    _scheduler.CancelAll();
                    _scheduler.Dispose();
                    _scheduler = null;
                }
            }
            _graphRoot = null;
            _loadedChunks.Clear();
            _loadedResolutions.Clear();
            _draftCoords.Clear();
            _cachedTerrainData = null;
            _cachedTerrainNode = null;

            try
            {
                GpuTerrain.CleanUp();
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[TerrainManager] Failed to clean up GPU resources on dispose: {ex.Message}");
            }
        }
        base.Dispose(disposing);
    }

    private void OnAssemblyUnloading(System.Runtime.Loader.AssemblyLoadContext alc)
    {
        GD.Print("[TerrainManager] Assembly unloading detected! Cancelling all scheduler threads immediately.");
        
        try
        {
            System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(TerrainManager).Assembly).Unloading -= OnAssemblyUnloading;
        }
        catch { }

        // Disable processing to prevent delegate_handle == nullptr spam during assembly reload
        SetProcess(false);
        SetPhysicsProcess(false);
        SetProcessInput(false);
        SetProcessShortcutInput(false);
        SetProcessUnhandledInput(false);
        SetProcessUnhandledKeyInput(false);

        lock (_schedulerLock)
        {
            if (_scheduler != null)
            {
                _scheduler.CancelAll();
                _scheduler.Dispose();
                _scheduler = null;
            }
        }
        _graphRoot = null;
        _loadedChunks.Clear();
        _loadedResolutions.Clear();
        _draftCoords.Clear();
        _cachedTerrainData = null;
        _cachedTerrainNode = null;

        try
        {
            GpuTerrain.CleanUp();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Failed to clean up GPU resources on assembly unload: {ex.Message}");
        }
    }

    /// <summary>
    /// Called when the node enters the scene tree.
    /// </summary>
    public override void _Ready()
    {
        GD.Print("[TerrainManager] Initializing runtime addon manager...");

        // Initialize GPU compute on the true main thread and warm the Device
        GpuTerrain.InitializeMainThread();
        _ = GpuTerrain.Device;

        try
        {
            System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(typeof(TerrainManager).Assembly).Unloading += OnAssemblyUnloading;
        }
        catch { }

        SetupTerrain3DAssets();

        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
        if (terrainNode != null)
        {
            var dataVar = terrainNode.Get("data");
            if (dataVar.Obj != null)
            {
                GodotObject dataObject = dataVar.As<GodotObject>();
                if (dataObject != null)
                {
                    try
                    {
                        Vector2 hr = new Vector2(-3000f, 3000f);
                        dataObject.Set("height_range", hr);
                        GD.Print($"[TerrainManager] _Ready: Dynamically set Terrain3D height_range to {hr}");
                    }
                    catch { }

                    try
                    {
                        var regionsVar = dataObject.Call("get_regions_active");
                        if (regionsVar.VariantType != Variant.Type.Nil)
                        {
                            var regions = regionsVar.AsGodotArray();
                            foreach (var regionVar in regions)
                            {
                                var region = regionVar.As<GodotObject>();
                                if (region != null)
                                {
                                    dataObject.Call("remove_region", region, false);
                                }
                            }
                            dataObject.Call("update_maps");
                            GD.Print("[TerrainManager] Cleared Terrain3D active regions on startup to ensure dynamic streaming.");
                        }
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[TerrainManager] Failed to clear Terrain3D active regions: {ex.Message}");
                    }
                }
            }
        }

        if (Graph == null)
        {
            if (!Engine.IsEditorHint())
            {
                GD.Print("[TerrainManager] Graph property is currently null. Waiting for programmatic assignment at runtime.");
            }
            return;
        }

        try
        {
            // 1. Instantiate ALL runtime nodes to find all output terminals
            //    (mirrors RebuildTerrain logic so ClearNodeCachesForChunk works)
            var runtimeNodes = GraphEvaluator.InstantiateGraphNodes(Graph);
            _allGraphNodes.Clear();
            _allGraphNodes.AddRange(runtimeNodes.Values);

            _graphRoot = null;
            _controlGraphRoot = null;
            _instancerGraphRoot = null;

            foreach (var node in _allGraphNodes)
            {
                if (node is HeightOutputNode)
                {
                    _graphRoot = node;
                }
                else if (node is Terrain3DControlOutputNode)
                {
                    _controlGraphRoot = node;
                }
                else if (node is Terrain3DInstancerOutputNode)
                {
                    _instancerGraphRoot = node;
                }
            }

            // Fallback for _graphRoot
            if (_graphRoot == null)
            {
                _graphRoot = GraphEvaluator.InstantiateGraph(Graph);
            }

            // Cache active height scale
            _cachedActiveHeightScale = HeightScale;
            if (_graphRoot != null && _graphRoot.GetType().Name == "HeightOutputNode")
            {
                var prop = _graphRoot.GetType().GetProperty("AssociatedResource");
                if (prop != null)
                {
                    var res = prop.GetValue(_graphRoot);
                    if (res != null)
                    {
                        var scaleProp = res.GetType().GetProperty("HeightScale");
                        if (scaleProp != null)
                        {
                            _cachedActiveHeightScale = (float)scaleProp.GetValue(res);
                        }
                    }
                }
            }

            GD.Print($"[TerrainManager] Procedural terrain graph instantiated. Nodes={_allGraphNodes.Count}, Height={_graphRoot != null}, Control={_controlGraphRoot != null}, Instancer={_instancerGraphRoot != null}");

            // 2. Initialize the background task scheduler
            _scheduler = new TerrainScheduler();

            // Reset camera chunk cache
            _prevCamChunkX = int.MinValue;
            _prevCamChunkZ = int.MinValue;

            // Compile river meshes
            if (SpawnWaterMeshes)
            {
                CompileRiverMeshes();
            }

            // Pre-cache all SplineInputNode splines on the main thread at startup
            int nodeCount = _allGraphNodes.Count;
            for (int i = 0; i < nodeCount; i++)
            {
                if (_allGraphNodes[i] is SplineInputNode splineNode)
                {
                    splineNode.LoadAndCacheSpline();
                }
            }
            _hasPreCachedSplines = true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Exception during initialization: {ex.Message}");
            GD.PrintErr(ex.StackTrace);
        }
    }

    /// <summary>
    /// Called every frame. Drives chunk scheduling, completion queue polling, and region loading/unloading.
    /// </summary>
    public override void _Process(double delta)
    {
        if (_scheduler == null || _graphRoot == null)
        {
            return;
        }

        // Pre-cache all SplineInputNode splines on the main thread
        bool shouldUpdateSplines = false;
        if (!Engine.IsEditorHint())
        {
            if (!_hasPreCachedSplines)
            {
                shouldUpdateSplines = true;
                _hasPreCachedSplines = true;
            }
        }
        else
        {
            _splineUpdateTimer += delta;
            if (_splineUpdateTimer >= 0.2) // Check 5 times per second in the editor
            {
                _splineUpdateTimer = 0.0;
                shouldUpdateSplines = true;
            }
        }

        if (shouldUpdateSplines)
        {
            int nodeCount = _allGraphNodes.Count;
            for (int i = 0; i < nodeCount; i++)
            {
                if (_allGraphNodes[i] is SplineInputNode splineNode)
                {
                    splineNode.LoadAndCacheSpline();
                }
            }
        }

        // 1. Locate the active Camera3D node to follow
        Camera3D camera = GetActiveCamera();
        if (camera == null)
        {
            return; // Wait until camera is active
        }

        // 2. Calculate the camera's current chunk coordinate and forward direction
        Vector3 camPos = camera.GlobalPosition;
        Vector3 camForward = -camera.GlobalTransform.Basis.Z;
        int camChunkX = Mathf.FloorToInt(camPos.X / ChunkWorldSize);
        int camChunkZ = Mathf.FloorToInt(camPos.Z / ChunkWorldSize);

        // 3. Track camera movement and schedule chunks dynamically
        bool cameraMoved = (camChunkX != _prevCamChunkX || camChunkZ != _prevCamChunkZ);
        if (cameraMoved)
        {
            _prevCamChunkX = camChunkX;
            _prevCamChunkZ = camChunkZ;
            _cameraStillTimer = 0f;

            UpdateChunkStates(camChunkX, camChunkZ, camPos, camForward);
        }
        else
        {
            _cameraStillTimer += (float)delta;

            // Periodically check/schedule more chunks if scheduler has free capacity
            if (_scheduler.ActiveTaskCount < 4)
            {
                UpdateChunkStates(camChunkX, camChunkZ, camPos, camForward);
            }

            // Progressive Refinement when camera is still
            if (_cameraStillTimer > REFINE_AFTER_SECONDS && _scheduler.ActiveTaskCount < 4)
            {
                ScheduleRefinement(camChunkX, camChunkZ, camPos, camForward);
            }
        }

        // 4. Drain the completed queue and upload heightmaps to Terrain3D every frame
        DrainCompletedQueue(camChunkX, camChunkZ, camPos, camForward);
    }

    private int GetResolutionForDistance(ChunkCoordinate coord, int camChunkX, int camChunkZ)
    {
        if (PinnedChunks.Contains(coord))
        {
            return ChunkResolution;
        }
        int dx = Math.Abs(coord.X - camChunkX);
        int dz = Math.Abs(coord.Z - camChunkZ);
        int dist = Math.Max(dx, dz);  // Chebyshev distance

        if (dist <= 1) return ChunkResolution;        // 512
        if (dist <= 4) return ChunkResolution / 2;    // 256
        return ChunkResolution / 4;                    // 128
    }

    private Dictionary<string, int> GetTextureNameToIdMap()
    {
        if (_textureNameToIdMap != null)
        {
            return _textureNameToIdMap;
        }

        var map = new Dictionary<string, int>();
        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
        if (terrainNode == null)
        {
            return map;
        }

        var assetsVar = terrainNode.Get("assets");
        GodotObject assets = assetsVar.As<GodotObject>();
        if (assets == null)
        {
            return map;
        }

        try
        {
            var textureListVar = assets.Get("texture_list");
            var textureList = textureListVar.AsGodotArray();
            int count = textureList.Count;
            for (int i = 0; i < count; i++)
            {
                var texAsset = textureList[i].As<GodotObject>();
                if (texAsset != null)
                {
                    string name = texAsset.Get("name").As<string>();
                    int id = texAsset.Get("id").As<int>();
                    if (!string.IsNullOrEmpty(name))
                    {
                        map[name] = id;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainManager] Failed to build TextureNameToIdMap: {ex.Message}");
        }

        _textureNameToIdMap = map;
        return _textureNameToIdMap;
    }

    private void ScheduleRefinement(int camChunkX, int camChunkZ, Vector3 camPos, Vector3 camForward)
    {
        var chunksToLoad = GetChunksInLoadRange(camChunkX, camChunkZ);
        var sorted = new List<ChunkCoordinate>(chunksToLoad);
        sorted.Sort((a, b) => {
            int da = (a.X - camChunkX) * (a.X - camChunkX) + (a.Z - camChunkZ) * (a.Z - camChunkZ);
            int db = (b.X - camChunkX) * (b.X - camChunkX) + (b.Z - camChunkZ) * (b.Z - camChunkZ);
            return da.CompareTo(db);
        });

        var textureMap = GetTextureNameToIdMap();

        foreach (var coord in sorted)
        {
            if (BypassedChunks.Contains(coord)) continue;

            bool isLoaded = _loadedChunks.ContainsKey(coord);
            int targetRes = GetResolutionForDistance(coord, camChunkX, camChunkZ);
            if (isLoaded && _loadedResolutions.TryGetValue(coord, out int currentRes) && currentRes < targetRes)
            {
                bool isScheduled;
                lock (_schedulerLock)
                {
                    isScheduled = _scheduler.ScheduledCoords.Contains(coord);
                }

                if (!isScheduled)
                {
                    Vector3 worldOrigin = new Vector3(coord.X * ChunkWorldSize, 0, coord.Z * ChunkWorldSize);
                    bool isHighPriority = IsChunkHighPriority(coord, camPos, camForward);

                    int nextRes = currentRes * 2;
                    if (nextRes > targetRes) nextRes = targetRes;

                    ClearNodeCachesForChunk(coord);

                    // GD.Print($"[TerrainManager] Refining chunk {coord} from res={currentRes} to res={nextRes}");
                    _scheduler.Schedule(
                        coord,
                        _graphRoot,
                        _controlGraphRoot,
                        _instancerGraphRoot,
                        highPriority: isHighPriority,
                        resolution: nextRes,
                        padding: ChunkPadding,
                        worldOrigin: worldOrigin,
                        worldSize: ChunkWorldSize,
                        heightScale: GetActiveHeightScale(),
                        textureNameToIdMap: textureMap
                    );
                    break; // Refine only one chunk per frame/check to be ultra smooth
                }
            }
        }
    }

    private void UpdateChunkStates(int camChunkX, int camChunkZ, Vector3 camPos, Vector3 camForward)
    {
        // Evict out-of-range chunks first
        EvictOutOfUnloadRangeChunks(camChunkX, camChunkZ);

        // Collect all chunk coordinates within the LoadRadius
        var chunksSet = GetChunksInLoadRange(camChunkX, camChunkZ);
        foreach (var pinned in PinnedChunks)
        {
            chunksSet.Add(pinned);
        }
        chunksSet.ExceptWith(BypassedChunks);

        // Sort chunks to load in a spiral (closest first)
        var sortedChunks = new List<ChunkCoordinate>(chunksSet);
        sortedChunks.Sort((a, b) => {
            int da = (a.X - camChunkX) * (a.X - camChunkX) + (a.Z - camChunkZ) * (a.Z - camChunkZ);
            int db = (b.X - camChunkX) * (b.X - camChunkX) + (b.Z - camChunkZ) * (b.Z - camChunkZ);
            return da.CompareTo(db);
        });

        var textureMap = GetTextureNameToIdMap();

        // Schedule new coordinates for background generation based on Chebyshev LOD distance
        foreach (var coord in sortedChunks)
        {
            bool isLoaded = _loadedChunks.ContainsKey(coord);
            int targetRes = GetResolutionForDistance(coord, camChunkX, camChunkZ);

            bool needsUpgrade = isLoaded && _loadedResolutions.TryGetValue(coord, out int currentRes) && currentRes < targetRes;
            bool isScheduled;

            lock (_schedulerLock)
            {
                isScheduled = _scheduler.ScheduledCoords.Contains(coord);
            }

            if ((!isLoaded || needsUpgrade) && !isScheduled)
            {
                Vector3 worldOrigin = new Vector3(coord.X * ChunkWorldSize, 0, coord.Z * ChunkWorldSize);
                bool isHighPriority = IsChunkHighPriority(coord, camPos, camForward);

                // If scheduler is at max capacity, stop scheduling for now.
                // It will try to schedule remaining in subsequent frames.
                lock (_schedulerLock)
                {
                    if (_scheduler.ActiveTaskCount >= 4)
                    {
                        break;
                    }
                }

                ClearNodeCachesForChunk(coord);

                _scheduler.Schedule(
                    coord,
                    _graphRoot,
                    _controlGraphRoot,
                    _instancerGraphRoot,
                    highPriority: isHighPriority,
                    resolution: targetRes,
                    padding: ChunkPadding,
                    worldOrigin: worldOrigin,
                    worldSize: ChunkWorldSize,
                    heightScale: GetActiveHeightScale(),
                    textureNameToIdMap: textureMap
                );
            }
        }
    }

    /// <summary>
    /// Helper to find the active Camera3D node.
    /// </summary>
    private Camera3D GetActiveCamera()
    {
        Camera3D camera = null;
        if (CameraNodePath != null && !CameraNodePath.IsEmpty)
        {
            camera = GetNodeOrNull<Camera3D>(CameraNodePath);
        }
        if (camera == null)
        {
            camera = GetViewport().GetCamera3D();
        }
        return camera;
    }

    /// <summary>
    /// Computes the active chunk coordinates around the camera within LoadRadius using the configured LoadShape.
    /// </summary>
    private HashSet<ChunkCoordinate> GetChunksInLoadRange(int centerX, int centerZ)
    {
        _chunksToLoadSet.Clear();

        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
        float regionScale = 256.0f; // Default fallback
        if (terrainNode != null)
        {
            float regSize = 1024.0f;
            if (terrainNode.HasMethod("get_region_size"))
            {
                regSize = terrainNode.Call("get_region_size").As<float>();
            }
            float spacing = 1.0f;
            if (terrainNode.HasMethod("get_vertex_spacing"))
            {
                spacing = terrainNode.Call("get_vertex_spacing").As<float>();
            }
            regionScale = regSize * spacing;
        }

        for (int dx = -LoadRadius; dx <= LoadRadius; dx++)
        {
            for (int dz = -LoadRadius; dz <= LoadRadius; dz++)
            {
                bool inRange = false;
                switch (_loadShape)
                {
                    case ChunkLoadShape.Square:
                        inRange = Math.Abs(dx) <= LoadRadius && Math.Abs(dz) <= LoadRadius;
                        break;
                    case ChunkLoadShape.Rhombus:
                        inRange = Math.Abs(dx) + Math.Abs(dz) <= LoadRadius;
                        break;
                    case ChunkLoadShape.Circle:
                        inRange = (dx * dx) + (dz * dz) <= LoadRadius * LoadRadius;
                        break;
                }

                if (inRange)
                {
                    ChunkCoordinate coord = new ChunkCoordinate(centerX + dx, centerZ + dz);
                    Vector3 globalPos = new Vector3(coord.X * ChunkWorldSize, 0, coord.Z * ChunkWorldSize);
                    int rx = Mathf.FloorToInt(globalPos.X / regionScale);
                    int rz = Mathf.FloorToInt(globalPos.Z / regionScale);
                    
                    // Terrain3D's supported region map size bounds go from -16 to 15
                    if (rx >= -16 && rx <= 15 && rz >= -16 && rz <= 15)
                    {
                        _chunksToLoadSet.Add(coord);
                    }
                }
            }
        }
        return _chunksToLoadSet;
    }

    /// <summary>
    /// Checks if a chunk coordinate is outside the unload radius from the camera using the configured LoadShape metric.
    /// </summary>
    private bool IsCoordOutsideUnloadRange(ChunkCoordinate coord, int centerX, int centerZ)
    {
        int unloadRad = Math.Max(UnloadRadius, LoadRadius + 1);
        int dx = coord.X - centerX;
        int dz = coord.Z - centerZ;

        switch (_loadShape)
        {
            case ChunkLoadShape.Square:
                return Math.Abs(dx) > unloadRad || Math.Abs(dz) > unloadRad;
            case ChunkLoadShape.Rhombus:
                return Math.Abs(dx) + Math.Abs(dz) > unloadRad;
            case ChunkLoadShape.Circle:
                return (dx * dx) + (dz * dz) > unloadRad * unloadRad;
            default:
                return (Math.Abs(dx) + Math.Abs(dz)) > unloadRad;
        }
    }

    /// <summary>
    /// Determines whether a chunk is high priority based on its distance to the camera and camera view cone.
    /// </summary>
    private bool IsChunkHighPriority(ChunkCoordinate coord, Vector3 camPos, Vector3 camForward)
    {
        // 1. Calculate chunk center in world space (projected onto camera Y plane for 2D distance)
        Vector3 chunkCenter = new Vector3(
            (coord.X + 0.5f) * ChunkWorldSize,
            camPos.Y,
            (coord.Z + 0.5f) * ChunkWorldSize
        );

        // 2. Safe range: within 1.5 chunks around player is always high priority (prevents falling/collision bugs)
        float distToChunk = camPos.DistanceTo(chunkCenter);
        if (distToChunk <= ChunkWorldSize * 1.5f)
        {
            return true;
        }

        // 3. View-cone check: is the chunk in front of the camera (cone of ~145 degrees)
        Vector3 dirToChunk = (chunkCenter - camPos).Normalized();
        float dot = camForward.Dot(dirToChunk);

        return dot > 0.3f;
    }

    /// <summary>
    /// Dequeues finished background results and pushes them to the active Terrain3D instance.
    /// </summary>
    private void DrainCompletedQueue(int camChunkX, int camChunkZ, Vector3 camPos, Vector3 camForward)
    {
        GodotObject dataObject = GetTerrainData();
        if (dataObject == null)
        {
            return;
        }

        int maxUploadsPerFrame = 1;
        int uploaded = 0;

        while (uploaded < maxUploadsPerFrame && _scheduler.CompletedQueue.TryDequeue(out ChunkPayload payload))
        {
            // Remove from scheduled tracking
            lock (_schedulerLock)
            {
                _scheduler.ScheduledCoords.Remove(payload.Coord);
            }

            // Evict if it's bypassed or outside the unload range (and not pinned)
            bool shouldEvict = BypassedChunks.Contains(payload.Coord) ||
                               (!PinnedChunks.Contains(payload.Coord) && IsCoordOutsideUnloadRange(payload.Coord, camChunkX, camChunkZ));
            if (shouldEvict)
            {
                payload.Heights?.Dispose();
                payload.ControlMap?.Dispose();
                _draftCoords.Remove(payload.Coord);
                continue;
            }

            if (payload.Heights == null)
            {
                payload.ControlMap?.Dispose();
                _draftCoords.Remove(payload.Coord);
                continue;
            }

            int W = payload.Heights.Width;

            // Check if we already have a higher or equal resolution chunk loaded
            if (_loadedResolutions.TryGetValue(payload.Coord, out int loadedRes) && loadedRes >= W)
            {
                // Discard incoming low-res draft/outdated chunk
                payload.Heights.Dispose();
                payload.ControlMap?.Dispose();
                _draftCoords.Remove(payload.Coord);
                continue;
            }

            // Cache raw height matrix, disposing of the old one
            if (_loadedChunks.TryGetValue(payload.Coord, out var oldHm))
            {
                oldHm?.Dispose();
            }
            _loadedChunks[payload.Coord] = payload.Heights.Clone();
            _loadedResolutions[payload.Coord] = W;

            // Dispose the original payload heights — we now work exclusively
            // with the stored clone so _loadedChunks always reflects the
            // welded state that future neighbors will read.
            payload.Heights.Dispose();
            HeightMatrix storedHeights = _loadedChunks[payload.Coord];

            // Perform Seam Welding on the STORED clone so _loadedChunks stays
            // consistent with what Terrain3D actually displays. Previously we
            // welded the original (now disposed) while the stored clone stayed
            // un-welded, causing cumulative boundary discrepancies.
            WeldChunk(payload.Coord, storedHeights);

            try
            {
                // 1. Upload heightmap and control map images together (welded stored clone + pre-packed control)
                UploadChunkImage(payload.Coord, storedHeights, payload.ControlMap, dataObject);
                uploaded++;

                // 2. Control map image is now uploaded in a single atomic import_images call, dispose it
                if (payload.ControlMap != null)
                {
                    payload.ControlMap.Dispose();
                }

                // 3. Upload foliage/object instances if present
                if (payload.Instances != null)
                {
                    try
                    {
                        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
                        if (terrainNode != null && _instancerGraphRoot is Terrain3DInstancerOutputNode instNode)
                        {
                            var ctx = new GenerationContext(payload.Coord, ChunkResolution, ChunkPadding, 
                                new Vector3(payload.Coord.X * ChunkWorldSize, 0, payload.Coord.Z * ChunkWorldSize), 
                                ChunkWorldSize, GetActiveHeightScale());
                            
                            instNode.PushToTerrain3DNode(terrainNode, ctx, payload.Instances);
                        }
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[TerrainManager] Exception uploading instancer for chunk {payload.Coord}: {ex.Message}");
                    }
                }

                // Update ocean water plane if present
                if (SpawnWaterMeshes)
                {
                    var oceanRes = FindOceanLevelNodeResource();
                    if (oceanRes != null)
                    {
                        UpdateOceanPlane(payload.Coord, oceanRes.WaterLevel);
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[TerrainManager] Exception uploading chunk {payload.Coord} to Terrain3D: {ex.Message}");
            }

            _draftCoords.Remove(payload.Coord);
        }

        // Process deferred weld re-uploads (max 2 per frame)
        if (_pendingReUploads.Count > 0)
        {
            int uploadedReWelds = 0;
            var uploadedList = new List<ChunkCoordinate>();

            foreach (var coord in _pendingReUploads)
            {
                if (uploadedReWelds >= 1) break;

                if (_loadedChunks.TryGetValue(coord, out var hm))
                {
                    try
                    {
                        UploadChunkImage(coord, hm, null, dataObject);
                        uploadedReWelds++;
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[TerrainManager] Exception uploading re-welded chunk {coord}: {ex.Message}");
                    }
                }
                uploadedList.Add(coord);
            }

            foreach (var coord in uploadedList)
            {
                _pendingReUploads.Remove(coord);
            }
        }

        if (_didUploadThisFrame)
        {
            _didUploadThisFrame = false;
            try
            {
                dataObject.Call("update_maps");
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[TerrainManager] Failed to update maps once-per-frame: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Evicts chunks that are no longer within unload distance range.
    /// </summary>
    private void EvictOutOfUnloadRangeChunks(int centerX, int centerZ)
    {
        Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
        GodotObject dataObject = null;
        if (terrainNode != null)
        {
            var dataVar = terrainNode.Get("data");
            if (dataVar.Obj != null)
            {
                dataObject = dataVar.As<GodotObject>();
            }
        }

        float regionSize = 1024.0f;
        if (terrainNode != null)
        {
            if (terrainNode.HasMethod("get_region_size"))
            {
                regionSize = terrainNode.Call("get_region_size").As<float>();
            }
            if (terrainNode.HasMethod("get_vertex_spacing"))
            {
                float spacing = terrainNode.Call("get_vertex_spacing").As<float>();
                regionSize *= spacing;
            }
        }

        var toEvict = new List<ChunkCoordinate>();
        foreach (var coord in _loadedChunks.Keys)
        {
            if (PinnedChunks.Contains(coord))
            {
                continue;
            }
            if (BypassedChunks.Contains(coord) || IsCoordOutsideUnloadRange(coord, centerX, centerZ))
            {
                toEvict.Add(coord);
            }
        }

        foreach (var coord in toEvict)
        {
            // Evict intermediate caches from all nodes in the generation graph
            ClearNodeCachesForChunk(coord);

            // Recycle heights matrix to return backing float array to ArrayPool
            if (_loadedChunks.TryGetValue(coord, out var hm))
            {
                hm?.Dispose();
            }
            _loadedChunks.Remove(coord);
            _loadedResolutions.Remove(coord);
            _draftCoords.Remove(coord);

            // Evict water plane
            string name = $"WaterPlane_{coord.X}_{coord.Z}";
            if (HasNode(name))
            {
                GetNode(name).QueueFree();
            }

            // Remove region from Terrain3D GDExtension ONLY if no other active chunks share this region tile
            if (dataObject != null)
            {
                try
                {
                    Vector3 globalPos = new Vector3(coord.X * ChunkWorldSize, 0f, coord.Z * ChunkWorldSize);
                    
                    float rx_evict = Mathf.Floor(globalPos.X / regionSize);
                    float rz_evict = Mathf.Floor(globalPos.Z / regionSize);
                    
                    bool regionShared = false;
                    foreach (var activeCoord in _loadedChunks.Keys)
                    {
                        Vector3 activePos = new Vector3(activeCoord.X * ChunkWorldSize, 0f, activeCoord.Z * ChunkWorldSize);
                        float rx_active = Mathf.Floor(activePos.X / regionSize);
                        float rz_active = Mathf.Floor(activePos.Z / regionSize);
                        
                        if (Mathf.IsEqualApprox(rx_evict, rx_active) && Mathf.IsEqualApprox(rz_evict, rz_active))
                        {
                            regionShared = true;
                            break;
                        }
                    }
                    
                    if (!regionShared)
                    {
                        // Check active region boundaries [-16, 15] to prevent native "Region not found" warnings
                        int rx_evict_int = Mathf.FloorToInt(globalPos.X / regionSize);
                        int rz_evict_int = Mathf.FloorToInt(globalPos.Z / regionSize);
                        if (rx_evict_int >= -16 && rx_evict_int <= 15 && rz_evict_int >= -16 && rz_evict_int <= 15)
                        {
                            dataObject.Call("remove_regionp", globalPos, false);
                            _didUploadThisFrame = true;
                        }
                    }
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[TerrainManager] Failed to remove region {coord} from Terrain3D: {ex.Message}");
                }
            }
        }
    }

    #region Water Spawning and Compilation

    private void ClearWaterMeshes()
    {
        foreach (Node child in GetChildren())
        {
            string cName = child.Name.ToString();
            if (cName.StartsWith("WaterPlane_") || cName.StartsWith("RiverMesh_"))
            {
                child.QueueFree();
            }
        }
    }

    private OceanLevelNodeResource FindOceanLevelNodeResource()
    {
        if (Graph == null) return null;
        foreach (var nodeRes in Graph.Nodes)
        {
            if (nodeRes is OceanLevelNodeResource oceanRes)
            {
                return oceanRes;
            }
        }
        return null;
    }

    private void UpdateOceanPlane(ChunkCoordinate coord, float waterLevel)
    {
        string name = $"WaterPlane_{coord.X}_{coord.Z}";
        float activeHeightScale = GetActiveHeightScale();
        if (HasNode(name))
        {
            var plane = GetNode<MeshInstance3D>(name);
            plane.GlobalPosition = new Vector3(
                (coord.X + 0.5f) * ChunkWorldSize,
                waterLevel * activeHeightScale,
                (coord.Z + 0.5f) * ChunkWorldSize
            );
            return;
        }

        var meshInstance = new MeshInstance3D();
        meshInstance.Name = name;

        var planeMesh = new PlaneMesh();
        planeMesh.Size = new Vector2(ChunkWorldSize, ChunkWorldSize);

        var material = new StandardMaterial3D();
        material.AlbedoColor = new Color(0.1f, 0.4f, 0.8f, 0.6f);
        material.Transparency = BaseMaterial3D.TransparencyEnum.Alpha;
        material.Roughness = 0.1f;
        material.Metallic = 0.1f;
        planeMesh.Material = material;

        meshInstance.Mesh = planeMesh;
        meshInstance.GlobalPosition = new Vector3(
            (coord.X + 0.5f) * ChunkWorldSize,
            waterLevel * activeHeightScale,
            (coord.Z + 0.5f) * ChunkWorldSize
        );

        AddChild(meshInstance);
    }

    private RiverGeneratorNode FindRiverGeneratorNodeRuntime()
    {
        if (_graphRoot == null) return null;
        var visited = new HashSet<TerrainNode>();
        var queue = new Queue<TerrainNode>();
        queue.Enqueue(_graphRoot);
        visited.Add(_graphRoot);

        while (queue.Count > 0)
        {
            var curr = queue.Dequeue();
            if (curr is RiverGeneratorNode riverNode)
            {
                return riverNode;
            }
            foreach (var inputLink in curr.InputLinks)
            {
                if (inputLink.SourceNode != null && !visited.Contains(inputLink.SourceNode))
                {
                    visited.Add(inputLink.SourceNode);
                    queue.Enqueue(inputLink.SourceNode);
                }
            }
        }
        return null;
    }

    private void CompileRiverMeshes()
    {
        // Clear old river meshes first
        foreach (Node child in GetChildren())
        {
            string cName = child.Name.ToString();
            if (cName.StartsWith("RiverMesh_"))
            {
                child.QueueFree();
            }
        }

        var riverNode = FindRiverGeneratorNodeRuntime();
        if (riverNode == null) return;

        // Find the spline input connection (Input 1)
        if (riverNode.InputLinks.Length <= 1) return;
        var splineLink = riverNode.InputLinks[1];
        if (splineLink.SourceNode == null) return;

        // Pull the spline set on the main thread
        var tempCtx = new GenerationContext(new ChunkCoordinate(0, 0), resolution: ChunkResolution, padding: ChunkPadding, worldOrigin: Vector3.Zero, worldSize: ChunkWorldSize);
        SplineSet splineSet = splineLink.SourceNode.PullData(tempCtx, splineLink.SourcePortIndex) as SplineSet;

        if (splineSet == null || splineSet.GetCurveCount() == 0) return;

        float riverWidth = riverNode.AssociatedResource != null ? riverNode.AssociatedResource.RiverWidth : 20.0f;
        float halfWidth = riverWidth / 2.0f;

        int riverIdx = 0;
        foreach (var curve in splineSet.Curves)
        {
            if (curve.ControlPoints.Count < 2) continue;

            var pts = curve.ControlPoints;
            SplineMath.ComputeTangents(curve, out var tOut, out var tIn);

            var vertices = new List<Vector3>();
            int n = pts.Count;
            int segments = curve.Type == CurveType.Closed ? n : n - 1;

            for (int s = 0; s < segments; s++)
            {
                Vector3 p0 = pts[s];
                Vector3 p3 = pts[(s + 1) % n];
                Vector3 p1 = p0 + tOut[s];
                Vector3 p2 = p3 + tIn[(s + 1) % n];

                int steps = 16;
                for (int i = 0; i < steps; i++)
                {
                    float t = (float)i / steps;
                    Vector3 pos = SplineMath.EvaluateBezierPosition(p0, p1, p2, p3, t);
                    Vector3 vel = SplineMath.EvaluateBezierDerivative(p0, p1, p2, p3, t);
                    Vector3 forward = vel.Normalized();
                    Vector3 left = forward.Cross(Vector3.Up).Normalized();

                    vertices.Add(pos + left * halfWidth);
                    vertices.Add(pos - left * halfWidth);
                }
            }

            if (curve.Type == CurveType.Open)
            {
                Vector3 p0 = pts[n - 2];
                Vector3 p3 = pts[n - 1];
                Vector3 p1 = p0 + tOut[n - 2];
                Vector3 p2 = p3 + tIn[n - 1];

                Vector3 pos = p3;
                Vector3 vel = SplineMath.EvaluateBezierDerivative(p0, p1, p2, p3, 1.0f);
                Vector3 forward = vel.Normalized();
                Vector3 left = forward.Cross(Vector3.Up).Normalized();

                vertices.Add(pos + left * halfWidth);
                vertices.Add(pos - left * halfWidth);
            }
            else
            {
                Vector3 p0 = pts[n - 1];
                Vector3 p3 = pts[0];
                Vector3 p1 = p0 + tOut[n - 1];
                Vector3 p2 = p3 + tIn[0];

                Vector3 pos = p3;
                Vector3 vel = SplineMath.EvaluateBezierDerivative(p0, p1, p2, p3, 1.0f);
                Vector3 forward = vel.Normalized();
                Vector3 left = forward.Cross(Vector3.Up).Normalized();

                vertices.Add(pos + left * halfWidth);
                vertices.Add(pos - left * halfWidth);
            }

            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);

            var material = new StandardMaterial3D();
            material.AlbedoColor = new Color(0.1f, 0.4f, 0.8f, 0.6f);
            material.Transparency = BaseMaterial3D.TransparencyEnum.Alpha;
            material.Roughness = 0.1f;
            material.Metallic = 0.1f;
            st.SetMaterial(material);

            int vCount = vertices.Count;
            for (int i = 0; i < vCount; i++)
            {
                float progress = (float)(i / 2) / (vCount / 2);
                float side = (i % 2 == 0) ? 0.0f : 1.0f;
                st.SetUV(new Vector2(progress * 10.0f, side));
                st.SetNormal(Vector3.Up);
                st.AddVertex(vertices[i]);
            }

            for (int i = 0; i < (vCount / 2) - 1; i++)
            {
                int v0 = i * 2;
                int v1 = i * 2 + 1;
                int v2 = (i + 1) * 2;
                int v3 = (i + 1) * 2 + 1;

                st.AddIndex(v0);
                st.AddIndex(v2);
                st.AddIndex(v1);

                st.AddIndex(v1);
                st.AddIndex(v2);
                st.AddIndex(v3);
            }

            var mesh = st.Commit();
            var meshInstance = new MeshInstance3D();
            meshInstance.Name = $"RiverMesh_{riverIdx}";
            meshInstance.Mesh = mesh;

            AddChild(meshInstance);
            riverIdx++;
        }
    }

    private void WeldChunk(ChunkCoordinate coord, HeightMatrix heights)
    {
        int P = ChunkPadding;
        int res = heights.Width - 2 * P;
        int M = WeldMargin;
        bool lowerOnMismatch = WeldLowerOnMismatch;

        _weldModifiedCoords.Clear();

        // Check West neighbor (coord.X - 1, coord.Z)
        var westCoord = new ChunkCoordinate(coord.X - 1, coord.Z);
        if (_loadedChunks.TryGetValue(westCoord, out var westHM) && _loadedResolutions.TryGetValue(westCoord, out int westRes) && westRes == res)
        {
            for (int z = 0; z < res; z++)
            {
                int pz = z + P;
                float h_curr = heights[P, pz];
                float h_neigh = westHM[res - 1 + P, pz];
                float h_weld = lowerOnMismatch ? MathF.Min(h_curr, h_neigh) : 0.5f * (h_curr + h_neigh);

                float delta_curr = h_weld - h_curr;
                float delta_neigh = h_weld - h_neigh;

                heights[P, pz] = h_weld;
                westHM[res - 1 + P, pz] = h_weld;

                for (int k = 1; k <= M; k++)
                {
                    float w = (float)(M - k) / M;
                    heights[P + k, pz] += delta_curr * w;
                    westHM[res - 1 + P - k, pz] += delta_neigh * w;
                }
            }
            _weldModifiedCoords.Add(westCoord);
        }

        // Check East neighbor (coord.X + 1, coord.Z)
        var eastCoord = new ChunkCoordinate(coord.X + 1, coord.Z);
        if (_loadedChunks.TryGetValue(eastCoord, out var eastHM) && _loadedResolutions.TryGetValue(eastCoord, out int eastRes) && eastRes == res)
        {
            for (int z = 0; z < res; z++)
            {
                int pz = z + P;
                float h_curr = heights[res - 1 + P, pz];
                float h_neigh = eastHM[P, pz];
                float h_weld = lowerOnMismatch ? MathF.Min(h_curr, h_neigh) : 0.5f * (h_curr + h_neigh);

                float delta_curr = h_weld - h_curr;
                float delta_neigh = h_weld - h_neigh;

                heights[res - 1 + P, pz] = h_weld;
                eastHM[P, pz] = h_weld;

                for (int k = 1; k <= M; k++)
                {
                    float w = (float)(M - k) / M;
                    heights[res - 1 + P - k, pz] += delta_curr * w;
                    eastHM[P + k, pz] += delta_neigh * w;
                }
            }
            _weldModifiedCoords.Add(eastCoord);
        }

        // Check North neighbor (coord.X, coord.Z - 1)
        var northCoord = new ChunkCoordinate(coord.X, coord.Z - 1);
        if (_loadedChunks.TryGetValue(northCoord, out var northHM) && _loadedResolutions.TryGetValue(northCoord, out int northRes) && northRes == res)
        {
            for (int x = 0; x < res; x++)
            {
                int px = x + P;
                float h_curr = heights[px, P];
                float h_neigh = northHM[px, res - 1 + P];
                float h_weld = lowerOnMismatch ? MathF.Min(h_curr, h_neigh) : 0.5f * (h_curr + h_neigh);

                float delta_curr = h_weld - h_curr;
                float delta_neigh = h_weld - h_neigh;

                heights[px, P] = h_weld;
                northHM[px, res - 1 + P] = h_weld;

                for (int k = 1; k <= M; k++)
                {
                    float w = (float)(M - k) / M;
                    heights[px, P + k] += delta_curr * w;
                    northHM[px, res - 1 + P - k] += delta_neigh * w;
                }
            }
            _weldModifiedCoords.Add(northCoord);
        }

        // Check South neighbor (coord.X, coord.Z + 1)
        var southCoord = new ChunkCoordinate(coord.X, coord.Z + 1);
        if (_loadedChunks.TryGetValue(southCoord, out var southHM) && _loadedResolutions.TryGetValue(southCoord, out int southRes) && southRes == res)
        {
            for (int x = 0; x < res; x++)
            {
                int px = x + P;
                float h_curr = heights[px, res - 1 + P];
                float h_neigh = southHM[px, P];
                float h_weld = lowerOnMismatch ? MathF.Min(h_curr, h_neigh) : 0.5f * (h_curr + h_neigh);

                float delta_curr = h_weld - h_curr;
                float delta_neigh = h_weld - h_neigh;

                heights[px, res - 1 + P] = h_weld;
                southHM[px, P] = h_weld;

                for (int k = 1; k <= M; k++)
                {
                    float w = (float)(M - k) / M;
                    heights[px, res - 1 + P - k] += delta_curr * w;
                    southHM[px, P + k] += delta_neigh * w;
                }
            }
            _weldModifiedCoords.Add(southCoord);
        }

        // Corner Resolution (SE, SW, NE, NW)
        ResolveCorner(coord, res, P, M, lowerOnMismatch, 1, 1, res - 1 + P, res - 1 + P, _weldModifiedCoords);
        ResolveCorner(coord, res, P, M, lowerOnMismatch, -1, 1, P, res - 1 + P, _weldModifiedCoords);
        ResolveCorner(coord, res, P, M, lowerOnMismatch, 1, -1, res - 1 + P, P, _weldModifiedCoords);
        ResolveCorner(coord, res, P, M, lowerOnMismatch, -1, -1, P, P, _weldModifiedCoords);

        // Defer neighbors re-uploading
        foreach (var mCoord in _weldModifiedCoords)
        {
            if (mCoord != coord)
            {
                _pendingReUploads.Add(mCoord);
            }
        }
    }

    private struct CornerWeldData
    {
        public ChunkCoordinate Coord;
        public HeightMatrix Heights;
        public int X;
        public int Z;
    }

    private void ResolveCorner(ChunkCoordinate coord, int res, int P, int M, bool lowerOnMismatch, int dx, int dz, int px_curr, int pz_curr, HashSet<ChunkCoordinate> modifiedCoords)
    {
        var c00 = coord;
        var c10 = new ChunkCoordinate(coord.X + dx, coord.Z);
        var c01 = new ChunkCoordinate(coord.X, coord.Z + dz);
        var c11 = new ChunkCoordinate(coord.X + dx, coord.Z + dz);

        int px_10 = (dx > 0) ? P : (res - 1 + P);
        int pz_01 = (dz > 0) ? P : (res - 1 + P);

        // Declare 4 separate stack-allocated items
        CornerWeldData item0 = default;
        CornerWeldData item1 = default;
        CornerWeldData item2 = default;
        CornerWeldData item3 = default;
        int count = 0;

        if (_loadedChunks.TryGetValue(c00, out var hm00))
        {
            item0 = new CornerWeldData { Coord = c00, Heights = hm00, X = px_curr, Z = pz_curr };
            count++;
        }
        if (_loadedChunks.TryGetValue(c10, out var hm10) && _loadedResolutions.TryGetValue(c10, out int res10) && res10 == res)
        {
            var targetItem = new CornerWeldData { Coord = c10, Heights = hm10, X = px_10, Z = pz_curr };
            if (count == 0) item0 = targetItem; else item1 = targetItem;
            count++;
        }
        if (_loadedChunks.TryGetValue(c01, out var hm01) && _loadedResolutions.TryGetValue(c01, out int res01) && res01 == res)
        {
            var targetItem = new CornerWeldData { Coord = c01, Heights = hm01, X = px_curr, Z = pz_01 };
            if (count == 0) item0 = targetItem; else if (count == 1) item1 = targetItem; else item2 = targetItem;
            count++;
        }
        if (_loadedChunks.TryGetValue(c11, out var hm11) && _loadedResolutions.TryGetValue(c11, out int res11) && res11 == res)
        {
            var targetItem = new CornerWeldData { Coord = c11, Heights = hm11, X = px_10, Z = pz_01 };
            if (count == 0) item0 = targetItem; else if (count == 1) item1 = targetItem; else if (count == 2) item2 = targetItem; else item3 = targetItem;
            count++;
        }

        if (count < 2) return;

        // Perform math using stack-allocated items
        float sum = 0f;
        float minVal = float.MaxValue;

        // Static local function: cannot capture outer variables, guaranteeing 0 heap allocations
        static void ProcessSumMin(ref CornerWeldData item, ref float sumVal, ref float minHeightVal)
        {
            float val = item.Heights[item.X, item.Z];
            sumVal += val;
            if (val < minHeightVal) minHeightVal = val;
        }

        if (count > 0) ProcessSumMin(ref item0, ref sum, ref minVal);
        if (count > 1) ProcessSumMin(ref item1, ref sum, ref minVal);
        if (count > 2) ProcessSumMin(ref item2, ref sum, ref minVal);
        if (count > 3) ProcessSumMin(ref item3, ref sum, ref minVal);

        float h_weld = lowerOnMismatch ? minVal : sum / count;

        // Static local function: passes captured variables by value/ref to avoid closure allocation
        static void ApplyWeld(
            ref CornerWeldData item, float weldHeight, int PVal, int MVal, 
            ChunkCoordinate activeCoord, HashSet<ChunkCoordinate> modifiedSet)
        {
            var targetCoord = item.Coord;
            var hm = item.Heights;
            int cx = item.X;
            int cz = item.Z;

            float delta = weldHeight - hm[cx, cz];
            hm[cx, cz] = weldHeight;

            int x_step = (cx == PVal) ? 1 : -1;
            int z_step = (cz == PVal) ? 1 : -1;

            for (int sz = 0; sz <= MVal; sz++)
            {
                for (int sx = 0; sx <= MVal; sx++)
                {
                    if (sx == 0 && sz == 0) continue;
                    float w = (1.0f - (float)sx / MVal) * (1.0f - (float)sz / MVal);
                    hm[cx + sx * x_step, cz + sz * z_step] += delta * w;
                }
            }

            if (targetCoord != activeCoord)
            {
                modifiedSet.Add(targetCoord);
            }
        }

        if (count > 0) ApplyWeld(ref item0, h_weld, P, M, coord, modifiedCoords);
        if (count > 1) ApplyWeld(ref item1, h_weld, P, M, coord, modifiedCoords);
        if (count > 2) ApplyWeld(ref item2, h_weld, P, M, coord, modifiedCoords);
        if (count > 3) ApplyWeld(ref item3, h_weld, P, M, coord, modifiedCoords);
    }

    private void UploadChunkImage(ChunkCoordinate coord, HeightMatrix heights, Image controlImage, GodotObject dataObject)
    {
        int paddingToUse = ChunkPadding;
        int resolution = heights.Width - 2 * paddingToUse;

        float minH = float.MaxValue;
        float maxH = float.MinValue;
        float sumH = 0.0f;
        int nanCount = 0;

        int pixelCount = resolution * resolution;
        if (_uploadFloatBuffer == null || _uploadFloatBuffer.Length < pixelCount)
        {
            _uploadFloatBuffer = new float[pixelCount];
        }

        var srcSpan = heights.AsReadOnlySpan();
        int hmWidth = heights.Width;
        bool isHeightOutputNode = _graphRoot != null && _graphRoot.GetType().Name == "HeightOutputNode";

        for (int z = 0; z < resolution; z++)
        {
            int pz = z + paddingToUse;
            int rowOffset = z * resolution;
            int srcRowOffset = pz * hmWidth;
            for (int x = 0; x < resolution; x++)
            {
                int px = x + paddingToUse;
                float rawHeight = srcSpan[srcRowOffset + px];
                if (float.IsNaN(rawHeight))
                {
                    nanCount++;
                }
                else
                {
                    if (rawHeight < minH) minH = rawHeight;
                    if (rawHeight > maxH) maxH = rawHeight;
                    sumH += rawHeight;
                }

                if (isHeightOutputNode)
                {
                    _uploadFloatBuffer[rowOffset + x] = rawHeight;
                }
                else
                {
                    float heightRaw = Math.Clamp(rawHeight, 0.0f, 1.0f);
                    _uploadFloatBuffer[rowOffset + x] = heightRaw * HeightScale;
                }
            }
        }

        int byteCount = pixelCount * 4;
        var floatSpan = _uploadFloatBuffer.AsSpan(0, pixelCount);
        ReadOnlySpan<byte> byteView = MemoryMarshal.AsBytes(floatSpan);

        byte[] rentedArray = ArrayPool<byte>.Shared.Rent(byteCount);
        byteView.CopyTo(rentedArray);

        using (Image heightImage = Image.CreateFromData(resolution, resolution, false, Image.Format.Rf, rentedArray))
        {
            ArrayPool<byte>.Shared.Return(rentedArray);

            Node terrainNode = GetNodeOrNull(Terrain3DNodePath);
            float gridScale = 1.0f;
            if (terrainNode != null)
            {
                var gridScaleVar = terrainNode.Get("grid_scale");
                if (gridScaleVar.VariantType != Variant.Type.Nil)
                {
                    gridScale = gridScaleVar.As<float>();
                }
            }

            int targetRes = Mathf.RoundToInt(ChunkWorldSize / gridScale);
            
            Image croppedControl = null;
            if (controlImage != null)
            {
                int controlWidth = controlImage.GetWidth();
                if (controlWidth > resolution)
                {
                    Rect2I cropRect = new Rect2I(paddingToUse, paddingToUse, resolution, resolution);
                    croppedControl = controlImage.GetRegion(cropRect);
                }
                else
                {
                    croppedControl = controlImage;
                }
            }

            if (resolution != targetRes)
            {
                heightImage.Resize(targetRes, targetRes, Image.Interpolation.Bilinear);
                if (croppedControl != null)
                {
                    croppedControl.Resize(targetRes, targetRes, Image.Interpolation.Nearest);
                }
            }

            if (croppedControl != null && (croppedControl.GetWidth() != heightImage.GetWidth() || croppedControl.GetHeight() != heightImage.GetHeight()))
            {
                if (croppedControl == controlImage)
                {
                    croppedControl = (Image)controlImage.Duplicate();
                }
                croppedControl.Resize(heightImage.GetWidth(), heightImage.GetHeight(), Image.Interpolation.Nearest);
            }

            try
            {
                Vector3 globalPosition = new Vector3(coord.X * ChunkWorldSize, 0, coord.Z * ChunkWorldSize);

                // Compute region index boundaries to prevent native crashes/errors
                float regionScale = 1024.0f;
                if (terrainNode != null)
                {
                    if (terrainNode.HasMethod("get_region_size"))
                    {
                        regionScale = terrainNode.Call("get_region_size").As<float>();
                    }
                    if (terrainNode.HasMethod("get_vertex_spacing"))
                    {
                        float spacing = terrainNode.Call("get_vertex_spacing").As<float>();
                        regionScale *= spacing;
                    }
                }

                int rx = Mathf.FloorToInt(globalPosition.X / regionScale);
                int rz = Mathf.FloorToInt(globalPosition.Z / regionScale);

                // Terrain3D's supported region map size bounds go from -16 to 15


                // Ensure the region exists in Terrain3D before importing
                if (!dataObject.Call("has_regionp", globalPosition).As<bool>())
                {
                    dataObject.Call("add_region_blankp", globalPosition, false);
                }

                var imagesArray = new Godot.Collections.Array();
                imagesArray.Resize(3);
                imagesArray[0] = heightImage;
                imagesArray[1] = (croppedControl != null) ? (Variant)croppedControl : new Variant();
                imagesArray[2] = new Variant();

                float importScale = 1.0f;
                float importOffset = 0.0f;

                dataObject.Call("import_images", imagesArray, globalPosition, importOffset, importScale);
                imagesArray.Clear();
                _didUploadThisFrame = true;

                if (croppedControl != null && croppedControl != controlImage)
                {
                    croppedControl.Dispose();
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[TerrainManager] Exception uploading chunk {coord} to Terrain3D during welding: {ex.Message}");
            }
        }
    }

    private void ClearNodeCachesForChunk(ChunkCoordinate coord)
    {
        foreach (var node in _allGraphNodes)
        {
            node.ClearCacheForChunk(coord);
        }
    }

    private float GetActiveHeightScale()
    {
        return _cachedActiveHeightScale;
    }

    /// <summary>
    /// Thread-safe getter for the number of loaded terrain chunks.
    /// </summary>
    public int GetLoadedChunkCount()
    {
        lock (_schedulerLock)
        {
            return _loadedChunks.Count;
        }
    }

    /// <summary>
    /// Thread-safe getter for all loaded chunk coordinates.
    /// </summary>
    public List<ChunkCoordinate> GetLoadedChunkCoordinates()
    {
        lock (_schedulerLock)
        {
            return new List<ChunkCoordinate>(_loadedChunks.Keys);
        }
    }

    /// <summary>
    /// Thread-safe getter for a loaded chunk's resolution, returning -1 if not loaded.
    /// </summary>
    public int GetChunkResolution(ChunkCoordinate coord)
    {
        lock (_schedulerLock)
        {
            if (_loadedResolutions.TryGetValue(coord, out int res))
            {
                return res;
            }
            return -1;
        }
    }

    /// <summary>
    /// Thread-safe helper to scan a loaded chunk's heightmatrix for its minimum and maximum heights.
    /// Returns true if loaded and scanned successfully, false otherwise.
    /// </summary>
    public bool GetChunkHeightRange(ChunkCoordinate coord, out float minHeight, out float maxHeight)
    {
        minHeight = float.MaxValue;
        maxHeight = float.MinValue;
        lock (_schedulerLock)
        {
            if (_loadedChunks.TryGetValue(coord, out var hm))
            {
                try
                {
                    ReadOnlySpan<float> span = hm.AsReadOnlySpan();
                    if (span.Length == 0)
                    {
                        return false;
                    }
                    float min = float.MaxValue;
                    float max = float.MinValue;
                    for (int i = 0; i < span.Length; i++)
                    {
                        float v = span[i];
                        if (v < min) min = v;
                        if (v > max) max = v;
                    }
                    minHeight = min;
                    maxHeight = max;
                    return true;
                }
                catch
                {
                    return false;
                }
            }
            return false;
        }
    }

    #endregion
}
