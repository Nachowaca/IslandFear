using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;

namespace SimpleXTerrain;

/// <summary>
/// Thread-safe coordinator that schedules terrain chunk evaluation tasks onto background threads using Task.Run
/// with explicit cancellation support for clean assembly reloads.
/// </summary>
public class TerrainScheduler : IDisposable
{
    private readonly object _lock = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly ConcurrentDictionary<ChunkCoordinate, Task> _activeTasks = new();

    public void CancelAll()
    {
        _cts.Cancel();
        try
        {
            var tasks = _activeTasks.Values.ToArray();
            GD.Print($"[TerrainScheduler] CancelAll called. Active tasks count: {tasks.Length}");
            if (tasks.Length > 0)
            {
                // Wait up to 500ms for active background tasks to cancel cleanly.
                // Short wait to avoid close lag when exiting the editor.
                bool completed = Task.WaitAll(tasks, 500);
                if (!completed)
                {
                    GD.Print("[TerrainScheduler] Some background tasks are still cancelling, proceeding with shutdown.");
                }
                else
                {
                    GD.Print("[TerrainScheduler] All active tasks cancelled and completed successfully.");
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainScheduler] Exception in CancelAll: {ex.Message}");
        }
    }

    public void Dispose()
    {
        CancelAll();
        _cts.Dispose();
    }

    /// <summary>
    /// Thread-safe queue containing completed chunk data payloads ready for main thread integration.
    /// </summary>
    public ConcurrentQueue<ChunkPayload> CompletedQueue { get; } = new();

    /// <summary>
    /// Set of chunk coordinates currently undergoing background generation.
    /// Access must be protected or limited to the main thread.
    /// </summary>
    public HashSet<ChunkCoordinate> ScheduledCoords { get; } = new();

    public int ActiveTaskCount => _activeTasks.Count;

    /// <summary>
    /// Schedules a chunk coordinate for generation on a background thread.
    /// </summary>
    /// <param name="coord">The coordinate of the chunk to generate.</param>
    /// <param name="graphRoot">The terminal/root node of the evaluation graph.</param>
    /// <param name="highPriority">True if the task should be treated with high priority in the worker pool.</param>
    /// <param name="resolution">The target grid resolution (e.g. 512).</param>
    /// <param name="padding">The grid padding boundary width (e.g. 32).</param>
    /// <param name="worldOrigin">The absolute world origin coordinate.</param>
    /// <param name="worldSize">The world size of the chunk in meters.</param>
    public void Schedule(
        ChunkCoordinate coord, 
        TerrainNode graphRoot, 
        TerrainNode splatRoot,
        TerrainNode instancerRoot,
        bool highPriority, 
        int resolution = 512, 
        int padding = 32, 
        Vector3 worldOrigin = default, 
        float worldSize = 512.0f, 
        float heightScale = 500.0f,
        System.Collections.Generic.Dictionary<string, int> textureNameToIdMap = null)
    {
        if (graphRoot == null)
        {
            throw new ArgumentNullException(nameof(graphRoot));
        }

        lock (_lock)
        {
            if (_activeTasks.Count >= 4)
            {
                return; // Wait for a slot
            }

            if (ScheduledCoords.Contains(coord))
            {
                // Already scheduled or in progress
                return;
            }

            ScheduledCoords.Add(coord);
        }

        // Snapshot parameters into the thread-safe context
        GenerationContext ctx = new GenerationContext(coord, resolution, padding, worldOrigin, worldSize, heightScale, textureNameToIdMap, _cts.Token);

        // Schedule onto standard .NET ThreadPool using Task.Run (bypasses Godot interop boundaries)
        var task = Task.Run(() => RunGeneration(coord, ctx, graphRoot, splatRoot, instancerRoot, _cts.Token), _cts.Token);
        _activeTasks[coord] = task;
    }

    /// <summary>
    /// Executed strictly on background worker pool threads. Evaluates the terrain graph and queues results.
    /// </summary>
    private void RunGeneration(
        ChunkCoordinate coord, 
        GenerationContext ctx, 
        TerrainNode graphRoot, 
        TerrainNode splatRoot,
        TerrainNode instancerRoot,
        CancellationToken token)
    {
        try
        {
            // Abort if cancelled before we even start
            token.ThrowIfCancellationRequested();

            // Pull the height data from the terminal node
            var totalSw = Stopwatch.StartNew();
            object result = graphRoot.PullData(ctx, 0);
            totalSw.Stop();
            float totalMs = totalSw.ElapsedTicks / (float)Stopwatch.Frequency * 1000f;
            GD.Print($"[Perf] Chunk {coord} total: {totalMs:F0}ms (res={ctx.Resolution})");
            
            // Abort if cancelled during computation
            token.ThrowIfCancellationRequested();

            HeightMatrix heights = result as HeightMatrix;

            // Pull pre-packed control map image from splatRoot if available
            Image controlMap = null;
            if (splatRoot != null)
            {
                var splatResult = splatRoot.PullData(ctx, 0);
                controlMap = splatResult as Image;
            }

            token.ThrowIfCancellationRequested();

            // Pull scattered instances from instancerRoot if available
            InstanceSet instances = null;
            if (instancerRoot != null)
            {
                var instResult = instancerRoot.PullData(ctx, 0);
                instances = instResult as InstanceSet;
            }

            // Package into the payload and enqueue
            ChunkPayload payload = new ChunkPayload(coord, heights, controlMap, instances);
            CompletedQueue.Enqueue(payload);
        }
        catch (OperationCanceledException)
        {
            // Task was cleanly cancelled (e.g. during assembly reload)
            lock (_lock)
            {
                ScheduledCoords.Remove(coord);
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[TerrainScheduler] Exception generating chunk {coord} on background thread: {ex.Message}");
            GD.PrintErr(ex.StackTrace);
            
            // Clean up coordinate from scheduled pool even on failure
            lock (_lock)
            {
                ScheduledCoords.Remove(coord);
            }
        }
        finally
        {
            _activeTasks.TryRemove(coord, out _);
        }
    }
}
