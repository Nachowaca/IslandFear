using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Enums

/// <summary>
/// Defines the containment boundary mode of the island mask.
/// </summary>
public enum IslandMode
{
    Circular,
    Spline
}

#endregion

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that restricts generated heightfields inside a circular or spline-bounded distance field.
/// </summary>
public partial class IslandMaskNode : TerrainNode
{
    public IslandMaskNodeResource AssociatedResource { get; set; }

    public IslandMaskNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("mask_out", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        IslandMode islandMode = AssociatedResource != null ? AssociatedResource.IslandMode : IslandMode.Circular;
        float centerX = AssociatedResource != null ? AssociatedResource.CenterX : 0.5f;
        float centerZ = AssociatedResource != null ? AssociatedResource.CenterZ : 0.5f;
        float radius = AssociatedResource != null ? AssociatedResource.Radius : 256.0f;
        float falloff = AssociatedResource != null ? AssociatedResource.Falloff : 128.0f;
        Curve falloffCurve = AssociatedResource != null ? AssociatedResource.FalloffCurve : null;

        // Fetch inputs
        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        SplineSet splineSet = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            splineSet = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplineSet;
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        HeightMatrix mask = ctx.AllocateHeightMatrix();

        // 1. Prepare Spline polygons and tangent data if in Spline Mode
        var polygons = new List<List<Vector3>>();
        var curvesData = new List<(Vector3[] controlPoints, Vector3[] tangentsOut, Vector3[] tangentsIn, CurveType type)>();

        if (islandMode == IslandMode.Spline && splineSet != null)
        {
            foreach (var curve in splineSet.Curves)
            {
                if (curve.ControlPoints.Count < 2) continue;

                // For containment (Ray-Casting), discretize closed curves to polygons
                if (curve.Type == CurveType.Closed)
                {
                    var poly = new List<Vector3>();
                    var pts = curve.ControlPoints;
                    SplineMath.ComputeTangents(curve, out var tOut, out var tIn);
                    int n = pts.Count;

                    for (int s = 0; s < n; s++)
                    {
                        Vector3 p0 = pts[s];
                        Vector3 p3 = pts[(s + 1) % n];
                        Vector3 p1 = p0 + tOut[s];
                        Vector3 p2 = p3 + tIn[(s + 1) % n];

                        for (int i = 0; i < 16; i++)
                        {
                            float t = (float)i / 16.0f;
                            poly.Add(SplineMath.EvaluateBezierPosition(p0, p1, p2, p3, t));
                        }
                    }
                    polygons.Add(poly);
                }

                // For distance fields, gather all curve segments
                var cPts = curve.ControlPoints;
                SplineMath.ComputeTangents(curve, out var cTOut, out var cTIn);
                curvesData.Add((cPts.ToArray(), cTOut, cTIn, curve.Type));
            }
        }

        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;
        float falloffVal = Math.Max(0.001f, falloff);

        // Center of circular island in absolute world space
        float cx = centerX;
        float cz = centerZ;

        for (int z = 0; z < hm.Height; z++)
        {
            float worldZ = ctx.WorldOrigin.Z + (z - ctx.Padding) * step;
            for (int x = 0; x < hm.Width; x++)
            {
                float worldX = ctx.WorldOrigin.X + (x - ctx.Padding) * step;
                Vector3 worldP = new Vector3(worldX, ctx.WorldOrigin.Y, worldZ);

                float d = 0.0f;
                bool isInside = false;

                if (islandMode == IslandMode.Circular)
                {
                    float dx = worldX - cx;
                    float dz = worldZ - cz;
                    d = MathF.Sqrt(dx * dx + dz * dz);
                }
                else // Spline mode
                {
                    if (polygons.Count > 0)
                    {
                        // Check if inside any closed curve
                        foreach (var poly in polygons)
                        {
                            if (IsPointInPolygon2D(worldP, poly))
                            {
                                isInside = true;
                                break;
                            }
                        }
                    }

                    if (isInside)
                    {
                        d = 0.0f; // Inside core
                    }
                    else if (curvesData.Count > 0)
                    {
                        // Outside all, calculate min distance to curves in 2D
                        float minDistSq = float.MaxValue;
                        Vector3 q2D = new Vector3(worldP.X, 0.0f, worldP.Z);

                        foreach (var data in curvesData)
                        {
                            int n = data.controlPoints.Length;
                            int segments = data.type == CurveType.Closed ? n : n - 1;

                            for (int s = 0; s < segments; s++)
                            {
                                Vector3 p0 = data.controlPoints[s];
                                Vector3 p3 = data.controlPoints[(s + 1) % n];
                                Vector3 t0 = data.tangentsOut[s];
                                Vector3 t3 = data.tangentsIn[(s + 1) % n];

                                Vector3 p1 = p0 + t0;
                                Vector3 p2 = p3 + t3;

                                Vector3 p0_2D = new Vector3(p0.X, 0.0f, p0.Z);
                                Vector3 p1_2D = new Vector3(p1.X, 0.0f, p1.Z);
                                Vector3 p2_2D = new Vector3(p2.X, 0.0f, p2.Z);
                                Vector3 p3_2D = new Vector3(p3.X, 0.0f, p3.Z);

                                float segmentDistSq;
                                SplineMath.ProjectPointOntoSegment(p0_2D, p1_2D, p2_2D, p3_2D, q2D, out segmentDistSq);
                                if (segmentDistSq < minDistSq)
                                {
                                    minDistSq = segmentDistSq;
                                }
                            }
                        }
                        d = minDistSq != float.MaxValue ? MathF.Sqrt(minDistSq) : 0.0f;
                    }
                    else
                    {
                        // Fallback to circular if no valid splines
                        float dx = worldX - cx;
                        float dz = worldZ - cz;
                        d = MathF.Sqrt(dx * dx + dz * dz);
                    }
                }

                // Compute falloff weight
                float w = 0.0f;
                if (d <= radius)
                {
                    w = 1.0f;
                }
                else if (d >= radius + falloffVal)
                {
                    w = 0.0f;
                }
                else
                {
                    float t = (d - radius) / falloffVal;
                    float wRaw = Math.Clamp(1.0f - t, 0.0f, 1.0f);
                    w = (falloffCurve != null) ? falloffCurve.SampleBaked(wRaw) : wRaw;
                }

                float inputVal = (inputHM != null) ? inputHM[x, z] : 1.0f;
                mask[x, z] = w;
                hm[x, z] = inputVal * w;
            }
        }

        if (outputPortIndex == 0)
        {
            mask.Dispose();
            return hm;
        }
        else
        {
            hm.Dispose();
            return mask;
        }
    }

    private static bool IsPointInPolygon2D(Vector3 P, List<Vector3> polygon)
    {
        int crossings = 0;
        int N = polygon.Count;
        if (N < 3) return false;

        for (int j = 0; j < N; j++)
        {
            Vector3 Vj = polygon[j];
            Vector3 Vj1 = polygon[(j + 1) % N];

            // Ray-casting crossing test in horizontal X direction
            if (((Vj.Z <= P.Z && P.Z < Vj1.Z) || (Vj1.Z <= P.Z && P.Z < Vj.Z)) &&
                (P.X < Vj.X + (P.Z - Vj.Z) * (Vj1.X - Vj.X) / (Vj1.Z - Vj.Z)))
            {
                crossings++;
            }
        }
        return (crossings % 2) != 0;
    }
}

#endregion
