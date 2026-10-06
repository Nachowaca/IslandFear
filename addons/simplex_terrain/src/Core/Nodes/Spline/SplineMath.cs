using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

/// <summary>
/// Core mathematical operations for cubic Bézier splines, numerical integration, projection, and refinement.
/// </summary>
public static class SplineMath
{
    private static readonly float[] GaussRoots = new float[] {
        -0.9602898565f, -0.7966664774f, -0.5255324099f, -0.1834346425f,
         0.1834346425f,  0.5255324099f,  0.7966664774f,  0.9602898565f
    };

    private static readonly float[] GaussWeights = new float[] {
         0.1012285363f,  0.2223810345f,  0.3137066459f,  0.3626837834f,
         0.3626837834f,  0.3137066459f,  0.2223810345f,  0.1012285363f
    };

    /// <summary>
    /// Computes the 3D position vector along a cubic Bézier segment at parameter t in [0, 1].
    /// </summary>
    public static Vector3 EvaluateBezierPosition(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t)
    {
        float omt = 1.0f - t;
        return omt * omt * omt * p0
             + 3.0f * t * omt * omt * p1
             + 3.0f * t * t * omt * p2
             + t * t * t * p3;
    }

    /// <summary>
    /// Computes the 3D velocity tangent vector B'(t) along a cubic Bézier segment.
    /// </summary>
    public static Vector3 EvaluateBezierDerivative(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t)
    {
        float omt = 1.0f - t;
        return 3.0f * omt * omt * (p1 - p0)
             + 6.0f * t * omt * (p2 - p1)
             + 3.0f * t * t * (p3 - p2);
    }

    /// <summary>
    /// Splits a cubic Bézier segment into two independent sub-segments at parameter t using De Casteljau's algorithm.
    /// </summary>
    public static void SplitSegment(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t,
        out Vector3 sa0, out Vector3 sa1, out Vector3 sa2, out Vector3 sa3,
        out Vector3 sb0, out Vector3 sb1, out Vector3 sb2, out Vector3 sb3)
    {
        float omt = 1.0f - t;
        Vector3 L01 = omt * p0 + t * p1;
        Vector3 L12 = omt * p1 + t * p2;
        Vector3 L23 = omt * p2 + t * p3;

        Vector3 Q012 = omt * L01 + t * L12;
        Vector3 Q123 = omt * L12 + t * L23;

        Vector3 split = omt * Q012 + t * Q123;

        sa0 = p0;
        sa1 = L01;
        sa2 = Q012;
        sa3 = split;

        sb0 = split;
        sb1 = Q123;
        sb2 = L23;
        sb3 = p3;
    }

    /// <summary>
    /// Projects an arbitrary coordinate query point Q onto a single cubic Bézier segment,
    /// returning the closest parameter t in [0, 1] and the minimum distance squared.
    /// </summary>
    public static float ProjectPointOntoSegment(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, Vector3 Q, out float minDistanceSq)
    {
        int kApprox = 10;
        float bestP = 0.0f;
        float bestDistSq = float.MaxValue;

        // Phase 1: Coarse Grid Search
        for (int i = 0; i < kApprox; i++)
        {
            float t = (float)i / (kApprox - 1);
            Vector3 pos = EvaluateBezierPosition(p0, p1, p2, p3, t);
            float distSq = pos.DistanceSquaredTo(Q);
            if (distSq < bestDistSq)
            {
                bestDistSq = distSq;
                bestP = t;
            }
        }

        // Phase 2: Binary Interval Refinement
        int jRefine = 8;
        float width = 1.0f / (kApprox - 1);

        for (int j = 0; j < jRefine; j++)
        {
            width *= 0.5f;
            float pUpper = Math.Clamp(bestP + width, 0.0f, 1.0f);
            float pLower = Math.Clamp(bestP - width, 0.0f, 1.0f);

            Vector3 posUpper = EvaluateBezierPosition(p0, p1, p2, p3, pUpper);
            Vector3 posLower = EvaluateBezierPosition(p0, p1, p2, p3, pLower);

            float distUpperSq = posUpper.DistanceSquaredTo(Q);
            float distLowerSq = posLower.DistanceSquaredTo(Q);

            if (distUpperSq < distLowerSq)
            {
                bestP = pUpper;
            }
            else
            {
                bestP = pLower;
            }
        }

        Vector3 finalPos = EvaluateBezierPosition(p0, p1, p2, p3, bestP);
        minDistanceSq = finalPos.DistanceSquaredTo(Q);
        return bestP;
    }

    /// <summary>
    /// Computes the physical spatial length along a segment by numerically integrating the speed function
    /// using Legendre-Gauss 8-Point Quadrature.
    /// </summary>
    public static float GetSegmentArcLength(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float a = 0.0f, float b = 1.0f)
    {
        float zScale = (b - a) / 2.0f;
        float zOffset = (b + a) / 2.0f;
        float sum = 0.0f;

        for (int i = 0; i < GaussRoots.Length; i++)
        {
            float tau = zScale * GaussRoots[i] + zOffset;
            Vector3 derivative = EvaluateBezierDerivative(p0, p1, p2, p3, tau);
            sum += GaussWeights[i] * derivative.Length();
        }

        return zScale * sum;
    }

    /// <summary>
    /// Computes or retrieves exact tangents for a SplineCurve.
    /// </summary>
    public static void ComputeTangents(SplineCurve curve, out Vector3[] tangentsOut, out Vector3[] tangentsIn)
    {
        if (curve.TangentsOut != null && curve.TangentsIn != null && curve.TangentsOut.Count == curve.ControlPoints.Count)
        {
            tangentsOut = curve.TangentsOut.ToArray();
            tangentsIn = curve.TangentsIn.ToArray();
        }
        else
        {
            ComputeTangents(curve.ControlPoints, curve.Type, out tangentsOut, out tangentsIn);
        }
    }

    /// <summary>
    /// Computes Catmull-Rom style C1 continuous tangents for a set of anchor points.
    /// </summary>
    public static void ComputeTangents(List<Vector3> points, CurveType type, out Vector3[] tangentsOut, out Vector3[] tangentsIn)
    {
        int n = points.Count;
        tangentsOut = new Vector3[n];
        tangentsIn = new Vector3[n];
        if (n < 2) return;

        for (int i = 0; i < n; i++)
        {
            if (type == CurveType.Closed)
            {
                int prev = (i - 1 + n) % n;
                int next = (i + 1) % n;
                // Chord-scaled interior tangent by 1/6
                tangentsOut[i] = (points[next] - points[prev]) / 6.0f;
                tangentsIn[i] = -tangentsOut[i];
            }
            else
            {
                if (i == 0)
                {
                    // Linear mode endpoint node (scaled by 1/3)
                    tangentsOut[i] = (points[1] - points[0]) / 3.0f;
                    tangentsIn[i] = -tangentsOut[i];
                }
                else if (i == n - 1)
                {
                    // Linear mode endpoint node (scaled by 1/3)
                    tangentsIn[i] = (points[n - 2] - points[n - 1]) / 3.0f;
                    tangentsOut[i] = -tangentsIn[i];
                }
                else
                {
                    // Chord-scaled interior tangent by 1/6
                    tangentsOut[i] = (points[i + 1] - points[i - 1]) / 6.0f;
                    tangentsIn[i] = -tangentsOut[i];
                }
            }
        }
    }
}
