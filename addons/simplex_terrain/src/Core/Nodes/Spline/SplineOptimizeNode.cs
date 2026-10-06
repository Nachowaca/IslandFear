using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that simplifies splines by removing redundant nodes whose spatial deviation is below a threshold.
/// </summary>
public partial class SplineOptimizeNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineOptimizeNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineOptimizeNode"/> class.
    /// </summary>
    public SplineOptimizeNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Optimizes spline curves using Heron's deviation and iterative node removal.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float deviationThreshold = AssociatedResource != null ? AssociatedResource.DeviationThreshold : 0.5f;
        deviationThreshold = Math.Max(0.0f, deviationThreshold);

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
            var pts = new List<Vector3>(curve.ControlPoints);
            int minRequired = curve.Type == CurveType.Closed ? 3 : 2;

            while (pts.Count > minRequired)
            {
                // Recompute tangents for active points
                SplineMath.ComputeTangents(pts, curve.Type, out var tOut, out var tIn);

                int bestIdx = -1;
                float minDev = float.MaxValue;

                // Determine range of candidate interior nodes to check
                int start = 1;
                int end = pts.Count - 2; // For open curves, exclude first and last nodes

                if (curve.Type == CurveType.Closed)
                {
                    start = 0;
                    end = pts.Count - 1;
                }

                for (int i = start; i <= end; i++)
                {
                    int prevIdx = (i - 1 + pts.Count) % pts.Count;
                    int nextIdx = (i + 1) % pts.Count;

                    Vector3 pPrev = pts[prevIdx];
                    Vector3 pNext = pts[nextIdx];
                    Vector3 pCurr = pts[i];

                    Vector3 A = pPrev + tOut[prevIdx];
                    Vector3 B = pNext + tIn[nextIdx];
                    Vector3 C = pCurr;

                    float a = A.DistanceTo(C);
                    float b = B.DistanceTo(C);
                    float c = A.DistanceTo(B);

                    float deviation = 0.0f;
                    if (c < 1e-6f)
                    {
                        deviation = a;
                    }
                    else
                    {
                        // Check projection foot location using dot products
                        Vector3 v = B - A;
                        Vector3 w = C - A;
                        float dot = w.Dot(v);
                        float lenSq = v.LengthSquared();
                        float proj = dot / lenSq;

                        if (proj < 0.0f)
                        {
                            deviation = a;
                        }
                        else if (proj > 1.0f)
                        {
                            deviation = b;
                        }
                        else
                        {
                            // Perpendicular foot is within segment, compute using Heron's formula
                            float s = (a + b + c) / 2.0f;
                            float areaSq = s * (s - a) * (s - b) * (s - c);
                            float area = areaSq > 0.0f ? MathF.Sqrt(areaSq) : 0.0f;
                            deviation = (2.0f * area) / c;
                        }
                    }

                    if (deviation < minDev)
                    {
                        minDev = deviation;
                        bestIdx = i;
                    }
                }

                if (bestIdx != -1 && minDev <= deviationThreshold)
                {
                    pts.RemoveAt(bestIdx);
                }
                else
                {
                    // No node can be removed under the threshold
                    break;
                }
            }

            SplineMath.ComputeTangents(pts, curve.Type, out var finalTOut, out var finalTIn);
            var optimizedCurve = new SplineCurve(pts, curve.Type, new List<Vector3>(finalTOut), new List<Vector3>(finalTIn));
            outputSpline.AddCurve(optimizedCurve);
        }

        return outputSpline;
    }
}

#endregion
