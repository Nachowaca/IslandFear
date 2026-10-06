namespace SimpleXTerrain;

using System;
using System.Buffers;

/// <summary>
/// Stores multi-layered, per-pixel terrain texture weights.
/// Backed by a rented flat float array using <see cref="ArrayPool{T}"/> to eliminate GC pressure.
/// Implements Partition of Unity normalization.
/// </summary>
public class SplatWeightSet : IDisposable
{
    private readonly float[] _data;
    private bool _disposed;

    /// <summary>
    /// Gets the horizontal pixel dimension of the splatmap.
    /// </summary>
    public int Width { get; }

    /// <summary>
    /// Gets the vertical pixel dimension of the splatmap.
    /// </summary>
    public int Height { get; }

    /// <summary>
    /// Gets the number of texture layers supported.
    /// </summary>
    public int LayerCount { get; }

    /// <summary>
    /// Gets the raw backing float array for this splat weight set.
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
    /// Gets or sets the mapping from local weight layer index to Terrain3D asset texture ID.
    /// </summary>
    public int[] TextureIdMap { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplatWeightSet"/> class.
    /// </summary>
    /// <param name="width">The width of the matrix.</param>
    /// <param name="height">The height of the matrix.</param>
    /// <param name="layerCount">The number of texture layers.</param>
    /// <exception cref="ArgumentException">Thrown when width, height, or layerCount is less than or equal to zero.</exception>
    public SplatWeightSet(int width, int height, int layerCount)
    {
        if (width <= 0 || height <= 0 || layerCount <= 0)
        {
            throw new ArgumentException("Width, Height, and LayerCount must be greater than zero.");
        }

        Width = width;
        Height = height;
        LayerCount = layerCount;
        _data = ArrayPool<float>.Shared.Rent(width * height * layerCount);
        _disposed = false;

        // Clear rented array to ensure zero default values
        Array.Clear(_data, 0, _data.Length);
    }

    /// <summary>
    /// Finalizes an instance of the <see cref="SplatWeightSet"/> class.
    /// </summary>
    ~SplatWeightSet()
    {
        Dispose(false);
    }

    private int GetFlatIndex(int layer, int x, int z)
    {
        return (layer * Width * Height) + (z * Width) + x;
    }

    /// <summary>
    /// Sets the raw float weight for a specific layer and coordinate.
    /// </summary>
    /// <param name="layer">The texture layer index.</param>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    /// <param name="value">The weight value [0, 1].</param>
    public void SetWeight(int layer, int x, int z, float value)
    {
        ThrowIfDisposed();
        if (layer >= 0 && layer < LayerCount && x >= 0 && x < Width && z >= 0 && z < Height)
        {
            _data[GetFlatIndex(layer, x, z)] = value;
        }
    }

    /// <summary>
    /// Retrieves the float weight for a specific layer and coordinate.
    /// Clamps out-of-bounds coordinate access to edge cells.
    /// </summary>
    /// <param name="layer">The texture layer index.</param>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    /// <returns>The weight value at the resolved coordinate.</returns>
    /// <exception cref="ArgumentOutOfRangeException">Thrown when layer index is invalid.</exception>
    public float GetWeight(int layer, int x, int z)
    {
        ThrowIfDisposed();
        if (layer < 0 || layer >= LayerCount)
        {
            throw new ArgumentOutOfRangeException(nameof(layer), "Layer index is out of bounds.");
        }

        x = Math.Clamp(x, 0, Width - 1);
        z = Math.Clamp(z, 0, Height - 1);

        return _data[GetFlatIndex(layer, x, z)];
    }

    /// <summary>
    /// Normalizes the weights of all layers at every pixel using the Partition of Unity algorithm.
    /// Ensures the sum of all texture weights at any pixel equals exactly one.
    /// </summary>
    public void NormalizeAll()
    {
        ThrowIfDisposed();

        int wh = Width * Height;
        // Pre-allocate sum buffer
        float[] sums = ArrayPool<float>.Shared.Rent(wh);
        Array.Clear(sums, 0, wh);

        // Pass 1: Accumulate per-pixel sums (CACHE-FRIENDLY — sequential per layer)
        for (int l = 0; l < LayerCount; l++)
        {
            int layerOff = l * wh;
            for (int i = 0; i < wh; i++)
            {
                sums[i] += _data[layerOff + i];
            }
        }

        // Pass 2: Normalize each layer (CACHE-FRIENDLY — sequential per layer)
        for (int l = 0; l < LayerCount; l++)
        {
            int layerOff = l * wh;
            for (int i = 0; i < wh; i++)
            {
                float s = sums[i];
                _data[layerOff + i] = s > 0f ? Math.Clamp(_data[layerOff + i] / s, 0f, 1f) : 0f;
            }
        }

        ArrayPool<float>.Shared.Return(sums);
    }

    /// <summary>
    /// Exposes the internal data array as a read-only span.
    /// </summary>
    public ReadOnlySpan<float> AsReadOnlySpan()
    {
        ThrowIfDisposed();
        return new ReadOnlySpan<float>(_data, 0, Width * Height * LayerCount);
    }

    /// <summary>
    /// Exposes the internal data array as a mutable span.
    /// </summary>
    public Span<float> AsSpan()
    {
        ThrowIfDisposed();
        return new Span<float>(_data, 0, Width * Height * LayerCount);
    }

    /// <summary>
    /// Exposes a copy of the active weight data as a flat array. Useful for verification.
    /// </summary>
    /// <returns>A new array copy of the splat weight data.</returns>
    public float[] ToArray()
    {
        ThrowIfDisposed();
        float[] copy = new float[Width * Height * LayerCount];
        Array.Copy(_data, copy, Width * Height * LayerCount);
        return copy;
    }

    /// <summary>
    /// Clones this splat weight set, renting a new buffer and copying the data.
    /// </summary>
    /// <returns>A new cloned SplatWeightSet.</returns>
    public SplatWeightSet Clone()
    {
        ThrowIfDisposed();
        SplatWeightSet copy = new SplatWeightSet(Width, Height, LayerCount);
        if (TextureIdMap != null)
        {
            copy.TextureIdMap = (int[])TextureIdMap.Clone();
        }
        Array.Copy(_data, copy._data, Width * Height * LayerCount);
        return copy;
    }

    /// <summary>
    /// Releases the rented array buffer back to the shared ArrayPool.
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
            throw new ObjectDisposedException(nameof(SplatWeightSet), "This SplatWeightSet instance has been disposed and its resources returned to the memory pool.");
        }
    }
}
