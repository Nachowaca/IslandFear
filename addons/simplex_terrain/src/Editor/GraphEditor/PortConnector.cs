using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

/// <summary>
/// Handles connection validation between node ports in the terrain graph,
/// including port type compatibility checks and topological cycle detection.
/// </summary>
[Tool]
public static class PortConnector
{
    /// <summary>
    /// Checks if a source output port type can connect to a destination input port type.
    /// </summary>
    /// <param name="fromType">The type of the output port on the upstream node.</param>
    /// <param name="toType">The type of the input port on the downstream node.</param>
    /// <returns><c>true</c> if compatible; otherwise, <c>false</c>.</returns>
    public static bool ArePortsCompatible(PortType fromType, PortType toType)
    {
        switch (fromType)
        {
            case PortType.Height:
                // HEIGHT can connect to HEIGHT or MASK
                return toType == PortType.Height || toType == PortType.Mask;

            case PortType.Mask:
                // MASK can connect to MASK or HEIGHT
                return toType == PortType.Mask || toType == PortType.Height;

            case PortType.Splat:
                return toType == PortType.Splat;

            case PortType.Spline:
                return toType == PortType.Spline;

            case PortType.Instance:
                return toType == PortType.Instance;

            case PortType.Scalar:
                // SCALAR can broadcast fill a HEIGHT matrix
                return toType == PortType.Height || toType == PortType.Scalar;

            default:
                return false;
        }
    }

    /// <summary>
    /// Determines if adding a connection from <paramref name="fromNodeId"/> to <paramref name="toNodeId"/>
    /// would introduce a cycle in the directed graph.
    /// </summary>
    /// <param name="graph">The current graph resource.</param>
    /// <param name="fromNodeId">The source node ID.</param>
    /// <param name="toNodeId">The target node ID.</param>
    /// <returns><c>true</c> if a cycle would be created; otherwise, <c>false</c>.</returns>
    public static bool WouldCreateCycle(TerrainGraphResource graph, string fromNodeId, string toNodeId)
    {
        if (graph == null)
        {
            throw new ArgumentNullException(nameof(graph));
        }

        if (fromNodeId == toNodeId)
        {
            return true;
        }

        // Build adjacency list of existing connections (from NodeId -> List of to NodeIds)
        var adj = new Dictionary<string, List<string>>();
        
        // Initialize nodes in the adjacency list
        foreach (var node in graph.Nodes)
        {
            if (node != null && !string.IsNullOrEmpty(node.NodeId))
            {
                adj[node.NodeId] = new List<string>();
            }
        }

        // Add existing connections
        foreach (var conn in graph.Connections)
        {
            if (conn != null && !string.IsNullOrEmpty(conn.FromNodeId) && !string.IsNullOrEmpty(conn.ToNodeId))
            {
                if (adj.ContainsKey(conn.FromNodeId))
                {
                    adj[conn.FromNodeId].Add(conn.ToNodeId);
                }
            }
        }

        // Add the proposed new connection to the adjacency structure
        if (adj.ContainsKey(fromNodeId))
        {
            adj[fromNodeId].Add(toNodeId);
        }
        else
        {
            adj[fromNodeId] = new List<string> { toNodeId };
        }

        // Run cycle detection using DFS with recursion stack tracking
        var visited = new HashSet<string>();
        var recStack = new HashSet<string>();

        foreach (var nodeId in adj.Keys)
        {
            if (HasCycleDfs(nodeId, adj, visited, recStack))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasCycleDfs(string node, Dictionary<string, List<string>> adj, HashSet<string> visited, HashSet<string> recStack)
    {
        if (recStack.Contains(node))
        {
            return true;
        }

        if (visited.Contains(node))
        {
            return false;
        }

        visited.Add(node);
        recStack.Add(node);

        if (adj.TryGetValue(node, out var neighbors))
        {
            foreach (var neighbor in neighbors)
            {
                if (HasCycleDfs(neighbor, adj, visited, recStack))
                {
                    return true;
                }
            }
        }

        recStack.Remove(node);
        return false;
    }
}
