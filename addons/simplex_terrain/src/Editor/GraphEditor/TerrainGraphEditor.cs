#if TOOLS
using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

/// <summary>
/// Custom palette item representing a node type that can be dragged onto the canvas.
/// Overrides _GetDragData to serialize drag information and supply a visual drag preview.
/// </summary>
[Tool]
public partial class PaletteItem : Label
{
    private string _nodeType;

    /// <summary>
    /// Parameterless constructor required by Godot for hot-reload reconstruction.
    /// </summary>
    public PaletteItem() { }

    public PaletteItem(string displayName, string nodeType, Color categoryColor)
    {
        Text = displayName;
        _nodeType = nodeType;
        HorizontalAlignment = HorizontalAlignment.Left;
        CustomMinimumSize = new Vector2(160, 26);
        MouseFilter = MouseFilterEnum.Stop;
        
        // Premium modern look with subtle sidebar accents
        var bg = new StyleBoxFlat();
        bg.BgColor = new Color(0.12f, 0.12f, 0.14f, 0.6f);
        bg.BorderWidthLeft = 3;
        bg.BorderColor = categoryColor;
        bg.ContentMarginLeft = 8;
        bg.ContentMarginRight = 8;
        bg.ContentMarginTop = 5;
        bg.ContentMarginBottom = 5;
        bg.CornerRadiusTopLeft = 2;
        bg.CornerRadiusTopRight = 2;
        bg.CornerRadiusBottomLeft = 2;
        bg.CornerRadiusBottomRight = 2;
        AddThemeStyleboxOverride("normal", bg);
        
        AddThemeFontSizeOverride("font_size", 11);
        AddThemeColorOverride("font_color", new Color(0.9f, 0.9f, 0.9f));
    }

    public override Variant _GetDragData(Vector2 atPosition)
    {
        var data = new Godot.Collections.Dictionary();
        data["terrain_node_type"] = _nodeType;

        var preview = new Label();
        preview.Text = Text;
        
        var previewBg = new StyleBoxFlat();
        previewBg.BgColor = new Color(0.08f, 0.08f, 0.1f, 0.9f);
        previewBg.BorderWidthLeft = 3;
        previewBg.BorderColor = new Color(1, 1, 1, 0.7f);
        previewBg.ContentMarginLeft = 10;
        previewBg.ContentMarginRight = 10;
        previewBg.ContentMarginTop = 6;
        previewBg.ContentMarginBottom = 6;
        previewBg.CornerRadiusTopLeft = 3;
        previewBg.CornerRadiusTopRight = 3;
        previewBg.CornerRadiusBottomLeft = 3;
        previewBg.CornerRadiusBottomRight = 3;
        
        preview.AddThemeStyleboxOverride("normal", previewBg);
        preview.AddThemeFontSizeOverride("font_size", 12);
        
        SetDragPreview(preview);

        return data;
    }
}

/// <summary>
/// Main bottom dock panel for editing the SimpleXTerrain visual node graph.
/// Wraps the custom canvas and the categorized node palette side-by-side.
/// </summary>
[Tool]
#pragma warning disable CS0618
public partial class TerrainGraphEditor : Control
{
    private HSplitContainer _split;
    private PanelContainer _sidebar;
    private VBoxContainer _paletteList;
    private VBoxContainer _canvasContainer;
    private Button _toggleSidebarBtn;
    private Button _saveBtn;
    private Button _pinBoardBtn;

    private Button _paintToolBtn;
    private HBoxContainer _brushSettingsContainer;
    private OptionButton _brushTypeOpt;
    private SpinBox _brushRadiusSpin;
    private SpinBox _brushStrengthSpin;
    private SpinBox _brushSpacingSpin;

    public bool PaintModeEnabled => (_paintToolBtn != null && GodotObject.IsInstanceValid(_paintToolBtn)) ? _paintToolBtn.ButtonPressed : false;
    public string BrushType => (_brushTypeOpt != null && GodotObject.IsInstanceValid(_brushTypeOpt)) ? _brushTypeOpt.GetItemText(_brushTypeOpt.Selected) : "Raise";
    public float BrushRadius => (float)((_brushRadiusSpin != null && GodotObject.IsInstanceValid(_brushRadiusSpin)) ? _brushRadiusSpin.Value : 20.0);
    public float BrushStrength => (float)((_brushStrengthSpin != null && GodotObject.IsInstanceValid(_brushStrengthSpin)) ? _brushStrengthSpin.Value : 1.0);
    public float BrushSpacing => (float)((_brushSpacingSpin != null && GodotObject.IsInstanceValid(_brushSpacingSpin)) ? _brushSpacingSpin.Value : 0.1);
    public bool IsRemovedFromBottomPanel { get; set; } = false;
    
    private TerrainManager _activeManager;
    private PinBoardPanel _pinBoardPanel;
    private ProceduralTerrainPlugin _plugin;
    private bool _isCleanedUp = false;

    public TerrainGraphEditor()
    {
    }

    public TerrainGraphEditor(ProceduralTerrainPlugin plugin)
    {
        _plugin = plugin;
    }

    /// <summary>
    /// Sets the active TerrainManager instance.
    /// </summary>
    public void SetActiveManager(TerrainManager manager)
    {
        _activeManager = manager;
    }

    /// <summary>
    /// Gets the custom canvas edit area.
    /// </summary>
    public TerrainGraphEdit Canvas { get; private set; }

    /// <summary>
    /// Signal forwarded when the canvas registers a node selection event.
    /// </summary>
    public event Action<TerrainNodeResource> NodeSelected;

    /// <summary>
    /// Event emitted when the graph is saved or modified.
    /// </summary>
    public event Action GraphModified;

    public override void _Ready()
    {
        try
        {
            // Make this control fill the bottom panel
            SetAnchorsPreset(LayoutPreset.FullRect);
            SetOffsetsPreset(LayoutPreset.FullRect);
            CustomMinimumSize = new Vector2(0, 300);

            // 1. Build split layout programmatically
            SizeFlagsHorizontal = SizeFlags.ExpandFill;
            SizeFlagsVertical = SizeFlags.ExpandFill;

            _split = new HSplitContainer();
            _split.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            _split.SizeFlagsVertical = SizeFlags.ExpandFill;
            _split.SetAnchorsPreset(LayoutPreset.FullRect);
            _split.SetOffsetsPreset(LayoutPreset.FullRect);
            _split.SplitOffset = 240; // palette sidebar width
            AddChild(_split);

            // 2. Build Sidebar Palette
            _sidebar = new PanelContainer();
            _sidebar.CustomMinimumSize = new Vector2(240, 0);
            _sidebar.SizeFlagsHorizontal = SizeFlags.Fill;
            _sidebar.SizeFlagsVertical = SizeFlags.ExpandFill;
            
            var sidebarStyle = new StyleBoxFlat();
            sidebarStyle.BgColor = new Color(0.08f, 0.08f, 0.09f, 1f); // Sleek dark slate sidebar
            sidebarStyle.BorderWidthRight = 1;
            sidebarStyle.BorderColor = new Color(0.18f, 0.18f, 0.2f, 1f);
            sidebarStyle.ContentMarginLeft = 8;
            sidebarStyle.ContentMarginRight = 8;
            sidebarStyle.ContentMarginTop = 8;
            sidebarStyle.ContentMarginBottom = 8;
            _sidebar.AddThemeStyleboxOverride("panel", sidebarStyle);
            _split.AddChild(_sidebar);

            var scroll = new ScrollContainer();
            scroll.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            scroll.SizeFlagsVertical = SizeFlags.ExpandFill;
            scroll.HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled;
            _sidebar.AddChild(scroll);

            _paletteList = new VBoxContainer();
            _paletteList.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            _paletteList.SizeFlagsVertical = SizeFlags.ExpandFill;
            _paletteList.AddThemeConstantOverride("separation", 6);
            scroll.AddChild(_paletteList);

            // 3. Build Canvas Container and Canvas Edit
            _canvasContainer = new VBoxContainer();
            _canvasContainer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            _canvasContainer.SizeFlagsVertical = SizeFlags.ExpandFill;
            _canvasContainer.AddThemeConstantOverride("separation", 0);
            _split.AddChild(_canvasContainer);

            // Top toolbar
            var toolbar = new HBoxContainer();
            toolbar.CustomMinimumSize = new Vector2(0, 32);
            toolbar.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            
            var toolbarStyle = new StyleBoxFlat();
            toolbarStyle.BgColor = new Color(0.1f, 0.1f, 0.11f, 1f);
            toolbarStyle.BorderWidthBottom = 1;
            toolbarStyle.BorderColor = new Color(0.18f, 0.18f, 0.2f, 1f);
            toolbarStyle.ContentMarginLeft = 12;
            toolbarStyle.ContentMarginRight = 12;
            toolbarStyle.ContentMarginTop = 4;
            toolbarStyle.ContentMarginBottom = 4;
            toolbar.AddThemeStyleboxOverride("panel", toolbarStyle);
            _canvasContainer.AddChild(toolbar);

            var toolbarTitle = new Label();
            toolbarTitle.Text = "Terrain Node Graph Canvas";
            toolbarTitle.AddThemeFontSizeOverride("font_size", 12);
            toolbarTitle.AddThemeColorOverride("font_color", new Color(0.85f, 0.85f, 0.9f));
            toolbar.AddChild(toolbarTitle);

            var spacer = new Control();
            spacer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            toolbar.AddChild(spacer);

            _toggleSidebarBtn = new Button();
            _toggleSidebarBtn.Text = "Hide Sidebar";
            _toggleSidebarBtn.Flat = true;
            _toggleSidebarBtn.Pressed += OnToggleSidebarPressed;
            toolbar.AddChild(_toggleSidebarBtn);

            // Paint Brush Toggle Button
            _paintToolBtn = new Button();
            _paintToolBtn.Text = "Paint Tool";
            _paintToolBtn.ToggleMode = true;
            _paintToolBtn.Flat = true;
            _paintToolBtn.Toggled += OnPaintToolToggled;
            toolbar.AddChild(_paintToolBtn);

            // Brush Settings Container (collapsible)
            _brushSettingsContainer = new HBoxContainer();
            _brushSettingsContainer.Visible = false;
            _brushSettingsContainer.AddThemeConstantOverride("separation", 8);
            toolbar.AddChild(_brushSettingsContainer);

            // Brush Type label & option
            var typeLabel = new Label();
            typeLabel.Text = "Type:";
            typeLabel.AddThemeFontSizeOverride("font_size", 11);
            _brushSettingsContainer.AddChild(typeLabel);

            _brushTypeOpt = new OptionButton();
            _brushTypeOpt.AddItem("Raise");
            _brushTypeOpt.AddItem("Lower");
            _brushTypeOpt.AddItem("Flatten");
            _brushTypeOpt.AddItem("Smooth");
            _brushTypeOpt.Selected = 0;
            _brushTypeOpt.AddThemeFontSizeOverride("font_size", 11);
            _brushSettingsContainer.AddChild(_brushTypeOpt);

            // Brush Radius label & spinbox
            var radiusLabel = new Label();
            radiusLabel.Text = "Radius:";
            radiusLabel.AddThemeFontSizeOverride("font_size", 11);
            _brushSettingsContainer.AddChild(radiusLabel);

            _brushRadiusSpin = new SpinBox();
            _brushRadiusSpin.MinValue = 1.0;
            _brushRadiusSpin.MaxValue = 150.0;
            _brushRadiusSpin.Value = 20.0;
            _brushRadiusSpin.Step = 1.0;
            _brushRadiusSpin.CustomMinimumSize = new Vector2(70, 0);
            _brushSettingsContainer.AddChild(_brushRadiusSpin);

            // Brush Strength label & spinbox
            var strengthLabel = new Label();
            strengthLabel.Text = "Strength:";
            strengthLabel.AddThemeFontSizeOverride("font_size", 11);
            _brushSettingsContainer.AddChild(strengthLabel);

            _brushStrengthSpin = new SpinBox();
            _brushStrengthSpin.MinValue = 0.05;
            _brushStrengthSpin.MaxValue = 20.0;
            _brushStrengthSpin.Value = 1.0;
            _brushStrengthSpin.Step = 0.05;
            _brushStrengthSpin.CustomMinimumSize = new Vector2(70, 0);
            _brushSettingsContainer.AddChild(_brushStrengthSpin);

            // Brush Spacing label & spinbox
            var spacingLabel = new Label();
            spacingLabel.Text = "Spacing:";
            spacingLabel.AddThemeFontSizeOverride("font_size", 11);
            _brushSettingsContainer.AddChild(spacingLabel);

            _brushSpacingSpin = new SpinBox();
            _brushSpacingSpin.MinValue = 0.02;
            _brushSpacingSpin.MaxValue = 0.5;
            _brushSpacingSpin.Value = 0.1;
            _brushSpacingSpin.Step = 0.01;
            _brushSpacingSpin.CustomMinimumSize = new Vector2(70, 0);
            _brushSettingsContainer.AddChild(_brushSpacingSpin);

            _saveBtn = new Button();
            _saveBtn.Text = "Force Save Graph";
            _saveBtn.Flat = true;
            _saveBtn.Pressed += OnSavePressed;
            toolbar.AddChild(_saveBtn);

            _pinBoardBtn = new Button();
            _pinBoardBtn.Text = "Pin Board";
            _pinBoardBtn.Flat = true;
            _pinBoardBtn.Pressed += OnPinBoardPressed;
            toolbar.AddChild(_pinBoardBtn);

            // Workspace canvas instance
            Canvas = new TerrainGraphEdit();
            _canvasContainer.AddChild(Canvas);

            // Connect Canvas signals
            Canvas.TerrainNodeSelected += OnCanvasNodeSelected;
            Canvas.GraphModified += OnCanvasGraphModified;

            // Instantiate PinBoardPanel overlay
            _pinBoardPanel = new PinBoardPanel();
            _pinBoardPanel.Visible = false;
            AddChild(_pinBoardPanel);

            // Populate categorized palette items
            PopulatePalette();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainGraphEditor] Error in _Ready(): {ex}");
        }
    }

    /// <summary>
    /// Loads a serialized graph resource into the canvas.
    /// </summary>
    /// <param name="graphResource">The graph resource.</param>
    /// <param name="path">The resource save path.</param>
    public void LoadGraph(TerrainGraphResource graphResource, string path)
    {
        Canvas?.LoadGraph(graphResource, path);
    }

    private void PopulatePalette()
    {
        // Category 1: Generators
        AddCategoryHeader("Generators", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Perlin Noise", "PerlinNoiseNode", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Fractal Noise", "FractalNode", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Voronoi Cellular", "VoronoiNode", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Constant Scalar", "DummyConstantNode", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Primitive Form", "PrimitiveFormNode", new Color(0.15f, 0.4f, 0.8f));
        AddPaletteNode("Radial Spot", "SpotNode", new Color(0.15f, 0.4f, 0.8f));

        // Category 2: Modifiers
        AddCategoryHeader("Modifiers", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Levels & Contrast", "LevelsNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("LUT Curve", "CurveNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Blend Combiner", "BlendNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Slope Selector", "SlopeNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Binomial Blur", "BlurNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Discrete Laplacian", "CavityNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Smooth Terrace", "TerraceNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Hermite Ledge", "LedgeNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Shoreline Beach", "BeachNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Moore Soil Erosion", "ErosionNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Aspect Shading", "AspectMapperNode", new Color(0.5f, 0.2f, 0.8f));
        AddPaletteNode("Parallax Displacement", "ParallaxDisplacementNode", new Color(0.5f, 0.2f, 0.8f));

        // Category 3: Splatting
        AddCategoryHeader("Splatting", new Color(1.0f, 0.4f, 0.2f));
        AddPaletteNode("Unified Splatmap", "SplatNode", new Color(1.0f, 0.4f, 0.2f));
        AddPaletteNode("Texture Input", "TextureInputNode", new Color(1.0f, 0.4f, 0.2f));

        // Category 4: Object Scatter
        AddCategoryHeader("Object Scatter", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Mitchell Scatter", "ScatterNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Terrain Snap & Normal", "TerrainSnapNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Stochastic Prune", "PruneNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Exclusion Proximity", "ProximityDecimationNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Local Excavator", "ExcavationNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Radial Dispersal", "RadialDispersalNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Cellular Forest Sim", "ForestSimulationNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Particle Slide", "ParticleSlidingNode", new Color(0.9f, 0.45f, 0.1f));
        AddPaletteNode("Foliage Density", "FoliageDensityNode", new Color(0.9f, 0.45f, 0.1f));

        // Category 5: Splines
        AddCategoryHeader("Splines & Pathfinding", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Scene Path3D Input", "SplineInputNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Spline Stroke Field", "SplineStrokeNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Road Conform Blend", "SplineConformNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("De Casteljau Subdiv", "SplineSubdivideNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Heron Prune Optimize", "SplineOptimizeNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Midpoint Relax Smooth", "SplineRelaxNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Proximity Weld Close", "SplineWeldCloseNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Dijkstra Road Finder", "DijkstraPathNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Gabriel Interlink", "GabrielGraphNode", new Color(0.1f, 0.5f, 0.6f));
        AddPaletteNode("Spline AABB Clip", "SplineClipNode", new Color(0.1f, 0.5f, 0.6f));

        // Category: Portals & Loops
        AddCategoryHeader("Portals & Loops", new Color(0.7f, 0.3f, 0.7f));
        AddPaletteNode("Portal Transmitter", "PortalTransmitterNode", new Color(0.7f, 0.3f, 0.7f));
        AddPaletteNode("Portal Receiver", "PortalReceiverNode", new Color(0.7f, 0.3f, 0.7f));
        AddPaletteNode("Loop Sub-Graph", "LoopNode", new Color(0.7f, 0.3f, 0.7f));
        AddPaletteNode("Loop Input", "LoopInputNode", new Color(0.7f, 0.3f, 0.7f));
        AddPaletteNode("Loop Output", "LoopOutputNode", new Color(0.7f, 0.3f, 0.7f));

        // Category 6: Biomes
        AddCategoryHeader("Biomes", new Color(0.1f, 0.6f, 0.3f));
        AddPaletteNode("Biome Sub-Graph Ref", "BiomeReferenceNode", new Color(0.1f, 0.6f, 0.3f));
        AddPaletteNode("Unified Biome Blend", "BiomeBlendNode", new Color(0.1f, 0.6f, 0.3f));
        AddPaletteNode("Whittaker 2D Lookup", "WhittakerLookupNode", new Color(0.1f, 0.6f, 0.3f));

        // Category: Geomorphology
        AddCategoryHeader("Geomorphology", new Color(0.2f, 0.5f, 0.5f));
        AddPaletteNode("Island Masking", "IslandMaskNode", new Color(0.2f, 0.5f, 0.5f));
        AddPaletteNode("Ocean Water Level", "OceanLevelNode", new Color(0.2f, 0.5f, 0.5f));
        AddPaletteNode("Lake Bed Excavator", "LakeExcavatorNode", new Color(0.2f, 0.5f, 0.5f));
        AddPaletteNode("River Channel Generator", "RiverGeneratorNode", new Color(0.2f, 0.5f, 0.5f));

        // Category 7: Outputs
        AddCategoryHeader("Outputs", new Color(0.8f, 0.15f, 0.15f));
        AddPaletteNode("Terrain3D Height", "HeightOutputNode", new Color(0.8f, 0.15f, 0.15f));
        AddPaletteNode("Terrain3D ControlMap", "Terrain3DControlOutputNode", new Color(0.8f, 0.15f, 0.15f));
        AddPaletteNode("Terrain3D Instancer", "Terrain3DInstancerOutputNode", new Color(0.8f, 0.15f, 0.15f));
        AddPaletteNode("Heightmap Exporter", "HeightmapExportNode", new Color(0.8f, 0.15f, 0.15f));
    }

    private void OnToggleSidebarPressed()
    {
        if (_sidebar != null && _toggleSidebarBtn != null)
        {
            _sidebar.Visible = !_sidebar.Visible;
            _toggleSidebarBtn.Text = _sidebar.Visible ? "Hide Sidebar" : "Show Sidebar";
        }
    }

    private void OnPaintToolToggled(bool buttonPressed)
    {
        if (_brushSettingsContainer != null)
        {
            _brushSettingsContainer.Visible = buttonPressed;
        }
    }

    private void AddCategoryHeader(string name, Color accentColor)
    {
        var wrapper = new PanelContainer();
        wrapper.CustomMinimumSize = new Vector2(0, 24);
        wrapper.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        
        var bg = new StyleBoxFlat();
        bg.BgColor = accentColor.Darkened(0.6f);
        bg.ContentMarginLeft = 8;
        bg.ContentMarginRight = 8;
        bg.ContentMarginTop = 3;
        bg.ContentMarginBottom = 3;
        bg.CornerRadiusTopLeft = 2;
        bg.CornerRadiusTopRight = 2;
        wrapper.AddThemeStyleboxOverride("panel", bg);

        var lbl = new Label();
        lbl.Text = name;
        lbl.AddThemeFontSizeOverride("font_size", 10);
        lbl.AddThemeColorOverride("font_color", new Color(1f, 1f, 1f));
        wrapper.AddChild(lbl);

        _paletteList.AddChild(wrapper);
    }

    private void AddPaletteNode(string name, string typeName, Color categoryColor)
    {
        var item = new PaletteItem(name, typeName, categoryColor);
        _paletteList.AddChild(item);
    }

    private void OnCanvasNodeSelected(TerrainNodeResource nodeResource)
    {
        NodeSelected?.Invoke(nodeResource);
    }

    private void OnCanvasGraphModified()
    {
        GraphModified?.Invoke();
    }

    private void OnSavePressed()
    {
        Canvas?.SaveGraph();
    }

    private void OnPinBoardPressed()
    {
        _pinBoardPanel?.Open(_activeManager);
    }

    private void CleanUp(bool isFromDispose)
    {
        if (_isCleanedUp) return;
        _isCleanedUp = true;

        _plugin = null;

        if (_toggleSidebarBtn != null && GodotObject.IsInstanceValid(_toggleSidebarBtn))
        {
            if (_toggleSidebarBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.OnToggleSidebarPressed)))
            {
                try
                {
                    _toggleSidebarBtn.Pressed -= OnToggleSidebarPressed;
                }
                catch { }
            }
        }
        if (_paintToolBtn != null && GodotObject.IsInstanceValid(_paintToolBtn))
        {
            if (_paintToolBtn.IsConnected(BaseButton.SignalName.Toggled, new Callable(this, MethodName.OnPaintToolToggled)))
            {
                try
                {
                    _paintToolBtn.Toggled -= OnPaintToolToggled;
                }
                catch { }
            }
        }
        if (_saveBtn != null && GodotObject.IsInstanceValid(_saveBtn))
        {
            if (_saveBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.OnSavePressed)))
            {
                try
                {
                    _saveBtn.Pressed -= OnSavePressed;
                }
                catch { }
            }
        }
        if (_pinBoardBtn != null && GodotObject.IsInstanceValid(_pinBoardBtn))
        {
            if (_pinBoardBtn.IsConnected(BaseButton.SignalName.Pressed, new Callable(this, MethodName.OnPinBoardPressed)))
            {
                try
                {
                    _pinBoardBtn.Pressed -= OnPinBoardPressed;
                }
                catch { }
            }
        }
        if (Canvas != null && GodotObject.IsInstanceValid(Canvas))
        {
            try
            {
                Canvas.TerrainNodeSelected -= OnCanvasNodeSelected;
                Canvas.GraphModified -= OnCanvasGraphModified;
            }
            catch { }
            try
            {
                Canvas.Dispose();
            }
            catch { }
        }
        if (_pinBoardPanel != null && GodotObject.IsInstanceValid(_pinBoardPanel))
        {
            try
            {
                _pinBoardPanel.Dispose();
            }
            catch { }
        }

        NodeSelected = null;
        GraphModified = null;
        _activeManager = null;
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
}
#pragma warning restore CS0618
#endif
