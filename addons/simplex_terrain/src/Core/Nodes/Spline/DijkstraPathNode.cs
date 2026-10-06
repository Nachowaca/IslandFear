using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that computes the lowest-cost 3D topographic path between two points over a heightfield using 8-directional Dijkstra search.
/// </summary>
public partial class DijkstraPathNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public DijkstraPathNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="DijkstraPathNode"/> class.
    /// </summary>
    public DijkstraPathNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("cost_mask", PortType.Mask, PortDirection.Input)); // Optional extra cost map
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the node, running the Dijkstra pathfinding algorithm.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float startX = AssociatedResource != null ? AssociatedResource.StartX : 0.0f;
        float startZ = AssociatedResource != null ? AssociatedResource.StartZ : 0.0f;
        float endX = AssociatedResource != null ? AssociatedResource.EndX : 1.0f;
        float endZ = AssociatedResource != null ? AssociatedResource.EndZ : 1.0f;
        float slopeCost = AssociatedResource != null ? AssociatedResource.SlopeCost : 2.0f;
        float turnCost = AssociatedResource != null ? AssociatedResource.TurnCost : 0.5f;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

        HeightMatrix heightIn = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            heightIn = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix costMask = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            costMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        var outputSpline = new SplineSet();
        if (heightIn == null)
        {
            return outputSpline;
        }

        int width = heightIn.Width;
        int height = heightIn.Height;

        // 1. Map normalized positions to grid indices
        int startPx = Math.Clamp((int)MathF.Round(startX * (width - 1)), 0, width - 1);
        int startPz = Math.Clamp((int)MathF.Round(startZ * (height - 1)), 0, height - 1);
        int endPx = Math.Clamp((int)MathF.Round(endX * (width - 1)), 0, width - 1);
        int endPz = Math.Clamp((int)MathF.Round(endZ * (height - 1)), 0, height - 1);

        if (startPx == endPx && startPz == endPz)
        {
            // Start and end are same, return a small 2-point spline at this position
            Vector3 wPos = CoordinateMapping.PixelToWorld(new Vector2(startPx, startPz), ctx);
            wPos.Y = heightIn[startPx, startPz] * heightScale;
            outputSpline.AddCurve(new SplineCurve(new List<Vector3> { wPos, wPos + new Vector3(0.1f, 0f, 0.1f) }, CurveType.Open));
            return outputSpline;
        }

        // 2. Initialize Dijkstra grids
        float[,] dist = new float[width, height];
        (int x, int z)[,] parent = new (int, int)[width, height];
        bool[,] visited = new bool[width, height];

        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                dist[x, z] = float.PositiveInfinity;
                parent[x, z] = (-1, -1);
            }
        }

        dist[startPx, startPz] = 0.0f;
        var pq = new PriorityQueue<(int x, int z), float>();
        pq.Enqueue((startPx, startPz), 0.0f);

        // 8 Moore neighborhood directions
        int[] dx = { 0, 0, -1, 1, -1, -1, 1, 1 };
        int[] dz = { -1, 1, 0, 0, -1, 1, -1, 1 };

        float S_max = 1.0f; // 45 degrees slope gradient maximum passable threshold

        int checkCounter = 0;
        while (pq.Count > 0)
        {
            if (checkCounter++ % 128 == 0) ctx.CancellationToken.ThrowIfCancellationRequested();
            var curr = pq.Dequeue();
            int cx = curr.x;
            int cz = curr.z;

            if (visited[cx, cz]) continue;
            visited[cx, cz] = true;

            if (cx == endPx && cz == endPz) break; // Destination reached!

            float h_curr = heightIn[cx, cz];
            var currParent = parent[cx, cz];

            for (int dir = 0; dir < 8; dir++)
            {
                int nx = cx + dx[dir];
                int nz = cz + dz[dir];

                if (nx < 0 || nx >= width || nz < 0 || nz >= height) continue;
                if (visited[nx, nz]) continue;

                // A. Physical distance
                float d_diag = (dx[dir] != 0 && dz[dir] != 0) ? MathF.Sqrt(2f) : 1.0f;

                // B. Friction mask
                float F_friction = 2.0f;
                if (costMask != null)
                {
                    float M = costMask[nx, nz];
                    F_friction = (M > 0.999f) ? float.PositiveInfinity : (1.0f / (1.0f - M) + 1.0f);
                }

                if (float.IsInfinity(F_friction)) continue;

                // C. Incline slope cost
                float delta_pixel = ctx.WorldSize / (float)ctx.Resolution;
                float h_neighbor = heightIn[nx, nz];
                float elevation = MathF.Abs(h_neighbor - h_curr) * heightScale;
                float S = elevation / (delta_pixel * d_diag);

                float S_ratio = S / S_max;
                float F_elevation = (S_ratio > 0.999f) ? float.PositiveInfinity : (1.0f + slopeCost * (S_ratio / (1.0f - S_ratio)));
                if (float.IsInfinity(F_elevation)) continue;

                // D. Directional Straightening Penalty
                float F_straight = 1.0f;
                if (currParent != (-1, -1))
                {
                    Vector2 u = new Vector2(cx - currParent.Item1, cz - currParent.Item2).Normalized();
                    Vector2 v = new Vector2(nx - cx, nz - cz).Normalized();
                    float cos_theta = u.Dot(v);
                    F_straight = 1.0f + turnCost * (1.0f - cos_theta);
                }

                // E. Epsilon directional perturbation to avoid grid alignment bias
                bool r_hash = (((nx * 73856093) ^ (nz * 19349663)) % 2) == 0;
                float epsilon = r_hash ? 1.0f : 0.999f;

                float stepCost = F_friction * d_diag * F_elevation * F_straight * epsilon;
                float nextDist = dist[cx, cz] + stepCost;

                if (nextDist < dist[nx, nz] - 1e-4f)
                {
                    dist[nx, nz] = nextDist;
                    parent[nx, nz] = (cx, cz);
                    pq.Enqueue((nx, nz), nextDist);
                }
            }
        }

        // 3. Backtrack path reconstruction
        var pathPoints = new List<Vector3>();
        int currX = endPx;
        int currZ = endPz;

        if (float.IsInfinity(dist[endPx, endPz]))
        {
            // Destination unreachable, return empty spline
            return outputSpline;
        }

        int loopCounter = 0;
        while (loopCounter < 4096)
        {
            Vector3 wPos = CoordinateMapping.PixelToWorld(new Vector2(currX, currZ), ctx);
            wPos.Y = heightIn[currX, currZ] * heightScale;
            pathPoints.Add(wPos);

            if (currX == startPx && currZ == startPz) break;

            var p = parent[currX, currZ];
            if (p == (-1, -1)) break;

            currX = p.x;
            currZ = p.z;
            loopCounter++;
        }

        pathPoints.Reverse();

        if (pathPoints.Count >= 2)
        {
            outputSpline.AddCurve(new SplineCurve(pathPoints, CurveType.Open));
        }

        return outputSpline;
    }
}

#endregion
