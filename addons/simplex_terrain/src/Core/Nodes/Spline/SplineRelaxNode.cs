using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that smooths jagged splines using iterative midpoint relaxation.
/// </summary>
public partial class SplineRelaxNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineRelaxNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineRelaxNode"/> class.
    /// </summary>
    public SplineRelaxNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Relax/smooth spline curves by iteratively shifting interior vertices toward neighbor midpoints.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int iterations = AssociatedResource != null ? AssociatedResource.Iterations : 3;
        float strength = AssociatedResource != null ? AssociatedResource.Strength : 0.5f;

        iterations = Math.Clamp(iterations, 1, 64);
        strength = Math.Clamp(strength, 0.0f, 1.0f);

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
            int n = pts.Count;

            if (n < 3)
            {
                outputSpline.AddCurve(curve);
                continue;
            }

            float halfBeta = strength / 2.0f;

            for (int iter = 0; iter < iterations; iter++)
            {
                var nextPts = new List<Vector3>(pts);

                if (curve.Type == CurveType.Closed)
                {
                    for (int i = 0; i < n; i++)
                    {
                        Vector3 pPrev = pts[(i - 1 + n) % n];
                        Vector3 pNext = pts[(i + 1) % n];
                        Vector3 pCurr = pts[i];

                        Vector3 M = (pPrev + pNext) / 2.0f;
                        nextPts[i] = M * halfBeta + pCurr * (1.0f - halfBeta);
                    }
                }
                else
                {
                    // Open curves: leave endpoints (index 0 and n-1) untouched
                    for (int i = 1; i < n - 1; i++)
                    {
                        Vector3 pPrev = pts[i - 1];
                        Vector3 pNext = pts[i + 1];
                        Vector3 pCurr = pts[i];

                        Vector3 M = (pPrev + pNext) / 2.0f;
                        nextPts[i] = M * halfBeta + pCurr * (1.0f - halfBeta);
                    }
                }

                pts = nextPts;
            }

            SplineMath.ComputeTangents(pts, curve.Type, out var tOut, out var tIn);
            var relaxedCurve = new SplineCurve(pts, curve.Type, new List<Vector3>(tOut), new List<Vector3>(tIn));
            outputSpline.AddCurve(relaxedCurve);
        }

        return outputSpline;
    }
}

#endregion
