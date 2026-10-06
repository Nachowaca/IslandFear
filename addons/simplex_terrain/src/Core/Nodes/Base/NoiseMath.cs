using System;

namespace SimpleXTerrain;

/// <summary>
/// High-fidelity mathematical utilities for pseudo-random hashing, coherent Perlin noise,
/// and Voronoi cell calculations, referencing the SimpleXTerrain Math Bible.
/// </summary>
public static class NoiseMath
{
    /// <summary>
    /// Bounces a value smoothly using a high-continuity quintic fade curve: psi(t) = t^3 * (6t^2 - 15t + 10).
    /// Eliminates derivative discontinuity seams at lattice boundaries.
    /// </summary>
    public static float QuinticFade(float t)
    {
        return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
    }

    /// <summary>
    /// Computes the dot product of one of the eight predefined 2D gradient vectors with the displacement vector.
    /// </summary>
    public static float DotGradient(int idx, float dx, float dz)
    {
        switch (idx & 7)
        {
            case 0: return dx;          // (1, 0)
            case 1: return -dx;         // (-1, 0)
            case 2: return dx + dz;     // (1, 1)
            case 3: return -dx + dz;    // (-1, 1)
            case 4: return dx - dz;     // (1, -1)
            case 5: return -dx - dz;    // (-1, -1)
            case 6: return dz;          // (0, 1)
            case 7: return -dz;         // (0, -1)
            default: return 0.0f;
        }
    }
}

/// <summary>
/// A thread-safe, seedable repeating permutation table populated via LCG hash transitions.
/// Used to provide deterministic spatial decorrelation for multi-dimensional coordinate hashing.
/// </summary>
public class PermutationTable
{
    private const int Size = 16384;
    private const int Mask = Size - 1;
    private readonly int[] _p = new int[Size * 2];

    /// <summary>
    /// Gets the table size N (16384).
    /// </summary>
    public int TableSize => Size;

    /// <summary>
    /// Initializes a new instance of the <see cref="PermutationTable"/> class from a starting seed.
    /// </summary>
    /// <param name="seed">The LCG random seed.</param>
    public PermutationTable(int seed)
    {
        uint state = (uint)seed;

        // Populate table using the C runtime LCG parameters
        for (int i = 0; i < Size; i++)
        {
            state = state * 214013u + 2531011u;
            float r = ((state >> 16) & 0x7FFF) / 32768.0f;
            int val = (int)MathF.Floor(r * Size);
            _p[i] = val;
            _p[i + Size] = val;
        }
    }

    /// <summary>
    /// Hashes a 2D integer coordinate to a deterministic pseudo-random float in the [0, 1) range.
    /// </summary>
    public float Hash2D(int x, int z, int sigma = 0)
    {
        int sigmaMasked = sigma & Mask;
        int h1 = _p[_p[sigmaMasked] + (x & Mask)];
        int h2 = _p[h1 + (z & Mask)];
        return (float)h2 / Size;
    }

    /// <summary>
    /// Samples a single octave of coherent gradient Perlin noise at continuous coordinates.
    /// </summary>
    /// <param name="x">The continuous X coordinate.</param>
    /// <param name="z">The continuous Z coordinate.</param>
    /// <returns>A continuous, smooth noise value in [0.0, 1.0] range.</returns>
    public float SampleSinglePerlin(float x, float z, int subSeed = 0)
    {
        float xFloor = MathF.Floor(x);
        float zFloor = MathF.Floor(z);

        int xi = (int)xFloor;
        int zi = (int)zFloor;

        float xf = x - xFloor;
        float zf = z - zFloor;

        int xMask = xi & Mask;
        int zMask = zi & Mask;

        // Sub-seed offset is incorporated into the permutation table lookup
        int hSeed = _p[subSeed & Mask];
        int h00 = _p[(hSeed + xMask) & Mask];
        int h10 = _p[(hSeed + xMask + 1) & Mask];

        int g00 = _p[(h00 + zMask) & Mask] & 7;
        int g01 = _p[(h00 + zMask + 1) & Mask] & 7;
        int g10 = _p[(h10 + zMask) & Mask] & 7;
        int g11 = _p[(h10 + zMask + 1) & Mask] & 7;

        float u = NoiseMath.QuinticFade(xf);
        float v = NoiseMath.QuinticFade(zf);

        float d00 = NoiseMath.DotGradient(g00, xf, zf);
        float d01 = NoiseMath.DotGradient(g01, xf, zf - 1.0f);
        float d10 = NoiseMath.DotGradient(g10, xf - 1.0f, zf);
        float d11 = NoiseMath.DotGradient(g11, xf - 1.0f, zf - 1.0f);

        float x1 = d00 * (1.0f - u) + d10 * u;
        float x2 = d01 * (1.0f - u) + d11 * u;
        float raw = x1 * (1.0f - v) + x2 * v;

        // Map from [-1.0, 1.0] to [0.0, 1.0]
        return (raw + 1.0f) * 0.5f;
    }
}
