using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that flat-blends the terrain heightmap along the spline curves.
/// </summary>
public partial class SplineConformNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineConformNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineConformNode"/> class.
    /// </summary>
    public SplineConformNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Locally conforms the heightfield along the spline curve network.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float blendWidth = AssociatedResource != null ? AssociatedResource.BlendWidth : 30.0f;
        Curve blendProfile = AssociatedResource != null ? AssociatedResource.BlendProfile : null;
        float heightOffset = AssociatedResource != null ? AssociatedResource.HeightOffset : 0.0f;
        bool preserveDetail = AssociatedResource != null ? AssociatedResource.PreserveDetail : true;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

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
        if (inputHM == null)
        {
            return hm;
        }

        // Copy input heights
        int width = inputHM.Width;
        int height = inputHM.Height;
        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                hm[x, z] = inputHM[x, z];
            }
        }

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

        // Phase 1: High-Frequency Detail Extraction (if active)
        using HeightMatrix lowHM = new HeightMatrix(width, height);
        using HeightMatrix detailHM = new HeightMatrix(width, height);

        if (preserveDetail)
        {
            // Low pass filter via separable binomial blur (4 iterations for radius ~2)
            // Initialize lowHM with input heights
            for (int z = 0; z < height; z++)
            {
                for (int x = 0; x < width; x++)
                {
                    lowHM[x, z] = inputHM[x, z];
                }
            }

            using HeightMatrix temp = new HeightMatrix(width, height);
            float q = 0.5f / 4.0f; // beta = 0.5
            float h = 1.0f - 2.0f * q;

            for (int iter = 0; iter < 4; iter++)
            {
                // Horizontal sweep
                for (int z = 0; z < height; z++)
                {
                    for (int x = 1; x < width - 1; x++)
                    {
                        temp[x, z] = q * lowHM[x - 1, z] + h * lowHM[x, z] + q * lowHM[x + 1, z];
                    }
                    temp[0, z] = h * lowHM[0, z] + 2.0f * q * lowHM[1, z];
                    temp[width - 1, z] = h * lowHM[width - 1, z] + 2.0f * q * lowHM[width - 2, z];
                }
                // Vertical sweep
                for (int x = 0; x < width; x++)
                {
                    for (int z = 1; z < height - 1; z++)
                    {
                        lowHM[x, z] = q * temp[x, z - 1] + h * temp[x, z] + q * temp[x, z + 1];
                    }
                    lowHM[x, 0] = h * temp[x, 0] + 2.0f * q * temp[x, 1];
                    lowHM[x, height - 1] = h * temp[x, height - 1] + 2.0f * q * temp[x, height - 2];
                }
            }

            // Extract detail delta
            for (int z = 0; z < height; z++)
            {
                for (int x = 0; x < width; x++)
                {
                    detailHM[x, z] = inputHM[x, z] - lowHM[x, z];
                }
            }
        }

        // Phase 2: Spline Conforming and Detail blending
        float blendWidthVal = blendWidth > 0.001f ? blendWidth : 0.001f;
        float heightScaleVal = MathF.Abs(heightScale) > 1e-5f ? heightScale : 1.0f;

        for (int pz = 0; pz < height; pz++)
        {
            for (int px = 0; px < width; px++)
            {
                Vector3 worldP = CoordinateMapping.PixelToWorld(new Vector2(px, pz), ctx);
                float bestDist2DSq = float.MaxValue;
                Vector3 bestProjPoint = Vector3.Zero;

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
                        Vector3 q2D = new Vector3(worldP.X, 0.0f, worldP.Z);

                        float segmentDistSq;
                        float tProj = SplineMath.ProjectPointOntoSegment(p0_2D, p1_2D, p2_2D, p3_2D, q2D, out segmentDistSq);
                        Vector3 projP = SplineMath.EvaluateBezierPosition(p0, p1, p2, p3, tProj);

                        float dist2DSq = (worldP.X - projP.X) * (worldP.X - projP.X) + (worldP.Z - projP.Z) * (worldP.Z - projP.Z);
                        if (dist2DSq < bestDist2DSq)
                        {
                            bestDist2DSq = dist2DSq;
                            bestProjPoint = projP;
                        }
                    }
                }

                if (bestDist2DSq == float.MaxValue) continue;

                float dist2D = MathF.Sqrt(bestDist2DSq);
                if (dist2D < blendWidthVal)
                {
                    float mSpread = Math.Max(0.0f, 1.0f - dist2D / blendWidthVal);
                    float p;

                    if (blendProfile != null)
                    {
                        p = blendProfile.SampleBaked(mSpread);
                    }
                    else
                    {
                        // Default road-shaped cross-section: center 35% flat road, outer 65% blends smoothly
                        float u = mSpread / 0.65f;
                        if (mSpread >= 0.65f) u = 1.0f;
                        p = 3.0f * u * u - 2.0f * u * u * u;
                    }

                    float roadHeightRaw = (bestProjPoint.Y + heightOffset) / heightScaleVal;

                    if (preserveDetail)
                    {
                        float lowHeight = lowHM[px, pz];
                        float detail = detailHM[px, pz];

                        // Attenuate detail on the flat road surface
                        float attenuation = 0.8f;
                        float blendedLow = roadHeightRaw * p + lowHeight * (1.0f - p);
                        float finalDetail = detail * (1.0f - p * attenuation);

                        hm[px, pz] = blendedLow + finalDetail;
                    }
                    else
                    {
                        float origHeight = inputHM[px, pz];
                        hm[px, pz] = roadHeightRaw * p + origHeight * (1.0f - p);
                    }
                }
            }
        }

        return hm;
    }
}

#endregion
