using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that rasterizes a 3D spline curve network as a 2D distance-field mask.
/// </summary>
public partial class SplineStrokeNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineStrokeNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineStrokeNode"/> class.
    /// </summary>
    public SplineStrokeNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("mask_out", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the distance field rasterization.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float width = AssociatedResource != null ? AssociatedResource.Width : 20.0f;
        float hardness = AssociatedResource != null ? AssociatedResource.Hardness : 0.8f;
        Curve falloffCurve = AssociatedResource != null ? AssociatedResource.FalloffCurve : null;

        SplineSet splineSet = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            splineSet = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplineSet;
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        if (splineSet == null || splineSet.GetCurveCount() == 0)
        {
            return hm;
        }

        // Precompute all curve tangents
        var curvesData = new List<(Vector3[] controlPoints, Vector3[] tangentsOut, Vector3[] tangentsIn, CurveType type)>();
        foreach (var curve in splineSet.Curves)
        {
            if (curve.ControlPoints.Count < 2) continue;
            var pts = curve.ControlPoints;
            SplineMath.ComputeTangents(curve, out var tOut, out var tIn);
            curvesData.Add((pts.ToArray(), tOut, tIn, curve.Type));
        }

        if (curvesData.Count == 0)
        {
            return hm;
        }

        var segmentsList = new List<SegmentData>();
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

                float minX = MathF.Min(MathF.Min(p0_2D.X, p1_2D.X), MathF.Min(p2_2D.X, p3_2D.X));
                float maxX = MathF.Max(MathF.Max(p0_2D.X, p1_2D.X), MathF.Max(p2_2D.X, p3_2D.X));
                float minZ = MathF.Min(MathF.Min(p0_2D.Z, p1_2D.Z), MathF.Min(p2_2D.Z, p3_2D.Z));
                float maxZ = MathF.Max(MathF.Max(p0_2D.Z, p1_2D.Z), MathF.Max(p2_2D.Z, p3_2D.Z));

                segmentsList.Add(new SegmentData
                {
                    P0_2D = p0_2D,
                    P1_2D = p1_2D,
                    P2_2D = p2_2D,
                    P3_2D = p3_2D,
                    MinX = minX,
                    MaxX = maxX,
                    MinZ = minZ,
                    MaxZ = maxZ
                });
            }
        }

        int paddedSize = ctx.PaddedSize;
        float radius = width / 2.0f;
        float radiusVal = radius > 0.001f ? radius : 0.001f;
        float divisor = 1.0f - hardness;

        for (int pz = 0; pz < paddedSize; pz++)
        {
            for (int px = 0; px < paddedSize; px++)
            {
                Vector3 worldP = CoordinateMapping.PixelToWorld(new Vector2(px, pz), ctx);
                float minDistSq = float.MaxValue;
                Vector3 q2D = new Vector3(worldP.X, 0.0f, worldP.Z);

                foreach (var seg in segmentsList)
                {
                    // Only test segments whose AABB overlaps the query point plus stroke radius
                    if (seg.MinX <= q2D.X + radiusVal && seg.MaxX >= q2D.X - radiusVal &&
                        seg.MinZ <= q2D.Z + radiusVal && seg.MaxZ >= q2D.Z - radiusVal)
                    {
                        float segmentDistSq;
                        SplineMath.ProjectPointOntoSegment(seg.P0_2D, seg.P1_2D, seg.P2_2D, seg.P3_2D, q2D, out segmentDistSq);
                        if (segmentDistSq < minDistSq)
                        {
                            minDistSq = segmentDistSq;
                        }
                    }
                }

                if (minDistSq == float.MaxValue)
                {
                    hm[px, pz] = 0.0f;
                    continue;
                }

                float dist = MathF.Sqrt(minDistSq);
                float mSpread = Math.Max(0.0f, 1.0f - dist / radiusVal);

                float val;
                if (divisor < 1e-4f)
                {
                    val = mSpread > 0.0f ? 1.0f : 0.0f;
                }
                else
                {
                    val = Math.Clamp(mSpread / divisor, 0.0f, 1.0f);
                }

                if (falloffCurve != null)
                {
                    val = falloffCurve.SampleBaked(val);
                }

                hm[px, pz] = val;
            }
        }

        return hm;
    }

    private struct SegmentData
    {
        public Vector3 P0_2D;
        public Vector3 P1_2D;
        public Vector3 P2_2D;
        public Vector3 P3_2D;
        public float MinX;
        public float MaxX;
        public float MinZ;
        public float MaxZ;
    }
}

#endregion
