using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Runtime node that clips spline networks cleanly to specific rectangular tile boundary bounds.
/// </summary>
public partial class SplineClipNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineClipNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineClipNode"/> class.
    /// </summary>
    public SplineClipNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Clips input spline curves to the context's WorldOrigin and WorldSize bounding box.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        SplineSet inputSpline = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputSpline = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplineSet;
        }

        var outputSpline = new SplineSet();
        if (inputSpline == null || inputSpline.GetCurveCount() == 0)
        {
            return outputSpline;
        }

        float xMin = ctx.WorldOrigin.X;
        float xMax = ctx.WorldOrigin.X + ctx.WorldSize;
        float zMin = ctx.WorldOrigin.Z;
        float zMax = ctx.WorldOrigin.Z + ctx.WorldSize;

        foreach (var curve in inputSpline.Curves)
        {
            int n = curve.ControlPoints.Count;
            if (n < 2)
            {
                outputSpline.AddCurve(curve);
                continue;
            }

            // Compute tangents
            SplineMath.ComputeTangents(curve, out var tOut, out var tIn);

            int segments = curve.Type == CurveType.Closed ? n : n - 1;
            var processedSegments = new List<Tuple<Vector3, Vector3, Vector3, Vector3>>();

            for (int s = 0; s < segments; s++)
            {
                Vector3 p0 = curve.ControlPoints[s];
                Vector3 p3 = curve.ControlPoints[(s + 1) % n];
                Vector3 p1 = p0 + tOut[s];
                Vector3 p2 = p3 + tIn[(s + 1) % n];

                var segmentQueue = new Queue<Tuple<Vector3, Vector3, Vector3, Vector3>>();
                segmentQueue.Enqueue(new(p0, p1, p2, p3));

                while (segmentQueue.Count > 0)
                {
                    var seg = segmentQueue.Dequeue();
                    var crossings = new List<float>();
                    FindCrossings(seg.Item1, seg.Item2, seg.Item3, seg.Item4, 0.0f, 1.0f, xMin, xMax, zMin, zMax, crossings);

                    if (crossings.Count > 0)
                    {
                        crossings.Sort();
                        float tSplit = -1.0f;
                        foreach (float tc in crossings)
                        {
                            if (tc > 0.01f && tc < 0.99f)
                            {
                                tSplit = tc;
                                break;
                            }
                        }

                        if (tSplit > 0.0f)
                        {
                            SplineMath.SplitSegment(seg.Item1, seg.Item2, seg.Item3, seg.Item4, tSplit,
                                out var sa0, out var sa1, out var sa2, out var sa3,
                                out var sb0, out var sb1, out var sb2, out var sb3);

                            segmentQueue.Enqueue(new(sa0, sa1, sa2, sa3));
                            segmentQueue.Enqueue(new(sb0, sb1, sb2, sb3));
                            continue;
                        }
                    }

                    processedSegments.Add(seg);
                }
            }

            var keptSegments = new List<Tuple<Vector3, Vector3, Vector3, Vector3>>();
            foreach (var seg in processedSegments)
            {
                float segMinX = MathF.Min(MathF.Min(seg.Item1.X, seg.Item2.X), MathF.Min(seg.Item3.X, seg.Item4.X));
                float segMaxX = MathF.Max(MathF.Max(seg.Item1.X, seg.Item2.X), MathF.Max(seg.Item3.X, seg.Item4.X));
                float segMinZ = MathF.Min(MathF.Min(seg.Item1.Z, seg.Item2.Z), MathF.Min(seg.Item3.Z, seg.Item4.Z));
                float segMaxZ = MathF.Max(MathF.Max(seg.Item1.Z, seg.Item2.Z), MathF.Max(seg.Item3.Z, seg.Item4.Z));

                bool overlaps = (segMinX <= xMax && segMaxX >= xMin && segMinZ <= zMax && segMaxZ >= zMin);
                if (overlaps)
                {
                    keptSegments.Add(seg);
                }
            }

            if (keptSegments.Count == 0) continue;

            if (keptSegments.Count == segments && curve.Type == CurveType.Closed)
            {
                outputSpline.AddCurve(curve);
                continue;
            }

            var currentPoints = new List<Vector3>();
            Vector3 ClampToBox(Vector3 p)
            {
                return new Vector3(
                    Math.Clamp(p.X, xMin, xMax),
                    p.Y,
                    Math.Clamp(p.Z, zMin, zMax)
                );
            }

            currentPoints.Add(ClampToBox(keptSegments[0].Item1));
            
            for (int i = 0; i < keptSegments.Count; i++)
            {
                var seg = keptSegments[i];
                currentPoints.Add(ClampToBox(seg.Item2));
                currentPoints.Add(ClampToBox(seg.Item3));
                currentPoints.Add(ClampToBox(seg.Item4));

                if (i < keptSegments.Count - 1)
                {
                    var nextSeg = keptSegments[i + 1];
                    Vector3 currentEndClamped = ClampToBox(seg.Item4);
                    Vector3 nextStartClamped = ClampToBox(nextSeg.Item1);
                    if (currentEndClamped.DistanceTo(nextStartClamped) > 1e-3f)
                    {
                        outputSpline.AddCurve(new SplineCurve(currentPoints, CurveType.Open));
                        currentPoints = new List<Vector3> { nextStartClamped };
                    }
                }
            }
            outputSpline.AddCurve(new SplineCurve(currentPoints, CurveType.Open));
        }

        return outputSpline;
    }

    private void FindCrossings(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float tStart, float tEnd, float xMin, float xMax, float zMin, float zMax, List<float> crossings)
    {
        SplineMath.SplitSegment(p0, p1, p2, p3, tEnd,
            out var la0, out var la1, out var la2, out var la3,
            out var lb0, out var lb1, out var lb2, out var lb3);

        float tSplit = tEnd > 0.0f ? (tStart / tEnd) : 0.0f;
        SplineMath.SplitSegment(la0, la1, la2, la3, tSplit,
            out var lra0, out var lra1, out var lra2, out var lra3,
            out var lrb0, out var lrb1, out var lrb2, out var lrb3);

        Vector3 b0 = lrb0, b1 = lrb1, b2 = lrb2, b3 = lrb3;

        float minX = MathF.Min(MathF.Min(b0.X, b1.X), MathF.Min(b2.X, b3.X));
        float maxX = MathF.Max(MathF.Max(b0.X, b1.X), MathF.Max(b2.X, b3.X));
        float minZ = MathF.Min(MathF.Min(b0.Z, b1.Z), MathF.Min(b2.Z, b3.Z));
        float maxZ = MathF.Max(MathF.Max(b0.Z, b1.Z), MathF.Max(b2.Z, b3.Z));

        bool crossesXMin = (minX <= xMin && maxX >= xMin);
        bool crossesXMax = (minX <= xMax && maxX >= xMax);
        bool crossesZMin = (minZ <= zMin && maxZ >= zMin);
        bool crossesZMax = (minZ <= zMax && maxZ >= zMax);

        if (!crossesXMin && !crossesXMax && !crossesZMin && !crossesZMax)
        {
            return;
        }

        if (tEnd - tStart < 1e-5f)
        {
            crossings.Add((tStart + tEnd) * 0.5f);
            return;
        }

        float tMid = (tStart + tEnd) * 0.5f;
        FindCrossings(p0, p1, p2, p3, tStart, tMid, xMin, xMax, zMin, zMax, crossings);
        FindCrossings(p0, p1, p2, p3, tMid, tEnd, xMin, xMax, zMin, zMax, crossings);
    }
}
