using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that interconnects scattered points into a road/path network using the Gabriel Graph empty-circle criterion.
/// </summary>
public partial class GabrielGraphNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public GabrielGraphNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="GabrielGraphNode"/> class.
    /// </summary>
    public GabrielGraphNode()
    {
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Interlinks isolated points using empty diametric circle empty-sphere criteria.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float maxEdgeLength = AssociatedResource != null ? AssociatedResource.MaxEdgeLength : 500.0f;
        int maxLinks = AssociatedResource != null ? AssociatedResource.MaxLinks : 4;

        maxEdgeLength = Math.Max(0.1f, maxEdgeLength);
        maxLinks = Math.Max(1, maxLinks);

        InstanceSet inputInstances = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputInstances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        var outputSpline = new SplineSet();
        if (inputInstances == null || inputInstances.Count < 2)
        {
            return outputSpline;
        }

        int n = inputInstances.Count;
        var instances = new List<InstanceTransform>(inputInstances.Instances);

        // Keep track of degrees for each node
        int[] degrees = new int[n];
        var proposedEdges = new List<ProposedEdge>();

        float maxEdgeLenSq = maxEdgeLength * maxEdgeLength;

        // 1. Build spatial partitioning grid
        var grid = new Dictionary<Vector2I, List<int>>();
        float cellSize = maxEdgeLength;
        for (int i = 0; i < n; i++)
        {
            Vector3 pos = instances[i].Position;
            var cell = new Vector2I((int)MathF.Floor(pos.X / cellSize), (int)MathF.Floor(pos.Z / cellSize));
            if (!grid.TryGetValue(cell, out var cellList))
            {
                cellList = new List<int>();
                grid[cell] = cellList;
            }
            cellList.Add(i);
        }

        // 2. For each node, find the top T_max closest neighbors
        int tMax = 16;
        var candidates = new List<int>[n];
        for (int i = 0; i < n; i++)
        {
            Vector3 posI = instances[i].Position;
            var cellI = new Vector2I((int)MathF.Floor(posI.X / cellSize), (int)MathF.Floor(posI.Z / cellSize));
            
            var list = new List<(int idx, float distSq)>();
            for (int dx = -1; dx <= 1; dx++)
            {
                for (int dz = -1; dz <= 1; dz++)
                {
                    var cell = new Vector2I(cellI.X + dx, cellI.Y + dz);
                    if (grid.TryGetValue(cell, out var cellList))
                    {
                        foreach (int j in cellList)
                        {
                            if (j == i) continue;
                            float dSq = posI.DistanceSquaredTo(instances[j].Position);
                            if (dSq <= maxEdgeLenSq)
                            {
                                list.Add((j, dSq));
                            }
                        }
                    }
                }
            }

            list.Sort((a, b) => a.distSq.CompareTo(b.distSq));
            
            var cList = new List<int>();
            int limit = Math.Min(list.Count, tMax);
            for (int k = 0; k < limit; k++)
            {
                cList.Add(list[k].idx);
            }
            candidates[i] = cList;
        }

        // 3. Perform reciprocal verification and empty-circle checks
        for (int i = 0; i < n; i++)
        {
            Vector3 posI = instances[i].Position;
            Vector2 pi = new Vector2(posI.X, posI.Z);

            foreach (int j in candidates[i])
            {
                if (j <= i) continue;

                // Reciprocal verification: both must consider each other neighbors
                if (!candidates[j].Contains(i)) continue;

                Vector3 posJ = instances[j].Position;
                Vector2 pj = new Vector2(posJ.X, posJ.Z);
                float distSq = posI.DistanceSquaredTo(posJ);

                bool isGabriel = true;

                // Empty diametric circle check in 2D using closest neighbors
                foreach (int k in candidates[i])
                {
                    if (k == j) continue;

                    Vector3 posK = instances[k].Position;
                    Vector2 pk = new Vector2(posK.X, posK.Z);

                    float dot = (pk - pi).Dot(pk - pj);
                    if (dot <= 1e-4f)
                    {
                        isGabriel = false;
                        break;
                    }
                }

                if (isGabriel)
                {
                    proposedEdges.Add(new ProposedEdge(i, j, distSq));
                }
            }
        }

        // Sort proposed edges in ascending order of length to connect shorter edges first
        proposedEdges.Sort((a, b) => a.LengthSq.CompareTo(b.LengthSq));

        // 3. Connect edges respecting degree limitation
        foreach (var edge in proposedEdges)
        {
            int u = edge.U;
            int v = edge.V;

            if (degrees[u] < maxLinks && degrees[v] < maxLinks)
            {
                degrees[u]++;
                degrees[v]++;

                // Add to output as a simple 2-point open curve segment
                var curvePts = new List<Vector3> { instances[u].Position, instances[v].Position };
                outputSpline.AddCurve(new SplineCurve(curvePts, CurveType.Open));
            }
        }

        return outputSpline;
    }

    #region Helpers

    private struct ProposedEdge
    {
        public int U;
        public int V;
        public float LengthSq;

        public ProposedEdge(int u, int v, float lenSq)
        {
            U = u;
            V = v;
            LengthSq = lenSq;
        }
    }

    #endregion
}

#endregion
