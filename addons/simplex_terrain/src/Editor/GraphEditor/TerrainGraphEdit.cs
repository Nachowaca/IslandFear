using Godot;
using System;
using System.Collections.Generic;
using System.Reflection;

namespace SimpleXTerrain;

/// <summary>
/// Custom infinite node canvas workspace using Godot's built-in GraphEdit control.
/// Manages spawning, connecting, disconnecting, and deleting visual nodes,
/// synchronizing all changes in real-time to the active TerrainGraphResource.
/// </summary>
[Tool]
public partial class TerrainGraphEdit : GraphEdit
{
    private TerrainGraphResource _graphResource;
    private string _activeResourcePath = string.Empty;
    private bool _isCleanedUp = false;

    /// <summary>
    /// Event emitted when the graph is modified (node added, deleted, connected, or disconnected).
    /// Used by the editor parent to request viewport refreshes.
    /// </summary>
    [Signal]
    public delegate void GraphModifiedEventHandler();

    /// <summary>
    /// Event emitted when a node is selected in the canvas.
    /// </summary>
    [Signal]
    public delegate void TerrainNodeSelectedEventHandler(TerrainNodeResource nodeResource);

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainGraphEdit"/> class.
    /// </summary>
    public TerrainGraphEdit()
    {
        // Configure GraphEdit settings
        RightDisconnects = true;
        SnapDistance = 15;
        UseSnap = true;
        SizeFlagsHorizontal = SizeFlags.ExpandFill;
        SizeFlagsVertical = SizeFlags.ExpandFill;

        // Wire built-in signals
        ConnectionRequest += OnConnectionRequest;
        DisconnectionRequest += OnDisconnectionRequest;
    }

    private Vector2 _rightClickPosition;
    private PopupMenu _contextMenu;
    private readonly List<PopupMenu> _submenus = new();
    private readonly Dictionary<PopupMenu, List<(string DisplayName, string NodeType)>> _submenuItemData = new();

    /// <summary>
    /// Called when the node enters the scene tree.
    /// </summary>
    public override void _Ready()
    {
        try
        {
            base._Ready();
            GD.Print("[DEBUG] TerrainGraphEdit._Ready() starting...");

            // Register compatible cross-type visual port connections in Godot's GraphEdit UI layer
            // 0 = Height (Blue), 1 = Mask (Orange)
            AddValidConnectionType((int)PortType.Height, (int)PortType.Mask);
            AddValidConnectionType((int)PortType.Mask, (int)PortType.Height);
            AddValidConnectionType((int)PortType.Scalar, (int)PortType.Height);

            PopupRequest += OnPopupRequest;
            GD.Print("[DEBUG] PopupRequest signal connected successfully");
            BuildContextMenu();
            
            // Auto-create a default in-memory graph so users can start adding nodes immediately
            if (_graphResource == null)
            {
                _graphResource = new TerrainGraphResource();
                _activeResourcePath = "res://default_terrain_graph.tres";
                GD.Print("[TerrainGraphEdit] Created default empty graph for immediate editing");
            }
            
            GD.Print($"[DEBUG] TerrainGraphEdit._Ready() completed. Size: {Size}, Visible: {Visible}");
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Error in _Ready(): {ex}");
        }
    }

    /// <summary>
    private void CleanUp(bool isDisposing)
    {
        if (_isCleanedUp) return;
        _isCleanedUp = true;

        if (IsConnected(SignalName.ConnectionRequest, new Callable(this, MethodName.OnConnectionRequest)))
        {
            try
            {
                ConnectionRequest -= OnConnectionRequest;
            }
            catch { }
        }
        if (IsConnected(SignalName.DisconnectionRequest, new Callable(this, MethodName.OnDisconnectionRequest)))
        {
            try
            {
                DisconnectionRequest -= OnDisconnectionRequest;
            }
            catch { }
        }
        if (IsConnected(SignalName.PopupRequest, new Callable(this, MethodName.OnPopupRequest)))
        {
            try
            {
                PopupRequest -= OnPopupRequest;
            }
            catch { }
        }

        if (!isDisposing)
        {
            // Clean up all children visual nodes and disconnect their delegates
            ClearCanvas();
        }

        // Clean up submenu event subscriptions (named method, no lambdas)
        foreach (var submenu in _submenus)
        {
            if (GodotObject.IsInstanceValid(submenu))
            {
                if (submenu.IsConnected(PopupMenu.SignalName.IdPressed, new Callable(this, MethodName.OnSubmenuItemSelected)))
                {
                    try
                    {
                        submenu.IdPressed -= OnSubmenuItemSelected;
                    }
                    catch { }
                }
            }
        }
        _submenus.Clear();
        _submenuItemData.Clear();
    }

    /// <summary>
    /// Called when the node leaves the scene tree.
    /// Cleans up signal delegates to prevent interop leaks.
    /// </summary>
    public override void _ExitTree()
    {
        CleanUp(false);
        base._ExitTree();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            CleanUp(true);
            try
            {
                QueueFree();
            }
            catch { }
        }
        base.Dispose(disposing);
    }

    /// <summary>
    /// Fallback GUI input handler to capture right-clicks for the context menu.
    /// </summary>
    public override void _GuiInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Right && mb.Pressed)
        {
            GD.Print($"[DEBUG] _GuiInput right-click detected at: {mb.Position}");
            _rightClickPosition = mb.Position;
            Vector2 globalPos = GetGlobalTransform() * mb.Position;
            GD.Print($"[DEBUG] Showing context menu via _GuiInput at global: {globalPos}, menu null? {_contextMenu == null}");
            _contextMenu?.Popup(new Rect2I((Vector2I)globalPos, Vector2I.Zero));
            AcceptEvent();
        }
    }

    private void OnPopupRequest(Vector2 position)
    {
        GD.Print($"[DEBUG] PopupRequest FIRED at position: {position}");
        _rightClickPosition = position;
        Vector2 globalPosition = GetGlobalTransform() * position;
        GD.Print($"[DEBUG] Showing context menu at global: {globalPosition}, menu null? {_contextMenu == null}");
        _contextMenu?.Popup(new Rect2I((Vector2I)globalPosition, Vector2I.Zero));
    }

    /// <summary>
    /// Named handler for all submenu IdPressed signals, replacing per-submenu lambda closures.
    /// Looks up which submenu fired using the _submenuItemData dictionary.
    /// </summary>
    private void OnSubmenuItemSelected(long id)
    {
        // Identify which submenu triggered this by checking which one just had an item activated.
        // Since Godot calls the handler on the specific signal source, we iterate to find it.
        foreach (var kvp in _submenuItemData)
        {
            PopupMenu submenu = kvp.Key;
            var itemsList = kvp.Value;

            // Check if this submenu's focused item index matches — use a flag approach
            // The IdPressed signal is fired by the specific submenu, and since all submenus
            // share this handler, we check if 'id' is valid for each list. We rely on the
            // fact that only one submenu is active at a time (popup menus are modal).
            if (!GodotObject.IsInstanceValid(submenu) || !submenu.Visible)
            {
                continue;
            }

            if (id >= 0 && id < itemsList.Count)
            {
                string nodeType = itemsList[(int)id].NodeType;
                Vector2 canvasPos = (_rightClickPosition + ScrollOffset) / Zoom;
                if (nodeType == "CREATE_FRAME")
                {
                    SpawnFrame(canvasPos);
                }
                else if (nodeType == "CREATE_COMMENT")
                {
                    SpawnComment(canvasPos);
                }
                else
                {
                    SpawnNode(nodeType, canvasPos);
                }
                return;
            }
        }
    }

    private void BuildContextMenu()
    {
        _contextMenu = new PopupMenu();
        _contextMenu.Name = "CanvasContextMenu";
        AddChild(_contextMenu);

        var categories = new Dictionary<string, List<(string DisplayName, string NodeType)>>()
        {
            {
                "Generators", new()
                {
                    ("Perlin Noise", "PerlinNoiseNode"),
                    ("Fractal Noise", "FractalNode"),
                    ("Voronoi Cellular", "VoronoiNode"),
                    ("Constant Scalar", "DummyConstantNode"),
                    ("Primitive Form", "PrimitiveFormNode"),
                    ("Radial Spot", "SpotNode")
                }
            },
            {
                "Modifiers", new()
                {
                    ("Levels & Contrast", "LevelsNode"),
                    ("LUT Curve", "CurveNode"),
                    ("Blend Combiner", "BlendNode"),
                    ("Slope Selector", "SlopeNode"),
                    ("Binomial Blur", "BlurNode"),
                    ("Discrete Laplacian", "CavityNode"),
                    ("Smooth Terrace", "TerraceNode"),
                    ("Hermite Ledge", "LedgeNode"),
                    ("Shoreline Beach", "BeachNode"),
                    ("Moore Soil Erosion", "ErosionNode"),
                    ("Aspect Shading", "AspectMapperNode"),
                    ("Parallax Displacement", "ParallaxDisplacementNode")
                }
            },
            {
                "Splatting", new()
                {
                    ("Unified Splatmap", "SplatNode"),
                    ("Texture Input", "TextureInputNode")
                }
            },
            {
                "Scatter", new()
                {
                    ("Mitchell Scatter", "ScatterNode"),
                    ("Terrain Snap & Normal", "TerrainSnapNode"),
                    ("Stochastic Prune", "PruneNode"),
                    ("Exclusion Proximity", "ProximityDecimationNode"),
                    ("Local Excavator", "ExcavationNode"),
                    ("Radial Dispersal", "RadialDispersalNode"),
                    ("Cellular Forest Sim", "ForestSimulationNode"),
                    ("Particle Slide", "ParticleSlidingNode"),
                    ("Foliage Density", "FoliageDensityNode")
                }
            },
            {
                "Splines", new()
                {
                    ("Scene Path3D Input", "SplineInputNode"),
                    ("Spline Stroke Field", "SplineStrokeNode"),
                    ("Road Conform Blend", "SplineConformNode"),
                    ("De Casteljau Subdiv", "SplineSubdivideNode"),
                    ("Heron Prune Optimize", "SplineOptimizeNode"),
                    ("Midpoint Relax Smooth", "SplineRelaxNode"),
                    ("Proximity Weld Close", "SplineWeldCloseNode"),
                    ("Dijkstra Road Finder", "DijkstraPathNode"),
                    ("Gabriel Interlink", "GabrielGraphNode"),
                    ("Spline AABB Clip", "SplineClipNode")
                }
            },
            {
                "Portals & Loops", new()
                {
                    ("Portal Transmitter", "PortalTransmitterNode"),
                    ("Portal Receiver", "PortalReceiverNode"),
                    ("Loop Sub-Graph", "LoopNode"),
                    ("Loop Input", "LoopInputNode"),
                    ("Loop Output", "LoopOutputNode")
                }
            },
            {
                "Biomes", new()
                {
                    ("Biome Sub-Graph Ref", "BiomeReferenceNode"),
                    ("Unified Biome Blend", "BiomeBlendNode"),
                    ("Whittaker 2D Lookup", "WhittakerLookupNode")
                }
            },
            {
                "Geomorphology", new()
                {
                    ("Island Masking", "IslandMaskNode"),
                    ("Ocean Water Level", "OceanLevelNode"),
                    ("Lake Bed Excavator", "LakeExcavatorNode"),
                    ("River Channel Generator", "RiverGeneratorNode")
                }
            },
            {
                "Outputs", new()
                {
                    ("Terrain3D Height", "HeightOutputNode"),
                    ("Terrain3D ControlMap", "Terrain3DControlOutputNode"),
                    ("Terrain3D Instancer", "Terrain3DInstancerOutputNode"),
                    ("Heightmap Exporter", "HeightmapExportNode")
                }
            },
            {
                "Visual Grouping", new()
                {
                    ("Add Group Frame", "CREATE_FRAME"),
                    ("Add Comment Box", "CREATE_COMMENT")
                }
            }
        };

        foreach (var category in categories)
        {
            PopupMenu submenu = new PopupMenu();
            submenu.Name = category.Key;
            _contextMenu.AddChild(submenu);
            _contextMenu.AddSubmenuNodeItem(category.Key, submenu);

            var itemsList = category.Value;
            for (int i = 0; i < itemsList.Count; i++)
            {
                submenu.AddItem(itemsList[i].DisplayName, i);
            }

            // Store items data for dictionary lookup (no lambda capture)
            _submenuItemData[submenu] = itemsList;
            submenu.IdPressed += OnSubmenuItemSelected;
            _submenus.Add(submenu);
        }
    }

    /// <summary>
    /// Loads a serialized graph resource into the workspace canvas.
    /// </summary>
    /// <param name="graphResource">The graph resource to load.</param>
    /// <param name="path">The file path to save adjustments to.</param>
    public void LoadGraph(TerrainGraphResource graphResource, string path)
    {
        _graphResource = graphResource;
        _activeResourcePath = path;

        // Clear existing canvas elements
        ClearCanvas();

        if (graphResource == null)
        {
            return;
        }

        // 1. Instantiate visual graph nodes
        Dictionary<string, TerrainGraphNode> visualNodes = new();
        
        foreach (var nodeResource in graphResource.Nodes)
        {
            if (nodeResource == null || string.IsNullOrEmpty(nodeResource.NodeId))
            {
                continue;
            }

            try
            {
                TerrainNode runtimeNode = GraphEvaluator.CreateNodeInstance(nodeResource.NodeType);
                runtimeNode.NodeId = nodeResource.NodeId;
                
                // Link parameter resource
                var prop = runtimeNode.GetType().GetProperty("AssociatedResource");
                if (prop != null && prop.CanWrite)
                {
                    prop.SetValue(runtimeNode, nodeResource);
                }

                // Call custom initialization if defined
                var onResourceSetMethod = runtimeNode.GetType().GetMethod("OnResourceSet");
                if (onResourceSetMethod != null)
                {
                    onResourceSetMethod.Invoke(runtimeNode, null);
                }

                TerrainGraphNode visualNode = new TerrainGraphNode();
                AddChild(visualNode);
                
                // Initialize layout and connection slots
                visualNode.Initialize(nodeResource, runtimeNode);
                
                // Connect visual interaction signals
                visualNode.NodeDragged += OnVisualNodeDragged;
                visualNode.NodeCloseRequested += OnVisualNodeCloseRequested;
                visualNode.NodeSelectedEvent += OnVisualNodeSelected;

                visualNodes[nodeResource.NodeId] = visualNode;
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[TerrainGraphEdit] Failed to load node of type '{nodeResource.NodeType}': {ex.Message}");
            }
        }

        // 2. Re-establish visual connection lines
        foreach (var conn in graphResource.Connections)
        {
            if (conn == null)
            {
                continue;
            }

            if (visualNodes.ContainsKey(conn.FromNodeId) && visualNodes.ContainsKey(conn.ToNodeId))
            {
                // Check if port indices are within bounds to prevent crash
                var fromNode = visualNodes[conn.FromNodeId];
                var toNode = visualNodes[conn.ToNodeId];

                if (conn.FromPort >= 0 && conn.FromPort < fromNode.RuntimeNode.Outputs.Count &&
                    conn.ToPort >= 0 && conn.ToPort < toNode.RuntimeNode.Inputs.Count)
                {
                    ConnectNode(fromNode.Name, conn.FromPort, toNode.Name, conn.ToPort);
                }
            }
        }

        // 3. Load visual frames
        if (graphResource.Frames != null)
        {
            foreach (var frameData in graphResource.Frames)
            {
                if (frameData == null) continue;
                TerrainGraphFrame visualFrame = new TerrainGraphFrame();
                AddChild(visualFrame);
                visualFrame.Initialize(frameData);
                visualFrame.NodeCloseRequested += OnVisualFrameCloseRequested;
                visualFrame.FrameDragged += OnVisualFrameDragged;
            }
        }

        // 4. Load visual comments
        if (graphResource.Comments != null)
        {
            foreach (var commentData in graphResource.Comments)
            {
                if (commentData == null) continue;
                TerrainGraphComment visualComment = new TerrainGraphComment();
                AddChild(visualComment);
                visualComment.Initialize(commentData);
                visualComment.NodeCloseRequested += OnVisualCommentCloseRequested;
                visualComment.CommentModified += OnVisualCommentModified;
            }
        }
    }

    /// <summary>
    /// Clears all visual nodes and connection lines from the canvas workspace.
    /// </summary>
    public void ClearCanvas()
    {
        ClearConnections();
        
        foreach (var child in GetChildren())
        {
            if (child is TerrainGraphNode visualNode)
            {
                // Disconnect signals to prevent memory leaks
                visualNode.NodeDragged -= OnVisualNodeDragged;
                visualNode.NodeCloseRequested -= OnVisualNodeCloseRequested;
                visualNode.NodeSelectedEvent -= OnVisualNodeSelected;
                
                RemoveChild(visualNode);
                visualNode.Free();
            }
            else if (child is TerrainGraphFrame visualFrame)
            {
                visualFrame.NodeCloseRequested -= OnVisualFrameCloseRequested;
                visualFrame.FrameDragged -= OnVisualFrameDragged;
                RemoveChild(visualFrame);
                visualFrame.Free();
            }
            else if (child is TerrainGraphComment visualComment)
            {
                visualComment.NodeCloseRequested -= OnVisualCommentCloseRequested;
                visualComment.CommentModified -= OnVisualCommentModified;
                RemoveChild(visualComment);
                visualComment.Free();
            }
        }
    }

    /// <summary>
    /// Save the active graph resource back to disk.
    /// </summary>
    public void SaveGraph()
    {
        if (_graphResource == null || string.IsNullOrEmpty(_activeResourcePath))
        {
            return;
        }

        Error err = ResourceSaver.Save(_graphResource, _activeResourcePath);
        if (err != Error.Ok)
        {
            GD.PrintErr($"[TerrainGraphEdit] Failed to save graph resource to '{_activeResourcePath}': {err}");
        }
        else
        {
            EmitSignal(SignalName.GraphModified);
        }
    }

    /// <summary>
    /// Handles drag compatibility check for the canvas area.
    /// </summary>
    public override bool _CanDropData(Vector2 position, Variant data)
    {
        GD.Print($"[DEBUG] _CanDropData called! data type: {data.VariantType}");
        if (data.VariantType == Variant.Type.Dictionary)
        {
            var dict = data.AsGodotDictionary();
            bool hasKey = dict.ContainsKey("terrain_node_type");
            GD.Print($"[DEBUG] _CanDropData dict has terrain_node_type: {hasKey}");
            return hasKey;
        }
        GD.Print("[DEBUG] _CanDropData returning FALSE - not a dictionary");
        return false;
    }

    /// <summary>
    /// Spawns a new node when dropped onto the canvas workspace.
    /// </summary>
    public override void _DropData(Vector2 position, Variant data)
    {
        GD.Print($"[DEBUG] _DropData called! graphResource null? {_graphResource == null}");
        if (_graphResource == null)
        {
            _graphResource = new TerrainGraphResource();
            _activeResourcePath = "res://default_terrain_graph.tres";
            GD.Print("[TerrainGraphEdit] Created default empty graph inside _DropData");
        }

        var dict = data.AsGodotDictionary();
        if (dict.TryGetValue("terrain_node_type", out Variant nodeTypeVar))
        {
            string nodeType = nodeTypeVar.AsString();
            
            // Map viewport position to canvas-relative coordinates
            Vector2 canvasPos = (position + ScrollOffset) / Zoom;

            SpawnNode(nodeType, canvasPos);
        }
    }

    /// <summary>
    /// Helper that instantiates a node resource and visual block, adds it to the graph, and triggers a save.
    /// </summary>
    private void SpawnNode(string nodeType, Vector2 canvasPos)
    {
        try
        {
            if (_graphResource == null)
            {
                _graphResource = new TerrainGraphResource();
                _activeResourcePath = "res://default_terrain_graph.tres";
                GD.Print("[TerrainGraphEdit] Created default empty graph inside SpawnNode");
            }

            // 1. Create backing resource
            TerrainNodeResource nodeResource = CreateNodeResourceInstance(nodeType);
            nodeResource.NodeId = Guid.NewGuid().ToString("N");
            nodeResource.EditorPosition = canvasPos;

            // 2. Create runtime equivalent to evaluate slot signatures
            TerrainNode runtimeNode = GraphEvaluator.CreateNodeInstance(nodeType);
            runtimeNode.NodeId = nodeResource.NodeId;
            
            var prop = runtimeNode.GetType().GetProperty("AssociatedResource");
            if (prop != null && prop.CanWrite)
            {
                prop.SetValue(runtimeNode, nodeResource);
            }

            var onResourceSetMethod = runtimeNode.GetType().GetMethod("OnResourceSet");
            if (onResourceSetMethod != null)
            {
                onResourceSetMethod.Invoke(runtimeNode, null);
            }

            // 3. Add resource to active Graph
            _graphResource.Nodes.Add(nodeResource);

            // 4. Create and initialize visual node
            TerrainGraphNode visualNode = new TerrainGraphNode();
            AddChild(visualNode);
            visualNode.Initialize(nodeResource, runtimeNode);

            // Connect visual interaction signals
            visualNode.NodeDragged += OnVisualNodeDragged;
            visualNode.NodeCloseRequested += OnVisualNodeCloseRequested;
            visualNode.NodeSelectedEvent += OnVisualNodeSelected;

            // Save adjustments immediately
            SaveGraph();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Exception spawning node of type '{nodeType}': {ex.Message}");
        }
    }

    private static readonly Dictionary<string, string> _scriptPathCache = new();

    private static string GetScriptPath(string resourceTypeName)
    {
        if (_scriptPathCache.TryGetValue(resourceTypeName, out string cachedPath))
        {
            return cachedPath;
        }

        string foundPath = SearchScriptPathRecursive("res://addons/simplex_terrain", resourceTypeName);
        if (foundPath != null)
        {
            _scriptPathCache[resourceTypeName] = foundPath;
            return foundPath;
        }
        return null;
    }

    private static string SearchScriptPathRecursive(string dirPath, string targetClass)
    {
        using var dir = DirAccess.Open(dirPath);
        if (dir == null) return null;

        dir.ListDirBegin();
        string fileName = dir.GetNext();
        while (fileName != "")
        {
            if (dir.CurrentIsDir())
            {
                if (fileName != "." && fileName != "..")
                {
                    string res = SearchScriptPathRecursive(dirPath.PathJoin(fileName), targetClass);
                    if (res != null) return res;
                }
            }
            else if (fileName.EndsWith(".cs"))
            {
                string filePath = dirPath.PathJoin(fileName);
                using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
                if (file != null)
                {
                    string content = file.GetAsText();
                    if (content.Contains($"class {targetClass}"))
                    {
                        return filePath;
                    }
                }
            }
            fileName = dir.GetNext();
        }
        return null;
    }

    private Resource CreateResourceByName(string resourceTypeName)
    {
        string scriptPath = GetScriptPath(resourceTypeName);
        if (string.IsNullOrEmpty(scriptPath))
        {
            throw new Exception($"Could not locate script path for {resourceTypeName}");
        }

        var script = GD.Load<CSharpScript>(scriptPath);
        if (script == null)
        {
            throw new Exception($"Failed to load script: {scriptPath}");
        }

        Variant instance = script.New();
        return instance.As<Resource>();
    }

    /// <summary>
    /// Creates a concrete parameter resource instance associated with a node type name using reflection.
    /// </summary>
    private TerrainNodeResource CreateNodeResourceInstance(string nodeType)
    {
        string resourceTypeName = nodeType + "Resource";
        try
        {
            Resource res = CreateResourceByName(resourceTypeName);
            if (res is TerrainNodeResource nodeRes)
            {
                nodeRes.NodeType = nodeType;
                GD.Print($"[TerrainGraphEdit] Successfully created resource instance for '{resourceTypeName}' using Script.New()");
                return nodeRes;
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Failed to create node resource '{resourceTypeName}' via Script.New(): {ex.Message}");
        }

        // Fallback to old behavior if script instantiation fails
        GD.PrintErr($"[TerrainGraphEdit] Warning: Falling back to base TerrainNodeResource for '{resourceTypeName}'");
        var fallback = new TerrainNodeResource();
        fallback.NodeType = nodeType;
        return fallback;
    }

    private void OnConnectionRequest(StringName fromNodeName, long fromPort, StringName toNodeName, long toPort)
    {
        if (_graphResource == null) return;

        // Locate visual nodes
        var fromNode = GetNodeOrNull<TerrainGraphNode>(fromNodeName.ToString());
        var toNode = GetNodeOrNull<TerrainGraphNode>(toNodeName.ToString());

        if (fromNode == null || toNode == null)
        {
            return;
        }

        // Retrieve port details
        PortType fromPortType = fromNode.RuntimeNode.Outputs[(int)fromPort].Type;
        PortType toPortType = toNode.RuntimeNode.Inputs[(int)toPort].Type;

        // 1. Validate type compatibility
        if (!PortConnector.ArePortsCompatible(fromPortType, toPortType))
        {
            GD.PrintErr($"[TerrainGraphEdit] Connection Rejected: Port types are incompatible ({fromPortType} -> {toPortType}).");
            return;
        }

        // 2. Validate cycle prevention
        if (PortConnector.WouldCreateCycle(_graphResource, fromNode.NodeResource.NodeId, toNode.NodeResource.NodeId))
        {
            GD.PrintErr("[TerrainGraphEdit] Connection Rejected: Loop/Cycle detected in topological validation check.");
            return;
        }

        // 3. Clear any existing connections on the target input port (single input per input port limit)
        DisconnectTargetInputPort(toNodeName, (int)toPort);

        // 4. Connect visual elements
        ConnectNode(fromNodeName, (int)fromPort, toNodeName, (int)toPort);

        // 5. Add to serialized resource connections list
        ConnectionData conn;
        try
        {
            conn = CreateResourceByName("ConnectionData") as ConnectionData;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Failed to create ConnectionData via Script.New(): {ex.Message}");
            conn = new ConnectionData();
        }
        conn.FromNodeId = fromNode.NodeResource.NodeId;
        conn.FromPort = (int)fromPort;
        conn.ToNodeId = toNode.NodeResource.NodeId;
        conn.ToPort = (int)toPort;
        _graphResource.Connections.Add(conn);

        // 6. Save modifications
        SaveGraph();
    }

    private void OnDisconnectionRequest(StringName fromNodeName, long fromPort, StringName toNodeName, long toPort)
    {
        if (_graphResource == null) return;

        var fromNode = GetNodeOrNull<TerrainGraphNode>(fromNodeName.ToString());
        var toNode = GetNodeOrNull<TerrainGraphNode>(toNodeName.ToString());

        if (fromNode == null || toNode == null) return;

        // 1. Disconnect visual elements
        DisconnectNode(fromNodeName, (int)fromPort, toNodeName, (int)toPort);

        // 2. Remove connection from serialized resources
        for (int i = 0; i < _graphResource.Connections.Count; i++)
        {
            var conn = _graphResource.Connections[i];
            if (conn != null &&
                conn.FromNodeId == fromNode.NodeResource.NodeId && conn.FromPort == fromPort &&
                conn.ToNodeId == toNode.NodeResource.NodeId && conn.ToPort == toPort)
            {
                _graphResource.Connections.RemoveAt(i);
                break;
            }
        }

        // 3. Save modifications
        SaveGraph();
    }

    private void DisconnectTargetInputPort(string toNodeName, int toPortIndex)
    {
        var toNode = GetNodeOrNull<TerrainGraphNode>(toNodeName);
        if (toNode == null) return;

        // Loop through current connection map in GraphEdit to disconnect visually
        foreach (var connection in GetConnectionList())
        {
            string from = GetDictString(connection, "from_node");
            int fromPort = GetDictInt(connection, "from_port");
            string to = GetDictString(connection, "to_node");
            int toPort = GetDictInt(connection, "to_port");

            if (to == toNodeName && toPort == toPortIndex)
            {
                GD.Print($"[TerrainGraphEdit] Disconnecting target input port visually: {from}:{fromPort} -> {to}:{toPort}");
                DisconnectNode(from, fromPort, to, toPort);
                break;
            }
        }

        // Remove from resource connections list
        for (int i = 0; i < _graphResource.Connections.Count; i++)
        {
            var conn = _graphResource.Connections[i];
            if (conn != null && conn.ToNodeId == toNode.NodeResource.NodeId && conn.ToPort == toPortIndex)
            {
                _graphResource.Connections.RemoveAt(i);
                break;
            }
        }
    }

    private void OnVisualNodeDragged(TerrainGraphNode visualNode, Vector2 newPos)
    {
        // Visual nodes update their backing EditorPosition resource automatically
        // Periodically save or trigger save when they finish
        SaveGraph();
    }

    private void OnVisualNodeCloseRequested(TerrainGraphNode visualNode)
    {
        if (_graphResource == null) return;

        string nodeId = visualNode.NodeResource.NodeId;
        string nodeName = visualNode.Name;

        // 1. Remove all connection lines and references connected to this node
        var connectionsToRemove = new List<Godot.Collections.Dictionary>();
        foreach (var conn in GetConnectionList())
        {
            string from = GetDictString(conn, "from_node");
            string to = GetDictString(conn, "to_node");

            if (from == nodeName || to == nodeName)
            {
                connectionsToRemove.Add(conn);
            }
        }

        foreach (var conn in connectionsToRemove)
        {
            string from = GetDictString(conn, "from_node");
            int fromPort = GetDictInt(conn, "from_port");
            string to = GetDictString(conn, "to_node");
            int toPort = GetDictInt(conn, "to_port");

            DisconnectNode(from, fromPort, to, toPort);
        }

        // Remove connection resources
        for (int i = _graphResource.Connections.Count - 1; i >= 0; i--)
        {
            var conn = _graphResource.Connections[i];
            if (conn != null && (conn.FromNodeId == nodeId || conn.ToNodeId == nodeId))
            {
                _graphResource.Connections.RemoveAt(i);
            }
        }

        // 2. Remove backing resource from graph
        for (int i = 0; i < _graphResource.Nodes.Count; i++)
        {
            if (_graphResource.Nodes[i]?.NodeId == nodeId)
            {
                _graphResource.Nodes.RemoveAt(i);
                break;
            }
        }

        // 3. Remove visual node child
        visualNode.NodeDragged -= OnVisualNodeDragged;
        visualNode.NodeCloseRequested -= OnVisualNodeCloseRequested;
        visualNode.NodeSelectedEvent -= OnVisualNodeSelected;

        RemoveChild(visualNode);
        visualNode.QueueFree();

        // 4. Save modifications
        SaveGraph();
    }

    private void OnVisualNodeSelected(TerrainGraphNode visualNode)
    {
        if (visualNode != null && visualNode.NodeResource != null)
        {
            EmitSignal(SignalName.TerrainNodeSelected, visualNode.NodeResource);
        }
    }

    private void OnVisualFrameCloseRequested(TerrainGraphFrame visualFrame)
    {
        if (_graphResource == null || visualFrame == null) return;
        _graphResource.Frames.Remove(visualFrame.Resource);
        visualFrame.NodeCloseRequested -= OnVisualFrameCloseRequested;
        visualFrame.FrameDragged -= OnVisualFrameDragged;
        RemoveChild(visualFrame);
        visualFrame.QueueFree();
        SaveGraph();
    }

    private void OnVisualFrameDragged(TerrainGraphFrame visualFrame)
    {
        SaveGraph();
    }

    private void OnVisualCommentCloseRequested(TerrainGraphComment visualComment)
    {
        if (_graphResource == null || visualComment == null) return;
        _graphResource.Comments.Remove(visualComment.Resource);
        visualComment.NodeCloseRequested -= OnVisualCommentCloseRequested;
        visualComment.CommentModified -= OnVisualCommentModified;
        RemoveChild(visualComment);
        visualComment.QueueFree();
        SaveGraph();
    }

    private void OnVisualCommentModified(TerrainGraphComment visualComment)
    {
        SaveGraph();
    }

    private void SpawnFrame(Vector2 canvasPos)
    {
        if (_graphResource == null) return;
        GraphFrameData frameData;
        try
        {
            frameData = CreateResourceByName("GraphFrameData") as GraphFrameData;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Failed to create GraphFrameData via Script.New(): {ex.Message}");
            frameData = new GraphFrameData();
        }
        frameData.Position = canvasPos;
        _graphResource.Frames.Add(frameData);

        TerrainGraphFrame visualFrame = new TerrainGraphFrame();
        AddChild(visualFrame);
        visualFrame.Initialize(frameData);
        visualFrame.NodeCloseRequested += OnVisualFrameCloseRequested;
        visualFrame.FrameDragged += OnVisualFrameDragged;

        SaveGraph();
    }

    private void SpawnComment(Vector2 canvasPos)
    {
        if (_graphResource == null) return;
        GraphCommentData commentData;
        try
        {
            commentData = CreateResourceByName("GraphCommentData") as GraphCommentData;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEdit] Failed to create GraphCommentData via Script.New(): {ex.Message}");
            commentData = new GraphCommentData();
        }
        commentData.Position = canvasPos;
        _graphResource.Comments.Add(commentData);

        TerrainGraphComment visualComment = new TerrainGraphComment();
        AddChild(visualComment);
        visualComment.Initialize(commentData);
        visualComment.NodeCloseRequested += OnVisualCommentCloseRequested;
        visualComment.CommentModified += OnVisualCommentModified;

        SaveGraph();
    }

    private string GetDictString(Godot.Collections.Dictionary dict, string key)
    {
        if (dict == null) return string.Empty;
        if (dict.ContainsKey(key))
        {
            return dict[key].AsString();
        }
        var sn = new StringName(key);
        if (dict.ContainsKey(sn))
        {
            return dict[sn].AsString();
        }
        return string.Empty;
    }

    private int GetDictInt(Godot.Collections.Dictionary dict, string key)
    {
        if (dict == null) return 0;
        if (dict.ContainsKey(key))
        {
            return dict[key].AsInt32();
        }
        var sn = new StringName(key);
        if (dict.ContainsKey(sn))
        {
            return dict[sn].AsInt32();
        }
        return 0;
    }
}
