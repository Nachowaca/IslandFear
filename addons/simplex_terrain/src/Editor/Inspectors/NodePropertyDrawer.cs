#if TOOLS
using Godot;
using System;

namespace SimpleXTerrain;

/// <summary>
/// Custom EditorInspectorPlugin that hooks into the property changes of TerrainNodeResource.
/// When any inspected property changes, it automatically saves the active graph and rebuilds the terrain.
/// </summary>
[Tool]
public partial class NodePropertyDrawer : EditorInspectorPlugin
{
    private Action _onSaveAndRebuild;
    private TerrainNodeResource _inspectedResource;
    private Action _cleanUpDelegate;
    private Action _resourceChangedDelegate;

    private ProceduralTerrainPlugin _plugin;
    public bool IsRemovedFromInspector { get; set; } = false;

    /// <summary>
    /// Parameterless constructor required by Godot.
    /// </summary>
    public NodePropertyDrawer()
    {
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="NodePropertyDrawer"/> class.
    /// </summary>
    /// <param name="plugin">The plugin instance.</param>
    /// <param name="onSaveAndRebuild">Callback triggered when properties of the inspected node change.</param>
    public NodePropertyDrawer(ProceduralTerrainPlugin plugin, Action onSaveAndRebuild)
    {
        _plugin = plugin;
        _onSaveAndRebuild = onSaveAndRebuild;
        _cleanUpDelegate = CleanUpPreviousConnection;
        _resourceChangedDelegate = OnResourceChanged;
        try
        {
            EditorInterface.Singleton.GetInspector().EditedObjectChanged += _cleanUpDelegate;
        }
        catch { }
    }

    public override bool _CanHandle(GodotObject @object)
    {
        return @object is TerrainNodeResource;
    }

    public override void _ParseBegin(GodotObject @object)
    {
        if (@object is TerrainNodeResource nodeResource)
        {
            CleanUpPreviousConnection();

            _inspectedResource = nodeResource;
            try
            {
                if (GodotObject.IsInstanceValid(_inspectedResource) && _resourceChangedDelegate != null)
                {
                    _inspectedResource.Changed += _resourceChangedDelegate;
                }
            }
            catch { }
        }
    }

    private void OnResourceChanged()
    {
        _onSaveAndRebuild?.Invoke();
    }

    private void CleanUpPreviousConnection()
    {
        if (_inspectedResource != null && GodotObject.IsInstanceValid(_inspectedResource))
        {
            try
            {
                if (_resourceChangedDelegate != null)
                {
                    _inspectedResource.Changed -= _resourceChangedDelegate;
                }
            }
            catch { }
        }
        _inspectedResource = null;
    }

    /// <summary>
    /// Explicitly cleans up references and delegate connections to prevent assembly load leaks.
    /// </summary>
    public void CleanUp()
    {
        try
        {
            if (_cleanUpDelegate != null)
            {
                EditorInterface.Singleton.GetInspector().EditedObjectChanged -= _cleanUpDelegate;
            }
        }
        catch { }
        CleanUpPreviousConnection();
        // Release delegate reference to prevent stale assembly references during reload
        _onSaveAndRebuild = null;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _plugin = null;
            CleanUp();
        }
        base.Dispose(disposing);
    }
}
#endif
