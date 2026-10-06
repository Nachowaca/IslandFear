using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that deforms height values using a high-performance 256-element baked look-up table (LUT).
/// </summary>
public partial class CurveNode : TerrainNode
{
    private const int LutSize = 256;
    private readonly float[] _lut = new float[LutSize];
    private bool _lutBaked = false;
    private Curve _lastCurve = null;

    // Precalculated extrapolation parameters to fully bypass flat easing shoulders
    private float _slopeStart = 0.0f;
    private float _slopeEnd = 0.0f;
    private float _tMaxSlopeStart = 0.0f;
    private float _yMaxSlopeStart = 0.0f;
    private float _tMaxSlopeEnd = 1.0f;
    private float _yMaxSlopeEnd = 1.0f;

    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public CurveNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="CurveNode"/> class.
    /// </summary>
    public CurveNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    private void BakeLut(Curve curve)
    {
        if (curve == null)
        {
            _lutBaked = false;
            _lastCurve = null;
            return;
        }

        // Bake the uniform 256-element table
        float step = 1.0f / (LutSize - 1);
        for (int i = 0; i < LutSize; i++)
        {
            float t = i * step;
            _lut[i] = curve.SampleBaked(t);
        }

        // Precompute extrapolation parameters to fully bypass easing tangents at boundaries
        float invDeltaStep = 255.0f;

        // Unconditionally search the first 20% of the LUT for the maximum absolute slope to capture the rising/falling trend
        _slopeStart = (_lut[1] - _lut[0]) * invDeltaStep;
        int idxMaxSlopeStart = 0;
        float maxAbsSlopeStart = MathF.Abs(_slopeStart);
        int searchEnd = (int)(LutSize * 0.2f);
        for (int i = 0; i < searchEnd; i++)
        {
            float s = (_lut[i + 1] - _lut[i]) * invDeltaStep;
            if (MathF.Abs(s) > maxAbsSlopeStart)
            {
                maxAbsSlopeStart = MathF.Abs(s);
                _slopeStart = s;
                idxMaxSlopeStart = i;
            }
        }
        _tMaxSlopeStart = idxMaxSlopeStart * step;
        _yMaxSlopeStart = _lut[idxMaxSlopeStart];

        // Unconditionally search the last 20% of the LUT for the maximum absolute slope to capture the rising/falling trend
        _slopeEnd = (_lut[LutSize - 1] - _lut[LutSize - 2]) * invDeltaStep;
        int idxMaxSlopeEnd = LutSize - 2;
        float maxAbsSlopeEnd = MathF.Abs(_slopeEnd);
        int searchStart = (int)(LutSize * 0.8f);
        for (int i = LutSize - 2; i >= searchStart; i--)
        {
            float s = (_lut[i + 1] - _lut[i]) * invDeltaStep;
            if (MathF.Abs(s) > maxAbsSlopeEnd)
            {
                maxAbsSlopeEnd = MathF.Abs(s);
                _slopeEnd = s;
                idxMaxSlopeEnd = i;
            }
        }
        _tMaxSlopeEnd = idxMaxSlopeEnd * step;
        _yMaxSlopeEnd = _lut[idxMaxSlopeEnd];

        GD.Print($"[Debug CurveNode] NodeId={NodeId} Extrapolation Start: t={_tMaxSlopeStart:F4}, y={_yMaxSlopeStart:F4}, slope={_slopeStart:F4} | End: t={_tMaxSlopeEnd:F4}, y={_yMaxSlopeEnd:F4}, slope={_slopeEnd:F4}");

        _lastCurve = curve;
        _lutBaked = true;
    }

    /// <summary>
    /// Evaluates the Curve deformer over the input height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        Curve curve = AssociatedResource?.CurveToApply;

        // Fetch upstream height matrix
        HeightMatrix inputHM = null;
        var link = InputLinks[0];
        if (link.SourceNode != null)
        {
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        if (inputHM == null)
        {
            return hm;
        }

        // Bake LUT if needed (thread-safe lock to protect local state cache)
        lock (_lut)
        {
            if (!_lutBaked || _lastCurve != curve)
            {
                BakeLut(curve);
            }
        }

        ReadOnlySpan<float> spanIn = inputHM.AsReadOnlySpan();
        Span<float> spanOut = hm.AsSpan();
        int total = hm.Width * hm.Height;
        int width = hm.Width;

        // Fast path: if no curve is provided, act as a pure passthrough
        if (curve == null)
        {
            spanIn.CopyTo(spanOut);
            return hm;
        }

        float deltaStep = 1.0f / (LutSize - 1);
        float invDeltaStep = 255.0f; // 1.0f / deltaStep

        bool bypass = AssociatedResource == null || AssociatedResource.BypassShoulders;

        float tStart = bypass ? _tMaxSlopeStart : 0.0f;
        float yStart = bypass ? _yMaxSlopeStart : _lut[0];
        float sStart = bypass ? _slopeStart : (_lut[1] - _lut[0]) * invDeltaStep;

        float tEnd = bypass ? _tMaxSlopeEnd : 1.0f;
        float yEnd = bypass ? _yMaxSlopeEnd : _lut[LutSize - 1];
        float sEnd = bypass ? _slopeEnd : (_lut[LutSize - 1] - _lut[LutSize - 2]) * invDeltaStep;

        for (int i = 0; i < total; i++)
        {
            if (i % width == 0)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
            }

            float v = spanIn[i];
            if (v >= tEnd)
            {
                spanOut[i] = yEnd + (v - tEnd) * sEnd;
            }
            else if (v <= tStart)
            {
                spanOut[i] = yStart + (v - tStart) * sStart;
            }
            else
            {
                // Index localization
                float scaledIdx = v * invDeltaStep;
                int idxPrev = (int)MathF.Floor(scaledIdx);
                idxPrev = Math.Clamp(idxPrev, 0, LutSize - 1);
                int idxNext = Math.Min(LutSize - 1, idxPrev + 1);

                // Blending percentage
                float xPrev = idxPrev * deltaStep;
                float p = (v - xPrev) * invDeltaStep;
                p = Math.Clamp(p, 0.0f, 1.0f);

                // Linear blend
                float yPrev = _lut[idxPrev];
                float yNext = _lut[idxNext];
                spanOut[i] = yPrev * (1.0f - p) + yNext * p;
            }
        }

        return hm;
    }
}

#endregion
