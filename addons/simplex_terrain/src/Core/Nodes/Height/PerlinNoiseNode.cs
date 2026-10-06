using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that generates single-octave coherent gradient Perlin noise.
/// Implements the <see cref="INoiseSource"/> interface.
/// </summary>
public partial class PerlinNoiseNode : TerrainNode, INoiseSource
{
    private PermutationTable _table;
    private int _lastSeed = -1;
    private readonly object _tableLock = new();

    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public PerlinNoiseNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="PerlinNoiseNode"/> class.
    /// </summary>
    public PerlinNoiseNode()
    {
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    private PermutationTable GetTable(int seed)
    {
        lock (_tableLock)
        {
            if (_table == null || _lastSeed != seed)
            {
                _table = new PermutationTable(seed);
                _lastSeed = seed;
            }
            return _table;
        }
    }

    /// <summary>
    /// Gets the compiled permutation table for the current seed configuration.
    /// </summary>
    public PermutationTable Table
    {
        get
        {
            int seed = AssociatedResource != null ? AssociatedResource.Seed : 1337;
            return GetTable(seed);
        }
    }

    /// <summary>
    /// Samples the continuous Perlin noise value at the given world coordinates in [0, 1] range.
    /// Implements <see cref="INoiseSource.Sample"/>.
    /// </summary>
    public float Sample(float x, float z, int subSeed = 0)
    {
        float scaleX = AssociatedResource != null ? AssociatedResource.ScaleX : 1.0f;
        float scaleZ = AssociatedResource != null ? AssociatedResource.ScaleZ : 1.0f;
        if (scaleX <= 0f) scaleX = 1.0f;
        if (scaleZ <= 0f) scaleZ = 1.0f;

        int seed = AssociatedResource != null ? AssociatedResource.Seed : 1337;
        var table = GetTable(seed);
        return table.SampleSinglePerlin(x / scaleX, z / scaleZ, subSeed);
    }

    /// <summary>
    /// Evaluates the Perlin noise over the entire padded chunk grid.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float freq = AssociatedResource != null ? AssociatedResource.Frequency : 0.01f;
        float outMin = AssociatedResource != null ? AssociatedResource.OutputMin : 0.0f;
        float outMax = AssociatedResource != null ? AssociatedResource.OutputMax : 1.0f;
        int seed = AssociatedResource != null ? AssociatedResource.Seed : 1337;
        float scaleX = AssociatedResource != null ? AssociatedResource.ScaleX : 1.0f;
        float scaleZ = AssociatedResource != null ? AssociatedResource.ScaleZ : 1.0f;
        if (scaleX <= 0f) scaleX = 1.0f;
        if (scaleZ <= 0f) scaleZ = 1.0f;

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        float step = ctx.Resolution > 0 ? ctx.WorldSize / ctx.Resolution : 1.0f;
        int w = hm.Width;
        int h = hm.Height;

        if (GpuTerrain.IsSupported && AssociatedResource != null && AssociatedResource.UseGpu)
        {
            var shader = GpuTerrain.LoadShader("res://addons/simplex_terrain/shaders/perlin_noise.glsl");
            if (shader.IsValid)
            {
                byte[] paramsBytes = new byte[48];
                Buffer.BlockCopy(BitConverter.GetBytes(freq), 0, paramsBytes, 0, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)seed), 0, paramsBytes, 4, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(ctx.WorldOrigin.X), 0, paramsBytes, 8, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(ctx.WorldOrigin.Z), 0, paramsBytes, 12, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(step), 0, paramsBytes, 16, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)ctx.Padding), 0, paramsBytes, 20, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(outMin), 0, paramsBytes, 24, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(outMax), 0, paramsBytes, 28, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)w), 0, paramsBytes, 32, 4);
                Buffer.BlockCopy(BitConverter.GetBytes((float)h), 0, paramsBytes, 36, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(scaleX), 0, paramsBytes, 40, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(scaleZ), 0, paramsBytes, 44, 4);

                uint groupsX = (uint)Mathf.CeilToInt(w / 8.0f);
                uint groupsY = (uint)Mathf.CeilToInt(h / 8.0f);

                GpuTerrain.DispatchAndReadback(shader, hm, paramsBytes, groupsX, groupsY);
                return hm;
            }
        }

        var span = hm.AsSpan();
        w = hm.Width;
        h = hm.Height;
        float range = outMax - outMin;
        float scaledStepX = (step * freq) / scaleX;
        float scaledStepZ = (step * freq) / scaleZ;
        float baseX = ((ctx.WorldOrigin.X - ctx.Padding * step) * freq) / scaleX;
        float baseZ = ((ctx.WorldOrigin.Z - ctx.Padding * step) * freq) / scaleZ;

        var table = GetTable(seed);

        for (int z = 0; z < h; z++)
        {
            ctx.CancellationToken.ThrowIfCancellationRequested();
            float worldZNoise = baseZ + z * scaledStepZ;
            int rowOff = z * w;
            for (int x = 0; x < w; x++)
            {
                float worldXNoise = baseX + x * scaledStepX;
                float val = table.SampleSinglePerlin(worldXNoise, worldZNoise);
                span[rowOff + x] = outMin + val * range;
            }
        }

        return hm;
    }
}

#endregion
