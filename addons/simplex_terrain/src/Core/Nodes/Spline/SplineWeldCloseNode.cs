using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that welds nearby spline endpoints and splits segments to form junctions and loops.
/// </summary>
public partial class SplineWeldCloseNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplineWeldCloseNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplineWeldCloseNode"/> class.
    /// </summary>
    public SplineWeldCloseNode()
    {
        Inputs.Add(new Port("spline_in", PortType.Spline, PortDirection.Input));
        Outputs.Add(new Port("spline_out", PortType.Spline, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Welds close open spline endpoints and segment crossings.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float weldRadius = AssociatedResource != null ? AssociatedResource.WeldRadius : 10.0f;
        weldRadius = Math.Max(0.01f, weldRadius);

        SplineSet inputSpline = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputSpline = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplineSet;
        }

        var outputSpline = new SplineSet();
        if (inputSpline == null || inputSpline.GetCurveCount() == 0)
        {
            return outputSpline;
        }

        // 1. Prepare curves as lists of points
        var curvesList = new List<List<Vector3>>();
        var typesList = new List<CurveType>();
        foreach (var curve in inputSpline.Curves)
        {
            if (curve.ControlPoints.Count >= 2)
            {
                curvesList.Add(new List<Vector3>(curve.ControlPoints));
                typesList.Add(curve.Type);
            }
        }

        // 2. Perform Segment Splitting at Proximity Points
        // Symmetrically check all control points Q against all segments of other curves
        for (int cIdx = 0; cIdx < curvesList.Count; cIdx++)
        {
            var ptsQ = curvesList[cIdx];
            for (int q = 0; q < ptsQ.Count; q++)
            {
                Vector3 Q = ptsQ[q];

                // Check against segments of all other curves
                for (int sIdx = 0; sIdx < curvesList.Count; sIdx++)
                {
                    if (sIdx == cIdx) continue;

                    var ptsS = curvesList[sIdx];
                    int segCount = typesList[sIdx] == CurveType.Closed ? ptsS.Count : ptsS.Count - 1;

                    // Calculate tangents for ptsS
                    SplineMath.ComputeTangents(ptsS, typesList[sIdx], out var tOut, out var tIn);

                    for (int s = 0; s < segCount; s++)
                    {
                        Vector3 p0 = ptsS[s];
                        Vector3 p3 = ptsS[(s + 1) % ptsS.Count];
                        Vector3 t0 = tOut[s];
                        Vector3 t3 = tIn[(s + 1) % ptsS.Count];

                        Vector3 p1 = p0 + t0;
                        Vector3 p2 = p3 + t3;

                        float t = SplineMath.ProjectPointOntoSegment(p0, p1, p2, p3, Q, out float distSq);
                        float dist = MathF.Sqrt(distSq);

                        if (dist < weldRadius && t > 0.05f && t < 0.95f)
                        {
                            // Split segment s at parameter t
                            SplineMath.SplitSegment(p0, p1, p2, p3, t,
                                out _, out _, out _, out Vector3 splitPoint,
                                out _, out _, out _, out _);

                            // Insert the split point
                            ptsS.Insert(s + 1, splitPoint);

                            // Recompute tangents since curve S has changed
                            SplineMath.ComputeTangents(ptsS, typesList[sIdx], out tOut, out tIn);
                            segCount = typesList[sIdx] == CurveType.Closed ? ptsS.Count : ptsS.Count - 1;
                            s++; // skip the newly created subsegment to avoid infinite loops
                        }
                    }
                }
            }
        }

        // 3. Cluster and Average Point Positions
        // Gather all points across all curves and find proximity groups
        var allPoints = new List<PointRef>();
        for (int c = 0; c < curvesList.Count; c++)
        {
            for (int p = 0; p < curvesList[c].Count; p++)
            {
                allPoints.Add(new PointRef(c, p, curvesList[c][p]));
            }
        }

        bool[] visited = new bool[allPoints.Count];
        for (int i = 0; i < allPoints.Count; i++)
        {
            if (visited[i]) continue;

            var cluster = new List<int> { i };
            visited[i] = true;

            // Simple BFS to find all points in cluster within weldRadius
            var queue = new Queue<int>();
            queue.Enqueue(i);

            while (queue.Count > 0)
            {
                int currIdx = queue.Dequeue();
                Vector3 currPos = allPoints[currIdx].Position;

                for (int j = 0; j < allPoints.Count; j++)
                {
                    if (visited[j]) continue;

                    if (currPos.DistanceTo(allPoints[j].Position) < weldRadius)
                    {
                        visited[j] = true;
                        cluster.Add(j);
                        queue.Enqueue(j);
                    }
                }
            }

            // Average positions of this cluster
            Vector3 average = Vector3.Zero;
            foreach (int idx in cluster)
            {
                average += allPoints[idx].Position;
            }
            average /= cluster.Count;

            // Set positions
            foreach (int idx in cluster)
            {
                var pRef = allPoints[idx];
                curvesList[pRef.CurveIndex][pRef.PointIndex] = average;
            }
        }

        // 4. Topological Reconnection (Chaining Segments)
        // Build list of all segments (directed edges)
        var edges = new List<SegmentEdge>();
        for (int c = 0; c < curvesList.Count; c++)
        {
            var pts = curvesList[c];
            int count = typesList[c] == CurveType.Closed ? pts.Count : pts.Count - 1;
            for (int i = 0; i < count; i++)
            {
                Vector3 start = pts[i];
                Vector3 end = pts[(i + 1) % pts.Count];

                if (start.DistanceTo(end) > 1e-4f) // skip degenerate
                {
                    edges.Add(new SegmentEdge(start, end));
                }
            }
        }

        // Local helper functions for quantization
        Vector3I Quantize(Vector3 v)
        {
            return new Vector3I(
                (int)MathF.Round(v.X * 1000.0f),
                (int)MathF.Round(v.Y * 1000.0f),
                (int)MathF.Round(v.Z * 1000.0f)
            );
        }

        bool CompareVector3I(Vector3I a, Vector3I b)
        {
            if (a.X != b.X) return a.X < b.X;
            if (a.Y != b.Y) return a.Y < b.Y;
            return a.Z < b.Z;
        }

        // Weld overlapping vertices to exact same float vectors using a spatial grid hash map
        var uniquePositions = new List<Vector3>();
        var grid = new Dictionary<Vector3I, List<Vector3>>();
        float cellSize = 0.01f;

        Vector3 GetUniquePos(Vector3 pos)
        {
            var centerKey = new Vector3I(
                (int)MathF.Floor(pos.X / cellSize),
                (int)MathF.Floor(pos.Y / cellSize),
                (int)MathF.Floor(pos.Z / cellSize)
            );

            for (int dx = -1; dx <= 1; dx++)
            {
                for (int dy = -1; dy <= 1; dy++)
                {
                    for (int dz = -1; dz <= 1; dz++)
                    {
                        var key = new Vector3I(centerKey.X + dx, centerKey.Y + dy, centerKey.Z + dz);
                        if (grid.TryGetValue(key, out var list))
                        {
                            foreach (var up in list)
                            {
                                if (up.DistanceTo(pos) < 1e-3f)
                                {
                                    return up;
                                }
                            }
                        }
                    }
                }
            }

            uniquePositions.Add(pos);
            if (!grid.TryGetValue(centerKey, out var cellList))
            {
                cellList = new List<Vector3>();
                grid[centerKey] = cellList;
            }
            cellList.Add(pos);
            return pos;
        }

        for (int i = 0; i < edges.Count; i++)
        {
            edges[i] = new SegmentEdge(GetUniquePos(edges[i].Start), GetUniquePos(edges[i].End));
        }

        // Remove duplicate edges (ignoring direction) in O(E) time
        var uniqueEdges = new List<SegmentEdge>();
        var seenEdges = new HashSet<(Vector3I, Vector3I)>();
        foreach (var edge in edges)
        {
            var k1 = Quantize(edge.Start);
            var k2 = Quantize(edge.End);
            var edgeKey = CompareVector3I(k1, k2) ? (k1, k2) : (k2, k1);
            if (seenEdges.Add(edgeKey))
            {
                uniqueEdges.Add(edge);
            }
        }

        // Build adjacency list for vertices using stable quantized keys
        var posMap = new Dictionary<Vector3I, Vector3>();
        foreach (var pos in uniquePositions)
        {
            posMap[Quantize(pos)] = pos;
        }

        var adj = new Dictionary<Vector3I, List<Vector3I>>();
        foreach (var edge in uniqueEdges)
        {
            var startKey = Quantize(edge.Start);
            var endKey = Quantize(edge.End);
            if (!adj.ContainsKey(startKey)) adj[startKey] = new List<Vector3I>();
            if (!adj.ContainsKey(endKey)) adj[endKey] = new List<Vector3I>();

            adj[startKey].Add(endKey);
            adj[endKey].Add(startKey);
        }

        // Trace paths using quantized keys
        var visitedVertices = new HashSet<Vector3I>();
        var tracedCurves = new List<List<Vector3>>();

        // Trace endpoints first (degree == 1) to form open paths
        var endpoints = adj.Keys.Where(k => adj[k].Count == 1).ToList();
        foreach (var startKey in endpoints)
        {
            if (visitedVertices.Contains(startKey)) continue;

            var path = new List<Vector3> { posMap[startKey] };
            visitedVertices.Add(startKey);

            Vector3I currKey = startKey;
            bool active = true;

            while (active)
            {
                active = false;
                foreach (var neighborKey in adj[currKey])
                {
                    if (!visitedVertices.Contains(neighborKey))
                    {
                        visitedVertices.Add(neighborKey);
                        path.Add(posMap[neighborKey]);
                        currKey = neighborKey;
                        active = true;
                        break;
                    }
                }
            }

            if (path.Count >= 2)
            {
                tracedCurves.Add(path);
            }
        }

        // Trace remaining loops (degree >= 2) using a separate visited set to prevent endpoint path collisions
        var loopVisited = new HashSet<Vector3I>();
        var loopStarts = adj.Keys.Where(k => adj[k].Count >= 2).ToList();
        foreach (var startKey in loopStarts)
        {
            if (loopVisited.Contains(startKey) || visitedVertices.Contains(startKey)) continue;

            var path = new List<Vector3> { posMap[startKey] };
            loopVisited.Add(startKey);

            Vector3I currKey = startKey;
            bool active = true;

            while (active)
            {
                active = false;
                foreach (var neighborKey in adj[currKey])
                {
                    if (!loopVisited.Contains(neighborKey) && !visitedVertices.Contains(neighborKey))
                    {
                        loopVisited.Add(neighborKey);
                        path.Add(posMap[neighborKey]);
                        currKey = neighborKey;
                        active = true;
                        break;
                    }
                    else if (neighborKey == startKey && path.Count >= 3)
                    {
                        // Loop closed!
                        tracedCurves.Add(path);
                        active = false;
                        break;
                    }
                }
            }
        }

        // Output results
        foreach (var path in tracedCurves)
        {
            bool isClosed = path.First().DistanceTo(path.Last()) < 1e-3f;
            var cleanPath = new List<Vector3>(path);
            if (isClosed && cleanPath.Count > 2)
            {
                cleanPath.RemoveAt(cleanPath.Count - 1); // remove duplicate wrap point for closed representation
                outputSpline.AddCurve(new SplineCurve(cleanPath, CurveType.Closed));
            }
            else
            {
                outputSpline.AddCurve(new SplineCurve(cleanPath, CurveType.Open));
            }
        }

        return outputSpline;
    }

    #region Helpers

    private struct PointRef
    {
        public int CurveIndex;
        public int PointIndex;
        public Vector3 Position;

        public PointRef(int cIdx, int pIdx, Vector3 pos)
        {
            CurveIndex = cIdx;
            PointIndex = pIdx;
            Position = pos;
        }
    }

    private struct SegmentEdge
    {
        public Vector3 Start;
        public Vector3 End;

        public SegmentEdge(Vector3 start, Vector3 end)
        {
            Start = start;
            End = end;
        }
    }

    #endregion
}

#endregion
