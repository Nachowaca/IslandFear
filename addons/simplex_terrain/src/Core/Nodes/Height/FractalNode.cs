using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that wraps and stacks any noise source into multiple octaves.
/// Implements lacunarity, persistence, and exact geometric scale range normalization.
/// </summary>
public partial class FractalNode : TerrainNode
{
    private static readonly INoiseSource DefaultNoise = new DefaultNoiseSource();

    private class DefaultNoiseSource : INoiseSource
    {
        private readonly PermutationTable _table = new(1337);
        public float Sample(float x, float z, int subSeed = 0) => _table.SampleSinglePerlin(x, z, subSeed);
        public PermutationTable Table => _table;
    }

    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public FractalNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="FractalNode"/> class.
    /// </summary>
    public FractalNode()
    {
        Inputs.Add(new Port("Noise", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the fractal octave summation over the chunk height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int octaves = AssociatedResource != null ? AssociatedResource.Octaves : 8;
        float persistence = AssociatedResource != null ? AssociatedResource.Persistence : 0.5f;
        float lacunarity = AssociatedResource != null ? AssociatedResource.Lacunarity : 2.0f;
        float frequency = AssociatedResource != null ? AssociatedResource.Frequency : 0.005f;
        float outMin = AssociatedResource != null ? AssociatedResource.OutputMin : 0.0f;
        float outMax = AssociatedResource != null ? AssociatedResource.OutputMax : 1.0f;

        // Bounded octave safety clamp
        octaves = Math.Clamp(octaves, 1, 16);

        // Fetch upstream noise source from connection
        INoiseSource noiseSource = DefaultNoise;
        var link = InputLinks[0];
        if (link.SourceNode is INoiseSource source)
        {
            noiseSource = source;
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;
        int w = hm.Width;
        int h = hm.Height;

        if (GpuTerrain.IsSupported && AssociatedResource != null && AssociatedResource.UseGpu)
        {
            var shader = GpuTerrain.LoadShader("res://addons/simplex_terrain/shaders/fractal_noise.glsl");
            if (shader.IsValid)
            {
                byte[] paramsBytes = new byte[52];
                Buffer.BlockCopy(BitConverter.GetBytes(frequency), 0, paramsBytes, 0, 4);
                float seedVal = 1337f;
                Buffer.BlockCopy(BitConverter.GetBytes(seedVal), 0, paramsBytes, 4, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(ctx.WorldOrigin.X), 0, paramsBytes, 8, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(ctx.WorldOrigin.Z), 0, paramsBytes, 12, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(step), 0, paramsBytes, 16, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)ctx.Padding), 0, paramsBytes, 20, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(outMin), 0, paramsBytes, 24, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(outMax), 0, paramsBytes, 28, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)w), 0, paramsBytes, 32, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)h), 0, paramsBytes, 36, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)octaves), 0, paramsBytes, 40, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(persistence), 0, paramsBytes, 44, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(lacunarity), 0, paramsBytes, 48, 4);

                uint groupsX = (uint)Mathf.CeilToInt(w / 8.0f);
                uint groupsY = (uint)Mathf.CeilToInt(h / 8.0f);

                GpuTerrain.DispatchAndReadback(shader, hm, paramsBytes, groupsX, groupsY);
                return hm;
            }
        }

        // Compute exact finite-octave geometric normalization factor to prevent clipping
        float normFactor;
        if (MathF.Abs(persistence - 1.0f) < 0.001f)
        {
            normFactor = 1.0f / octaves;
        }
        else
        {
            normFactor = (1.0f - persistence) / (1.0f - MathF.Pow(persistence, octaves));
        }

        var span = hm.AsSpan();
        float range = outMax - outMin;

        Span<float> invFreqs = stackalloc float[octaves];
        float freqVal = 1.0f / frequency;
        for (int i = 0; i < octaves; i++)
        {
            invFreqs[i] = 1.0f / freqVal;
            freqVal /= lacunarity;
        }

        Span<float> amps = stackalloc float[octaves];
        float curAmp = 1.0f;
        for (int i = 0; i < octaves; i++)
        {
            amps[i] = curAmp;
            curAmp *= persistence;
        }

        var table = noiseSource.Table;

        for (int z = 0; z < h; z++)
        {
            ctx.CancellationToken.ThrowIfCancellationRequested();
            float worldZ = ctx.WorldOrigin.Z + (z - ctx.Padding) * step;
            int rowOff = z * w;
            for (int x = 0; x < w; x++)
            {
                float worldX = ctx.WorldOrigin.X + (x - ctx.Padding) * step;

                float rAcc = 0.0f;
                for (int i = 0; i < octaves; i++)
                {
                    // Sample continuous noise at scaled frequency
                    float vOct = noiseSource.Sample(worldX * invFreqs[i], worldZ * invFreqs[i], i);
                    rAcc += vOct * amps[i];
                }

                float rOut = rAcc * normFactor;
                float clamped = Math.Max(rOut, 0.0f);
                span[rowOff + x] = outMin + clamped * range;
            }
        }

        return hm;
    }
}

#endregion
