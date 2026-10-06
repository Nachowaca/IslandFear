using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that increases node density by subdividing Bézier segments longer than max_segment_length.
/// </summary>
public partial class SplineSubdivideNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineSubdivideNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineSubdivideNode"/> class.
    /// </summary>
    public SplineSubdivideNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Subdivides long segments using De Casteljau's split.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float maxSegmentLength = AssociatedResource != null ? AssociatedResource.MaxSegmentLength : 50.0f;
        int iterations = AssociatedResource != null ? AssociatedResource.Iterations : 1;

        maxSegmentLength = Math.Max(0.1f, maxSegmentLength);
        iterations = Math.Clamp(iterations, 1, 8);

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

        foreach (var curve in inputSpline.Curves)
        {
            int n = curve.ControlPoints.Count;
            if (n < 2)
            {
                outputSpline.AddCurve(curve);
                continue;
            }

            // Compute initial tangents
            SplineMath.ComputeTangents(curve, out var tOut, out var tIn);

            int segments = curve.Type == CurveType.Closed ? n : n - 1;
            var allSubSegs = new List<(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)>();

            for (int s = 0; s < segments; s++)
            {
                Vector3 p0 = curve.ControlPoints[s];
                Vector3 p3 = curve.ControlPoints[(s + 1) % n];
                Vector3 t0 = tOut[s];
                Vector3 t3 = tIn[(s + 1) % n];

                Vector3 p1 = p0 + t0;
                Vector3 p2 = p3 + t3;

                float len = SplineMath.GetSegmentArcLength(p0, p1, p2, p3);
                int m = 1;

                if (len > maxSegmentLength)
                {
                    m = Math.Min(1 << iterations, (int)MathF.Ceiling(len / maxSegmentLength));
                }

                if (m > 1)
                {
                    Vector3 curP0 = p0, curP1 = p1, curP2 = p2, curP3 = p3;

                    for (int k = 0; k < m - 1; k++)
                    {
                        float tk = 1.0f / (m - k);
                        SplineMath.SplitSegment(curP0, curP1, curP2, curP3, tk,
                            out var sa0, out var sa1, out var sa2, out var sa3,
                            out var sb0, out var sb1, out var sb2, out var sb3);

                        allSubSegs.Add((sa0, sa1, sa2, sa3));
                        curP0 = sb0;
                        curP1 = sb1;
                        curP2 = sb2;
                        curP3 = sb3;
                    }
                    allSubSegs.Add((curP0, curP1, curP2, curP3));
                }
                else
                {
                    allSubSegs.Add((p0, p1, p2, p3));
                }
            }

            // Now construct newPoints, newTangentsOut, and newTangentsIn from allSubSegs
            var newPoints = new List<Vector3>();
            var newTangentsOut = new List<Vector3>();
            var newTangentsIn = new List<Vector3>();

            if (curve.Type == CurveType.Closed)
            {
                for (int i = 0; i < allSubSegs.Count; i++)
                {
                    var seg = allSubSegs[i];
                    newPoints.Add(seg.p0);
                    newTangentsOut.Add(seg.p1 - seg.p0);
                    
                    int prevIdx = (i - 1 + allSubSegs.Count) % allSubSegs.Count;
                    newTangentsIn.Add(allSubSegs[prevIdx].p2 - allSubSegs[prevIdx].p3);
                }
            }
            else
            {
                for (int i = 0; i < allSubSegs.Count; i++)
                {
                    var seg = allSubSegs[i];
                    newPoints.Add(seg.p0);
                    newTangentsOut.Add(seg.p1 - seg.p0);
                    
                    if (i == 0)
                    {
                        newTangentsIn.Add(tIn[0]);
                    }
                    else
                    {
                        newTangentsIn.Add(allSubSegs[i - 1].p2 - allSubSegs[i - 1].p3);
                    }
                }
                
                // Add the last endpoint
                var lastSeg = allSubSegs[allSubSegs.Count - 1];
                newPoints.Add(lastSeg.p3);
                newTangentsIn.Add(lastSeg.p2 - lastSeg.p3);
                newTangentsOut.Add(tOut[tOut.Length - 1]);
            }

            var subdividedCurve = new SplineCurve(newPoints, curve.Type, newTangentsOut, newTangentsIn);
            outputSpline.AddCurve(subdividedCurve);
        }

        return outputSpline;
    }
}

#endregion
