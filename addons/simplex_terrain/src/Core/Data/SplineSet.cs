namespace SimpleXTerrain;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// Defines the open or closed loop topology of a spline curve.
/// </summary>
public enum CurveType
{
    /// <summary>
    /// An open curve with distinct starting and ending points.
    /// </summary>
    Open,

    /// <summary>
    /// A closed loop curve where the last point implicitly connects back to the first.
    /// </summary>
    Closed
}

/// <summary>
/// Represents a single spline curve defined by 3D control points and a loop type.
/// </summary>
public struct SplineCurve
{
    /// <summary>
    /// Gets the list of 3D control points for this curve.
    /// </summary>
    public List<Vector3> ControlPoints { get; }

    /// <summary>
    /// Gets the topology type of the curve (Open or Closed).
    /// </summary>
    public CurveType Type { get; }

    /// <summary>
    /// Gets the exact outgoing tangent vectors for the control points, if available.
    /// </summary>
    public List<Vector3> TangentsOut { get; }

    /// <summary>
    /// Gets the exact incoming tangent vectors for the control points, if available.
    /// </summary>
    public List<Vector3> TangentsIn { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineCurve"/> struct.
    /// </summary>
    /// <param name="controlPoints">The list of Vector3 control points.</param>
    /// <param name="type">The curve topology type (Open or Closed).</param>
    /// <param name="tangentsOut">The list of Vector3 outgoing tangent vectors.</param>
    /// <param name="tangentsIn">The list of Vector3 incoming tangent vectors.</param>
    public SplineCurve(List<Vector3> controlPoints, CurveType type, List<Vector3> tangentsOut = null, List<Vector3> tangentsIn = null)
    {
        ControlPoints = controlPoints ?? new List<Vector3>();
        Type = type;
        TangentsOut = tangentsOut;
        TangentsIn = tangentsIn;
    }
}

/// <summary>
/// A collection of spline curves that flow through the node graph, suitable for conforming terrain geometry.
/// </summary>
public class SplineSet
{
    private readonly List<SplineCurve> _curves = new List<SplineCurve>();

    /// <summary>
    /// Gets the read-only list of curves in this set.
    /// </summary>
    public IReadOnlyList<SplineCurve> Curves => _curves;

    /// <summary>
    /// Adds a spline curve to this set.
    /// </summary>
    /// <param name="curve">The spline curve to add.</param>
    public void AddCurve(SplineCurve curve)
    {
        _curves.Add(curve);
    }

    /// <summary>
    /// Gets the total number of spline curves in this set.
    /// </summary>
    /// <returns>The count of spline curves.</returns>
    public int GetCurveCount()
    {
        return _curves.Count;
    }
}
