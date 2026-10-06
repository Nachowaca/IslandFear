namespace SimpleXTerrain;

using System;
using System.Buffers;
using Godot;

/// <summary>
/// A high-performance 2D grid matrix of float height values.
/// Uses <see cref="ArrayPool{T}"/> to avoid garbage collection spikes during procedural generation.
/// Implements bilinear sampling, discrete central-difference slope, and normal calculations.
/// </summary>
public class HeightMatrix : IDisposable
{
    private readonly float[] _data;
    private bool _disposed;

    /// <summary>
    /// Gets the horizontal pixel dimension of this heightmap.
    /// </summary>
    public int Width { get; }

    /// <summary>
    /// Gets the vertical pixel dimension of this heightmap.
    /// </summary>
    public int Height { get; }

    /// <summary>
    /// Gets the raw backing float array for this matrix.
    /// </summary>
    public float[] RawData
    {
        get
        {
            ThrowIfDisposed();
            return _data;
        }
    }

    /// <summary>
    /// Boundary clamping behaviors for coordinates outside the grid range.
    /// </summary>
    public enum BoundaryMode
    {
        /// <summary>
        /// Clamp the out-of-bounds coordinate to the edge cell (default).
        /// </summary>
        Clamp,

        /// <summary>
        /// Mirror coordinates back onto the grid.
        /// </summary>
        Mirror,

        /// <summary>
        /// Wrap coordinates around (repeat tiling).
        /// </summary>
        Wrap
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="HeightMatrix"/> class, renting the backing buffer from the shared ArrayPool.
    /// </summary>
    /// <param name="width">The width of the matrix.</param>
    /// <param name="height">The height of the matrix.</param>
    /// <exception cref="ArgumentException">Thrown when width or height is less than or equal to zero.</exception>
    public HeightMatrix(int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentException("Width and Height must be greater than zero.");
        }

        Width = width;
        Height = height;
        _data = ArrayPool<float>.Shared.Rent(width * height);
        Array.Clear(_data, 0, width * height);
        _disposed = false;
    }

    /// <summary>
    /// Finalizes an instance of the <see cref="HeightMatrix"/> class.
    /// </summary>
    ~HeightMatrix()
    {
        Dispose(false);
    }

    /// <summary>
    /// Gets or sets the height value at the specified integer pixel coordinate, applying boundary clamping on reads.
    /// Writes are ignored if they fall outside the boundary of the grid.
    /// </summary>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    public float this[int x, int z]
    {
        get
        {
            ThrowIfDisposed();
            return GetValue(x, z, BoundaryMode.Clamp);
        }
        set
        {
            ThrowIfDisposed();
            if (x >= 0 && x < Width && z >= 0 && z < Height)
            {
                _data[z * Width + x] = value;
            }
        }
    }

    /// <summary>
    /// Returns a raw Span over the active pixel data for zero-overhead inner loops.
    /// Single disposed check at call time. Caller indexes as: span[z * Width + x]
    /// </summary>
    public Span<float> AsSpan()
    {
        ThrowIfDisposed();
        return _data.AsSpan(0, Width * Height);
    }

    /// <summary>
    /// Returns a read-only span for consumers that only read data.
    /// </summary>
    public ReadOnlySpan<float> AsReadOnlySpan()
    {
        ThrowIfDisposed();
        return _data.AsSpan(0, Width * Height);
    }

    /// <summary>
    /// Retrieves a height value at the specified coordinate applying the chosen <see cref="BoundaryMode"/>.
    /// </summary>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    /// <param name="mode">The boundary handling mode.</param>
    /// <returns>The height value at the resolved coordinate.</returns>
    public float GetValue(int x, int z, BoundaryMode mode = BoundaryMode.Clamp)
    {
        ThrowIfDisposed();

        int cx = ClampCoordinate(x, Width, mode);
        int cz = ClampCoordinate(z, Height, mode);

        return _data[cz * Width + cx];
    }

    /// <summary>
    /// Performs bilinear sampling of the height grid using normalized coordinate ranges [0, 1].
    /// </summary>
    /// <param name="normX">The normalized X coordinate in [0, 1] range.</param>
    /// <param name="normZ">The normalized Z coordinate in [0, 1] range.</param>
    /// <returns>The interpolated float height value.</returns>
    public float SampleBilinear(float normX, float normZ)
    {
        ThrowIfDisposed();

        // Ref: 03_INTERPOLATION_AND_CURVES.md §4
        // Clamp normalized coordinates to [0, 1]
        normX = Math.Clamp(normX, 0f, 1f);
        normZ = Math.Clamp(normZ, 0f, 1f);

        // Map to pixel index space
        float px = normX * (Width - 1);
        float pz = normZ * (Height - 1);

        int x0 = (int)MathF.Floor(px);
        int z0 = (int)MathF.Floor(pz);
        int x1 = Math.Min(x0 + 1, Width - 1);
        int z1 = Math.Min(z0 + 1, Height - 1);

        float tx = px - x0;
        float tz = pz - z0;

        float h00 = this[x0, z0];
        float h10 = this[x1, z0];
        float h01 = this[x0, z1];
        float h11 = this[x1, z1];

        float hBottom = h00 * (1f - tx) + h10 * tx;
        float hTop = h01 * (1f - tx) + h11 * tx;

        return hBottom * (1f - tz) + hTop * tz;
    }

    /// <summary>
    /// Calculates the discrete incline slope in degrees at the specified coordinate.
    /// Uses 4-neighbor maximum absolute height delta (Math Bible Module 09 §1.A).
    /// </summary>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    /// <returns>The surface slope angle in degrees [0, 90].</returns>
    public float GetSlope(int x, int z, float cellSize = 1.0f)
    {
        ThrowIfDisposed();

        // Ref: 09_HEIGHT_AND_TERRAIN_MODIFIERS.md §1.A
        // D_delta = max( |H[x-1, z] - H[x, z]|, |H[x+1, z] - H[x, z]|, |H[x, z-1] - H[x, z]|, |H[x, z+1] - H[x, z]| )
        float h = GetValue(x, z);
        float dLeft = MathF.Abs(GetValue(x - 1, z) - h);
        float dRight = MathF.Abs(GetValue(x + 1, z) - h);
        float dUp = MathF.Abs(GetValue(x, z - 1) - h);
        float dDown = MathF.Abs(GetValue(x, z + 1) - h);

        float maxDelta = MathF.Max(MathF.Max(dLeft, dRight), MathF.Max(dUp, dDown));

        return MathF.Atan(maxDelta / cellSize) * (180.0f / MathF.PI);
    }

    /// <summary>
    /// Computes the surface normal vector at the specified coordinate.
    /// Uses boundary clamped central difference gradients assuming unit pixel size and height scaling.
    /// </summary>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    /// <param name="cellSize">The physical grid cell size.</param>
    /// <returns>The normalized 3D unit surface normal.</returns>
    public Vector3 GetNormal(int x, int z, float cellSize = 1.0f)
    {
        ThrowIfDisposed();

        // Ref: 05_GRID_AND_MATRIX_OPERATIONS.md §3
        // Gradient vector components: G_x = H[x-1, z] - H[x+1, z], G_z = H[x, z-1] - H[x, z+1], G_y = 2.0 (span width)
        float dx = GetValue(x - 1, z) - GetValue(x + 1, z);
        float dz = GetValue(x, z - 1) - GetValue(x, z + 1);

        Vector3 normal = new Vector3(-dx, 2.0f * cellSize, -dz);
        return normal.Normalized();
    }

    /// <summary>
    /// Clones this height matrix, renting a new buffer and copying the data.
    /// </summary>
    /// <returns>A new cloned HeightMatrix.</returns>
    public HeightMatrix Clone()
    {
        ThrowIfDisposed();
        HeightMatrix copy = new HeightMatrix(Width, Height);
        Array.Copy(_data, copy._data, Width * Height);
        return copy;
    }

    /// <summary>
    /// Fills the entire matrix with a constant height value.
    /// </summary>
    /// <param name="value">The value to write.</param>
    public void Fill(float value)
    {
        ThrowIfDisposed();
        Array.Fill(_data, value, 0, Width * Height);
    }

    /// <summary>
    /// Exposes a copy of the active height data as a flat array. Useful for verification and test assertions.
    /// </summary>
    /// <returns>A new array copy of the height matrix data.</returns>
    public float[] ToArray()
    {
        ThrowIfDisposed();
        float[] copy = new float[Width * Height];
        Array.Copy(_data, copy, Width * Height);
        return copy;
    }

    /// <summary>
    /// Releases the backing array buffer back to the shared ArrayPool.
    /// </summary>
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// Internal implementation of the Dispose pattern.
    /// </summary>
    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (_data != null)
            {
                ArrayPool<float>.Shared.Return(_data);
            }
            _disposed = true;
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(HeightMatrix));
        }
    }

    private static int ClampCoordinate(int val, int max, BoundaryMode mode)
    {
        if (val >= 0 && val < max)
            return val;

        switch (mode)
        {
            case BoundaryMode.Clamp:
                return Math.Clamp(val, 0, max - 1);

            case BoundaryMode.Mirror:
                if (max <= 1) return 0;
                while (val < 0 || val >= max)
                {
                    if (val < 0)
                        val = -val;
                    if (val >= max)
                        val = 2 * (max - 1) - val;
                }
                return Math.Clamp(val, 0, max - 1);

            case BoundaryMode.Wrap:
                int remainder = val % max;
                return remainder >= 0 ? remainder : remainder + max;

            default:
                return Math.Clamp(val, 0, max - 1);
        }
    }
}
