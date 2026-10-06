namespace SimpleXTerrain;

using Godot;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;

/// <summary>
/// Structure representing a connection link to an input port.
/// </summary>
public struct InputLink
{
    /// <summary>
    /// The upstream source node producing the data.
    /// </summary>
    public TerrainNode SourceNode;

    /// <summary>
    /// The index of the output port on the upstream source node.
    /// </summary>
    public int SourcePortIndex;
}

/// <summary>
/// Abstract runtime execution object representing a node in the procedural terrain generation graph.
/// Manages data flow, caching, and dirty state propagation.
/// </summary>
public abstract partial class TerrainNode : RefCounted
{
    private readonly object _lock = new();

    // Cache: ChunkCoordinate -> (OutputPortIndex -> Lazy evaluation)
    private readonly ConcurrentDictionary<ChunkCoordinate, ConcurrentDictionary<int, Lazy<object>>> _lazyCache = new();

    // Set of chunk coordinates for which this node is currently dirty.
    private readonly ConcurrentDictionary<ChunkCoordinate, byte> _dirtyChunks = new();

    /// <summary>
    /// Gets or sets the unique identifier of this node instance in the graph.
    /// </summary>
    public string NodeId { get; set; } = string.Empty;

    /// <summary>
    /// Gets the list of input ports defined by this node.
    /// </summary>
    public List<Port> Inputs { get; } = new();

    /// <summary>
    /// Gets the list of output ports defined by this node.
    /// </summary>
    public List<Port> Outputs { get; } = new();

    /// <summary>
    /// Gets the array of active connection links bound to the input ports.
    /// </summary>
    public InputLink[] InputLinks { get; private set; } = Array.Empty<InputLink>();

    /// <summary>
    /// Gets the list of active upstream source nodes connected directly to this node's inputs.
    /// Populated at graph compilation time.
    /// </summary>
    public List<TerrainNode> ConnectedInputs
    {
        get
        {
            var list = new List<TerrainNode>();
            lock (_lock)
            {
                foreach (var link in InputLinks)
                {
                    if (link.SourceNode != null)
                    {
                        list.Add(link.SourceNode);
                    }
                }
            }
            return list;
        }
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainNode"/> class.
    /// </summary>
    protected TerrainNode()
    {
    }

    /// <summary>
    /// Initializes the input link buffers. Should be called by subclasses after defining their ports.
    /// </summary>
    protected void InitializePorts()
    {
        lock (_lock)
        {
            InputLinks = new InputLink[Inputs.Count];
        }
    }

    /// <summary>
    /// Sets an input port connection link.
    /// </summary>
    /// <param name="portIndex">The local input port index on this node.</param>
    /// <param name="sourceNode">The upstream source node producing the input data.</param>
    /// <param name="sourcePortIndex">The output port index on the source node.</param>
    /// <exception cref="ArgumentOutOfRangeException">Thrown when portIndex is out of range.</exception>
    public void SetInput(int portIndex, TerrainNode sourceNode, int sourcePortIndex)
    {
        lock (_lock)
        {
            if (portIndex < 0 || portIndex >= InputLinks.Length)
            {
                throw new ArgumentOutOfRangeException(nameof(portIndex), $"Input port index {portIndex} is out of bounds (0 to {InputLinks.Length - 1}).");
            }

            // Remove downstream registration from old source node
            var oldSource = InputLinks[portIndex].SourceNode;
            if (oldSource != null)
            {
                oldSource.RemoveDownstreamConnection(this);
            }

            InputLinks[portIndex] = new InputLink
            {
                SourceNode = sourceNode,
                SourcePortIndex = sourcePortIndex
            };

            // Register downstream connection on new source node
            if (sourceNode != null)
            {
                sourceNode.AddDownstreamConnection(this);
            }
        }
    }

    private readonly List<TerrainNode> _downstreamConnections = new();

    internal void AddDownstreamConnection(TerrainNode node)
    {
        lock (_lock)
        {
            if (!_downstreamConnections.Contains(node))
            {
                _downstreamConnections.Add(node);
            }
        }
    }

    internal void RemoveDownstreamConnection(TerrainNode node)
    {
        lock (_lock)
        {
            _downstreamConnections.Remove(node);
        }
    }

    /// <summary>
    /// Pulls data from this node for the specified chunk and output port.
    /// Utilizes caching and dirty-state checks.
    /// </summary>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="outputPortIndex">The output port index to pull data from.</param>
    /// <returns>The generated data object.</returns>
    /// <exception cref="ArgumentOutOfRangeException">Thrown when outputPortIndex is out of bounds.</exception>
    public virtual object PullData(GenerationContext ctx, int outputPortIndex)
    {
        ctx.CancellationToken.ThrowIfCancellationRequested();

        if (outputPortIndex < 0 || outputPortIndex >= Outputs.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(outputPortIndex), $"Output port index {outputPortIndex} is out of bounds (0 to {Outputs.Count - 1}).");
        }

        var portCache = _lazyCache.GetOrAdd(ctx.Coord, _ => new ConcurrentDictionary<int, Lazy<object>>());
        var lazy = portCache.GetOrAdd(outputPortIndex, _ => new Lazy<object>(() =>
        {
            string profilerId = string.IsNullOrEmpty(NodeId) ? GetType().Name : NodeId;
            ctx.Profiler.StartNode(profilerId);
            var innerSw = Stopwatch.StartNew();

            var res = Evaluate(ctx, outputPortIndex);

            innerSw.Stop();
            double elapsedMs = innerSw.ElapsedTicks / (double)Stopwatch.Frequency * 1000.0;
            ctx.Profiler.AddTotalTime(profilerId, elapsedMs);
            ctx.Profiler.EndNode(profilerId);

            MarkClean(ctx.Coord);
            return res;
        }));

        var sw = Stopwatch.StartNew();
        var result = lazy.Value;
        sw.Stop();
        
        float ms = sw.ElapsedTicks / (float)Stopwatch.Frequency * 1000f;
        if (ms > 0.1f)
            GD.Print($"[Perf] {GetType().Name} (NodeId={NodeId}) chunk({ctx.Coord}) port={outputPortIndex}: {ms:F2}ms");

        return result;
    }

    /// <summary>
    /// Returns the cached HeightMatrix WITHOUT cloning.
    /// Use when the calling node only READS the data (BlendNode, SplatNode, etc.)
    /// </summary>
    public HeightMatrix PullReadOnlyHeight(GenerationContext ctx, int port)
    {
        return PullData(ctx, port) as HeightMatrix;  // cached, NOT cloned
    }

    /// <summary>
    /// Returns a CLONE of the cached HeightMatrix for safe writing.
    /// Use when the calling node MUTATES the data (ErosionNode, etc.)
    /// </summary>
    public HeightMatrix PullMutableHeight(GenerationContext ctx, int port)
    {
        var hm = PullData(ctx, port) as HeightMatrix;
        return hm?.Clone();  // clone for writing
    }

    /// <summary>
    /// Internal mathematical and logic evaluation of the node. Must be implemented by concrete subclasses.
    /// </summary>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="outputPortIndex">The output port index being requested.</param>
    /// <returns>The calculated data object.</returns>
    protected abstract object Evaluate(GenerationContext ctx, int outputPortIndex);

    /// <summary>
    /// Determines whether the node cache is marked dirty for the specified chunk coordinate.
    /// </summary>
    /// <param name="coord">The chunk coordinate.</param>
    /// <returns><c>true</c> if dirty; otherwise, <c>false</c>.</returns>
    public bool IsDirty(ChunkCoordinate coord)
    {
        // If we've never calculated for this chunk, it's conceptually dirty
        if (!_lazyCache.ContainsKey(coord))
        {
            return true;
        }
        return _dirtyChunks.ContainsKey(coord);
    }

    /// <summary>
    /// Marks the cache dirty for the specified chunk coordinate.
    /// </summary>
    /// <param name="coord">The chunk coordinate.</param>
    public void MarkDirty(ChunkCoordinate coord)
    {
        _dirtyChunks.TryAdd(coord, 0);
        ClearCacheForChunkLocal(coord);

        List<TerrainNode> connections;
        lock (_lock)
        {
            connections = new List<TerrainNode>(_downstreamConnections);
        }
        foreach (var downstream in connections)
        {
            if (!downstream.IsDirty(coord))
            {
                downstream.MarkDirty(coord);
            }
        }
    }

    private void ClearCacheForChunkLocal(ChunkCoordinate coord)
    {
        if (_lazyCache.TryRemove(coord, out var portCache))
        {
            foreach (var lazyVal in portCache.Values)
            {
                if (lazyVal.IsValueCreated && lazyVal.Value is IDisposable disp)
                {
                    disp.Dispose();
                }
            }
        }
    }

    /// <summary>
    /// Clears the dirty flag for the specified chunk coordinate.
    /// </summary>
    /// <param name="coord">The chunk coordinate.</param>
    public void MarkClean(ChunkCoordinate coord)
    {
        _dirtyChunks.TryRemove(coord, out _);
    }

    /// <summary>
    /// Clears all cached data across all chunks and marks the node as dirty.
    /// </summary>
    public virtual void ClearCache()
    {
        var keys = new List<ChunkCoordinate>(_lazyCache.Keys);
        foreach (var key in keys)
        {
            ClearCacheForChunk(key);
        }
    }

    /// <summary>
    /// Clears cached data specifically for the given chunk coordinate.
    /// </summary>
    public virtual void ClearCacheForChunk(ChunkCoordinate coord)
    {
        if (_lazyCache.TryRemove(coord, out var portCache))
        {
            foreach (var lazyVal in portCache.Values)
            {
                if (lazyVal.IsValueCreated && lazyVal.Value is IDisposable disp)
                {
                    disp.Dispose();
                }
            }
        }
        _dirtyChunks.TryRemove(coord, out _);

        // Recursively clear downstream caches for this chunk
        List<TerrainNode> connections;
        lock (_lock)
        {
            connections = new List<TerrainNode>(_downstreamConnections);
        }
        foreach (var downstream in connections)
        {
            downstream.ClearCacheForChunk(coord);
        }
    }
}
