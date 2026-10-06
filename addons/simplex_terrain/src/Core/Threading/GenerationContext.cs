namespace SimpleXTerrain;

using Godot;

/// <summary>
/// Execution sandbox representing the configuration and parameters for procedural generation of a single chunk.
/// Provides data isolation across background worker threads.
/// </summary>
public class GenerationContext
{
    /// <summary>
    /// Gets the coordinate of the chunk being generated.
    /// </summary>
    public ChunkCoordinate Coord { get; }

    /// <summary>
    /// Gets the resolution (unpadded size) of the chunk grid (e.g. 512 for 512x512).
    /// </summary>
    public int Resolution { get; }

    /// <summary>
    /// Gets the padding width (number of skirt/apron cells) surrounding the core chunk.
    /// </summary>
    public int Padding { get; }

    /// <summary>
    /// Gets the total width/height of the padded height matrix (Resolution + 2 * Padding).
    /// </summary>
    public int PaddedSize => Resolution + 2 * Padding;

    /// <summary>
    /// Gets the world-space coordinate corresponding to the bottom-left/origin corner (0,0) of this chunk.
    /// </summary>
    public Vector3 WorldOrigin { get; }

    /// <summary>
    /// Gets the world-space size/dimension of this chunk in meters.
    /// </summary>
    public float WorldSize { get; }

    /// <summary>
    /// Gets the world-space height scale factor.
    /// </summary>
    public float HeightScale { get; }

    /// <summary>
    /// Gets the mapping from texture name to Terrain3D texture asset ID.
    /// </summary>
    public System.Collections.Generic.Dictionary<string, int> TextureNameToIdMap { get; }

    /// <summary>
    /// Gets the cancellation token for the active generation task.
    /// </summary>
    public System.Threading.CancellationToken CancellationToken { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="GenerationContext"/> class.
    /// </summary>
    /// <param name="coord">The chunk coordinate.</param>
    /// <param name="resolution">The resolution.</param>
    /// <param name="padding">The padding width.</param>
    /// <param name="worldOrigin">The world space origin.</param>
    /// <param name="worldSize">The world space size in meters.</param>
    /// <param name="heightScale">The world-space height scale factor.</param>
    /// <param name="textureNameToIdMap">The mapping of texture name to asset ID.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    public GenerationContext(ChunkCoordinate coord, int resolution = 512, int padding = 32, Vector3 worldOrigin = default, float worldSize = 512.0f, float heightScale = 500.0f, System.Collections.Generic.Dictionary<string, int> textureNameToIdMap = null, System.Threading.CancellationToken cancellationToken = default)
    {
        Coord = coord;
        Resolution = resolution;
        Padding = padding;
        WorldOrigin = worldOrigin;
        WorldSize = worldSize;
        HeightScale = heightScale;
        TextureNameToIdMap = textureNameToIdMap ?? new System.Collections.Generic.Dictionary<string, int>();
        CancellationToken = cancellationToken;
    }

    /// <summary>
    /// Gets the detailed profiler for tracking node execution times.
    /// </summary>
    public ChunkProfiler Profiler { get; } = new();

    /// <summary>
    /// Allocates a new <see cref="HeightMatrix"/> sized to the padded dimensions of this context.
    /// </summary>
    /// <returns>A new <see cref="HeightMatrix"/> instance.</returns>
    public HeightMatrix AllocateHeightMatrix()
    {
        return new HeightMatrix(PaddedSize, PaddedSize);
    }
}

/// <summary>
/// Profiles evaluation times (Self and Total) of graph nodes during chunk generation.
/// </summary>
public class ChunkProfiler
{
    private readonly System.Diagnostics.Stopwatch _sw = new();
    private readonly System.Collections.Generic.Stack<string> _nodeStack = new();
    private readonly System.Collections.Generic.Dictionary<string, double> _nodeSelfTimes = new();
    private readonly System.Collections.Generic.Dictionary<string, double> _nodeTotalTimes = new();
    private long _lastTicks = 0;

    public void StartNode(string nodeId)
    {
        if (string.IsNullOrEmpty(nodeId)) return;

        if (!_sw.IsRunning)
        {
            _sw.Start();
            _lastTicks = _sw.ElapsedTicks;
        }

        long currentTicks = _sw.ElapsedTicks;
        double elapsedMs = (currentTicks - _lastTicks) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;

        if (_nodeStack.Count > 0)
        {
            string parentId = _nodeStack.Peek();
            _nodeSelfTimes.TryGetValue(parentId, out double val);
            _nodeSelfTimes[parentId] = val + elapsedMs;
        }

        _nodeStack.Push(nodeId);
        _lastTicks = currentTicks;
    }

    public void EndNode(string nodeId)
    {
        if (string.IsNullOrEmpty(nodeId)) return;

        long currentTicks = _sw.ElapsedTicks;
        double elapsedMs = (currentTicks - _lastTicks) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;

        if (_nodeStack.Count > 0 && _nodeStack.Peek() == nodeId)
        {
            _nodeStack.Pop();
            _nodeSelfTimes.TryGetValue(nodeId, out double val);
            _nodeSelfTimes[nodeId] = val + elapsedMs;
        }

        _lastTicks = currentTicks;
    }

    public void AddTotalTime(string nodeId, double ms)
    {
        if (string.IsNullOrEmpty(nodeId)) return;
        _nodeTotalTimes.TryGetValue(nodeId, out double val);
        _nodeTotalTimes[nodeId] = val + ms;
    }

    public System.Collections.Generic.Dictionary<string, (double TotalMs, double SelfMs)> GetResults()
    {
        var results = new System.Collections.Generic.Dictionary<string, (double TotalMs, double SelfMs)>();
        foreach (var kvp in _nodeSelfTimes)
        {
            _nodeTotalTimes.TryGetValue(kvp.Key, out double total);
            if (total == 0) total = kvp.Value;
            results[kvp.Key] = (total, kvp.Value);
        }
        foreach (var kvp in _nodeTotalTimes)
        {
            if (!results.ContainsKey(kvp.Key))
            {
                results[kvp.Key] = (kvp.Value, kvp.Value);
            }
        }
        return results;
    }
}

