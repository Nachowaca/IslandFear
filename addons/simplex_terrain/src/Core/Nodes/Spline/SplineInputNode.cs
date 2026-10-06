using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that reads anchor points from a Godot Path3D scene node and outputs a SplineSet.
/// </summary>
public partial class SplineInputNode : TerrainNode
{
    private readonly object _lock = new();
    private SplineSet _cachedSplineSet;
    private static int _mainThreadId = 0;

    // Tracking variables to detect modifications in the editor
    private GodotObject _lastCurveNode;
    private int _lastPointCount = -1;
    private List<Vector3> _lastPoints = new();
    private List<Vector3> _lastTangentsIn = new();
    private List<Vector3> _lastTangentsOut = new();

    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineInputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Gets or sets a direct spline set to bypass scene tree lookups in unit tests.
    /// </summary>
    public SplineSet DirectSplineSet { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineInputNode"/> class.
    /// </summary>
    public SplineInputNode()
    {
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Clears the cached spline data to force a reload from the scene tree.
    /// </summary>
    public override void ClearCache()
    {
        base.ClearCache();
        lock (_lock)
        {
            _cachedSplineSet = null;
            _lastCurveNode = null;
            _lastPointCount = -1;
            _lastPoints.Clear();
            _lastTangentsIn.Clear();
            _lastTangentsOut.Clear();
        }
    }

    /// <summary>
    /// Loads the spline set from the scene tree and caches it.
    /// MUST be called on the main/UI thread.
    /// </summary>
    public void LoadAndCacheSpline()
    {
        lock (_lock)
        {
            if (_mainThreadId == 0)
            {
                _mainThreadId = System.Environment.CurrentManagedThreadId;
            }

            // In runtime game, once cached, never reload
            if (!Engine.IsEditorHint() && _cachedSplineSet != null)
            {
                return;
            }

            NodePath pathNode = AssociatedResource != null ? AssociatedResource.PathNode : new NodePath("");
            _cachedSplineSet = LoadSplineSetFromScene(pathNode);
        }
    }

    /// <summary>
    /// Evaluates and returns the loaded SplineSet.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        if (DirectSplineSet != null)
        {
            return DirectSplineSet;
        }

        lock (_lock)
        {
            if (_cachedSplineSet != null)
            {
                return _cachedSplineSet;
            }

            NodePath pathNode = AssociatedResource != null ? AssociatedResource.PathNode : new NodePath("");

            // Scene tree lookup is restricted to the main thread
            int currentThreadId = System.Environment.CurrentManagedThreadId;
            if (_mainThreadId != 0 && currentThreadId == _mainThreadId)
            {
                _cachedSplineSet = LoadSplineSetFromScene(pathNode);
            }
            else if (_mainThreadId == 0 && currentThreadId == 1) // Fallback for early startup
            {
                _cachedSplineSet = LoadSplineSetFromScene(pathNode);
            }

            return _cachedSplineSet ?? new SplineSet();
        }
    }

    private SplineSet LoadSplineSetFromScene(NodePath pathNode)
    {
        var splineSet = new SplineSet();
        if (pathNode == null || pathNode.IsEmpty)
        {
            if (_cachedSplineSet == null)
            {
                GD.Print("[SplineInputNode] PathNode is empty or null");
            }
            return splineSet;
        }

        SceneTree tree = Engine.GetMainLoop() as SceneTree;
        if (tree == null)
        {
            if (_cachedSplineSet == null)
            {
                GD.Print("[SplineInputNode] SceneTree is null");
            }
            return splineSet;
        }

        Node node = null;
        if (_lastCurveNode != null && GodotObject.IsInstanceValid(_lastCurveNode))
        {
            node = (Node)_lastCurveNode;
        }
        else
        {
            node = tree.Root.GetNodeOrNull(pathNode);
            if (node == null)
            {
                // Search recursively by name as a fallback
                node = FindNodeByName(tree.Root, pathNode.ToString());
            }
        }

        if (node != null)
        {
            var curveProp = node.GetType().GetProperty("Curve");
            if (curveProp != null)
            {
                object curveObj = curveProp.GetValue(node);
                if (curveObj != null)
                {
                    var pointCountProp = curveObj.GetType().GetProperty("PointCount");
                    var getPointPosMethod = curveObj.GetType().GetMethod("GetPointPosition");
                    var getPointInMethod = curveObj.GetType().GetMethod("GetPointIn");
                    var getPointOutMethod = curveObj.GetType().GetMethod("GetPointOut");

                    if (pointCountProp != null && getPointPosMethod != null)
                    {
                        int ptCount = (int)pointCountProp.GetValue(curveObj);
                        var points = new List<Vector3>();
                        var tangentsIn = new List<Vector3>();
                        var tangentsOut = new List<Vector3>();

                        for (int i = 0; i < ptCount; i++)
                        {
                            Vector3 pos = (Vector3)getPointPosMethod.Invoke(curveObj, new object[] { i });
                            points.Add(pos);

                            if (getPointInMethod != null)
                            {
                                Vector3 tIn = (Vector3)getPointInMethod.Invoke(curveObj, new object[] { i });
                                tangentsIn.Add(tIn);
                            }
                            if (getPointOutMethod != null)
                            {
                                Vector3 tOut = (Vector3)getPointOutMethod.Invoke(curveObj, new object[] { i });
                                tangentsOut.Add(tOut);
                            }
                        }

                        // Check if points or node actually changed since last load
                        bool changed = _cachedSplineSet == null ||
                                       node != _lastCurveNode ||
                                       ptCount != _lastPointCount ||
                                       !AreListsEqual(points, _lastPoints) ||
                                       !AreListsEqual(tangentsIn, _lastTangentsIn) ||
                                       !AreListsEqual(tangentsOut, _lastTangentsOut);

                        if (!changed)
                        {
                            return _cachedSplineSet;
                        }

                        _lastCurveNode = node;
                        _lastPointCount = ptCount;
                        _lastPoints = points;
                        _lastTangentsIn = tangentsIn;
                        _lastTangentsOut = tangentsOut;

                        string nodePathStr = node.IsInsideTree() ? node.GetPath().ToString() : "(not in tree)";
                        GD.Print($"[SplineInputNode] Found node: {node.Name} at path: {nodePathStr}");
                        GD.Print($"[SplineInputNode] Loaded {points.Count} points: {string.Join(", ", points)}");

                        var newSplineSet = new SplineSet();
                        if (points.Count >= 2)
                        {
                            var curve = new SplineCurve(
                                points,
                                CurveType.Open,
                                tangentsOut.Count == points.Count ? tangentsOut : null,
                                tangentsIn.Count == points.Count ? tangentsIn : null
                            );
                            newSplineSet.AddCurve(curve);
                        }
                        return newSplineSet;
                    }
                    else
                    {
                        if (_cachedSplineSet == null) GD.Print("[SplineInputNode] Curve object has no PointCount or GetPointPosition");
                    }
                }
                else
                {
                    if (_cachedSplineSet == null) GD.Print("[SplineInputNode] Curve object is null");
                }
            }
            else
            {
                if (_cachedSplineSet == null) GD.Print("[SplineInputNode] Node has no Curve property");
            }
        }
        else
        {
            if (_cachedSplineSet == null) GD.Print($"[SplineInputNode] Node '{pathNode}' not found in SceneTree from root: {tree.Root.GetPath()}");
        }

        return _cachedSplineSet ?? splineSet;
    }

    private bool AreListsEqual(List<Vector3> a, List<Vector3> b)
    {
        if (a.Count != b.Count) return false;
        for (int i = 0; i < a.Count; i++)
        {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    private Node FindNodeByName(Node parent, string name)
    {
        if (parent == null) return null;
        if (parent.Name == name)
        {
            return parent;
        }

        int childCount = parent.GetChildCount();
        for (int i = 0; i < childCount; i++)
        {
            Node res = FindNodeByName(parent.GetChild(i), name);
            if (res != null) return res;
        }
        return null;
    }
}

#endregion
