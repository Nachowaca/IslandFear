using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Enums

/// <summary>
/// Defines sorting strategy/priority for which objects survive proximity decimation when too close.
/// </summary>
public enum DecimationPriority
{
    Random,
    First,
    Last
}

#endregion

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that performs spatial Poisson-like proximity thinning of scattered objects using a spatial hash grid database.
/// </summary>
public partial class ProximityDecimationNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public ProximityDecimationNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="ProximityDecimationNode"/> class.
    /// </summary>
    public ProximityDecimationNode()
    {
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Thins out incoming instances using a 2D spatial grid.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float exclusionRadius = AssociatedResource != null ? AssociatedResource.ExclusionRadius : 5.0f;
        float sizeFactor = AssociatedResource != null ? AssociatedResource.SizeFactor : 0.0f;
        DecimationPriority priority = AssociatedResource != null ? AssociatedResource.Priority : DecimationPriority.Random;

        InstanceSet inputInstances = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputInstances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        var outputSet = new InstanceSet();
        if (inputInstances == null || inputInstances.Count == 0)
        {
            return outputSet;
        }

        // Sort candidates based on priority
        var candidates = new List<InstanceTransform>(inputInstances.Instances);
        if (priority == DecimationPriority.Last)
        {
            candidates.Reverse();
        }
        else if (priority == DecimationPriority.Random)
        {
            candidates.Sort((a, b) => a.Hash.CompareTo(b.Hash));
        }

        // Initialize spatial grid
        // The cell size should be set to a reasonable scale representing the maximum likely exclusion radius
        float maxExRadius = exclusionRadius * Math.Max(1.0f, 1.0f + sizeFactor * 5.0f);
        float gridCellSize = Math.Max(1.0f, maxExRadius);
        var grid = new ProximityGrid(gridCellSize);

        var accepted = new List<InstanceTransform>();

        foreach (var inst in candidates)
        {
            Vector3 pos = inst.Position;

            // Compute this entity's exclusion radius
            // R = D_exclude * (1.0 - F_size + S_x * F_size)
            float r_i = exclusionRadius * (1.0f - sizeFactor + inst.Scale.X * sizeFactor);

            // Query spatial neighbors
            // The maximum overlap check radius is r_i plus the maximum neighbor exclusion radius
            // We can conservatively query with 2 * maxExRadius
            float queryRadius = r_i + maxExRadius;
            var neighbors = grid.QueryNeighbors(pos, queryRadius);

            bool overlaps = false;
            foreach (var n in neighbors)
            {
                float r_n = exclusionRadius * (1.0f - sizeFactor + n.Scale.X * sizeFactor);
                float dOverlap = r_i + r_n;
                float dOverlapSq = dOverlap * dOverlap;

                float dx = pos.X - n.Position.X;
                float dz = pos.Z - n.Position.Z;
                float distSq = dx * dx + dz * dz;

                if (distSq < dOverlapSq)
                {
                    overlaps = true;
                    break;
                }
            }

            if (!overlaps)
            {
                grid.Add(inst);
                accepted.Add(inst);
            }
        }

        // Output results in their accepted order
        foreach (var inst in accepted)
        {
            outputSet.Add(inst);
        }

        return outputSet;
    }

    #region Inner Helper Class

    private class ProximityGrid
    {
        private readonly float _cellSize;
        private readonly Dictionary<(int, int), List<InstanceTransform>> _grid = new Dictionary<(int, int), List<InstanceTransform>>();

        public ProximityGrid(float cellSize)
        {
            _cellSize = cellSize > 0.01f ? cellSize : 1.0f;
        }

        private (int, int) GetCell(Vector3 pos)
        {
            int cx = (int)MathF.Floor(pos.X / _cellSize);
            int cz = (int)MathF.Floor(pos.Z / _cellSize);
            return (cx, cz);
        }

        public void Add(InstanceTransform inst)
        {
            var cell = GetCell(inst.Position);
            if (!_grid.TryGetValue(cell, out var list))
            {
                list = new List<InstanceTransform>();
                _grid[cell] = list;
            }
            list.Add(inst);
        }

        public List<InstanceTransform> QueryNeighbors(Vector3 pos, float radius)
        {
            var neighbors = new List<InstanceTransform>();
            int minX = (int)MathF.Floor((pos.X - radius) / _cellSize);
            int maxX = (int)MathF.Floor((pos.X + radius) / _cellSize);
            int minZ = (int)MathF.Floor((pos.Z - radius) / _cellSize);
            int maxZ = (int)MathF.Floor((pos.Z + radius) / _cellSize);

            for (int cx = minX; cx <= maxX; cx++)
            {
                for (int cz = minZ; cz <= maxZ; cz++)
                {
                    if (_grid.TryGetValue((cx, cz), out var list))
                    {
                        neighbors.AddRange(list);
                    }
                }
            }
            return neighbors;
        }
    }

    #endregion
}

#endregion
