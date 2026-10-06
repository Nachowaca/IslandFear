namespace SimpleXTerrain;

using Godot;
using System;
using System.Collections.Generic;
using System.Reflection;

/// <summary>
/// Exception thrown when a cyclic dependency is detected in the terrain node graph.
/// </summary>
public class GraphCycleException : Exception
{
    /// <summary>
    /// Initializes a new instance of the <see cref="GraphCycleException"/> class.
    /// </summary>
    /// <param name="message">The exception message.</param>
    public GraphCycleException(string message) : base(message)
    {
    }
}

/// <summary>
/// Service class that manages node connections, evaluates graph topology, runs dirty sweeps,
/// and instantiates runtime graphs from serialized resources.
/// </summary>
public static class GraphEvaluator
{
    /// <summary>
    /// Performs a topological sort of the graph nodes using Kahn's Algorithm.
    /// Validates that the graph is a Directed Acyclic Graph (DAG) and throws if a cycle exists.
    /// </summary>
    /// <param name="nodes">The list of runtime nodes to sort.</param>
    /// <returns>A topologically sorted list of nodes (independent nodes first, dependent last).</returns>
    /// <exception cref="GraphCycleException">Thrown when a cyclic dependency is detected.</exception>
    public static List<TerrainNode> TopologicalSort(List<TerrainNode> nodes)
    {
        var downstream = new Dictionary<TerrainNode, List<TerrainNode>>();
        var inDegree = new Dictionary<TerrainNode, int>();

        // Initialize structures
        foreach (var node in nodes)
        {
            inDegree[node] = 0;
            downstream[node] = new List<TerrainNode>();
        }

        // Build adjacency and in-degree counts
        foreach (var node in nodes)
        {
            foreach (var inputNode in node.ConnectedInputs)
            {
                // Only count connections within the set of nodes being sorted
                if (nodes.Contains(inputNode))
                {
                    downstream[inputNode].Add(node);
                    inDegree[node]++;
                }
            }
        }

        // Find all nodes with in-degree 0 (no connected inputs)
        var queue = new Queue<TerrainNode>();
        foreach (var node in nodes)
        {
            if (inDegree[node] == 0)
            {
                queue.Enqueue(node);
            }
        }

        var sorted = new List<TerrainNode>();
        while (queue.Count > 0)
        {
            var u = queue.Dequeue();
            sorted.Add(u);

            foreach (var v in downstream[u])
            {
                inDegree[v]--;
                if (inDegree[v] == 0)
                {
                    queue.Enqueue(v);
                }
            }
        }

        // If sorted count doesn't match total count, a cycle exists
        if (sorted.Count != nodes.Count)
        {
            throw new GraphCycleException("A cyclic dependency was detected in the terrain node graph.");
        }

        return sorted;
    }

    /// <summary>
    /// Propagates a dirty state downstream from a modified node across the graph for a specific chunk.
    /// Uses a Breadth-First Search (BFS) sweep to mark all dependent nodes.
    /// </summary>
    /// <param name="changedNode">The node whose parameters or inputs changed.</param>
    /// <param name="allNodes">The list of all active nodes in the graph.</param>
    /// <param name="coord">The chunk coordinate to invalidate.</param>
    public static void PropagateDirty(TerrainNode changedNode, List<TerrainNode> allNodes, ChunkCoordinate coord)
    {
        // Build downstream adjacency map
        var downstream = new Dictionary<TerrainNode, List<TerrainNode>>();
        foreach (var node in allNodes)
        {
            downstream[node] = new List<TerrainNode>();
        }

        foreach (var node in allNodes)
        {
            foreach (var inputNode in node.ConnectedInputs)
            {
                if (downstream.ContainsKey(inputNode))
                {
                    downstream[inputNode].Add(node);
                }
            }
        }

        // BFS traversal
        var queue = new Queue<TerrainNode>();
        var visited = new HashSet<TerrainNode>();

        queue.Enqueue(changedNode);
        visited.Add(changedNode);

        while (queue.Count > 0)
        {
            var u = queue.Dequeue();
            u.MarkDirty(coord);

            foreach (var v in downstream[u])
            {
                if (!visited.Contains(v))
                {
                    visited.Add(v);
                    queue.Enqueue(v);
                }
            }
        }
    }

    /// <summary>
    /// Instantiates all runtime <see cref="TerrainNode"/> instances from a serialized <see cref="TerrainGraphResource"/>
    /// and returns the complete ID-to-Node dictionary.
    /// </summary>
    public static Dictionary<string, TerrainNode> InstantiateGraphNodes(TerrainGraphResource resource)
    {
        if (resource == null)
        {
            throw new ArgumentNullException(nameof(resource));
        }

        var runtimeNodes = new Dictionary<string, TerrainNode>();

        // 1. Instantiate all nodes
        foreach (var nodeResource in resource.Nodes)
        {
            if (nodeResource == null) continue;

            // Propagate the shared variables resource reference to each node resource
            nodeResource.SharedVariables = resource.SharedVariables;

            TerrainNode runtimeNode = CreateNodeInstance(nodeResource.NodeType);
            runtimeNode.NodeId = nodeResource.NodeId;
            
            // Link back to the resource containing parameters
            var prop = runtimeNode.GetType().GetProperty("AssociatedResource");
            if (prop != null && prop.CanWrite)
            {
                prop.SetValue(runtimeNode, nodeResource);
            }

            // Invokes custom resource initialization if defined on the node class
            var onResourceSetMethod = runtimeNode.GetType().GetMethod("OnResourceSet");
            if (onResourceSetMethod != null)
            {
                onResourceSetMethod.Invoke(runtimeNode, null);
            }

            runtimeNodes[nodeResource.NodeId] = runtimeNode;
        }

        // 2. Wire connections
        foreach (var conn in resource.Connections)
        {
            if (conn == null) continue;

            if (!runtimeNodes.TryGetValue(conn.FromNodeId, out var fromNode))
            {
                GD.PrintErr($"Graph Instantiation Warning: Source node ID '{conn.FromNodeId}' not found.");
                continue;
            }

            if (!runtimeNodes.TryGetValue(conn.ToNodeId, out var toNode))
            {
                GD.PrintErr($"Graph Instantiation Warning: Destination node ID '{conn.ToNodeId}' not found.");
                continue;
            }

            toNode.SetInput(conn.ToPort, fromNode, conn.FromPort);
        }

        // 3. Wire wireless portal connections
        foreach (var toNode in runtimeNodes.Values)
        {
            var toResProp = toNode.GetType().GetProperty("AssociatedResource");
            if (toResProp == null) continue;
            var toRes = toResProp.GetValue(toNode) as TerrainNodeResource;
            if (toRes == null) continue;

            if (!toRes.NodeType.Contains("Receiver")) continue;

            var portalNameProp = toRes.GetType().GetProperty("PortalName");
            if (portalNameProp == null) continue;

            string targetPortalName = portalNameProp.GetValue(toRes) as string;
            if (string.IsNullOrEmpty(targetPortalName)) continue;

            // Find matching transmitter
            TerrainNode foundTransmitter = null;
            foreach (var fromNode in runtimeNodes.Values)
            {
                var fromResProp = fromNode.GetType().GetProperty("AssociatedResource");
                if (fromResProp == null) continue;
                var fromRes = fromResProp.GetValue(fromNode) as TerrainNodeResource;
                if (fromRes == null) continue;

                var fromPortalNameProp = fromRes.GetType().GetProperty("PortalName");
                if (fromPortalNameProp == null) continue;

                string fromPortalName = fromPortalNameProp.GetValue(fromRes) as string;

                if (fromRes.NodeType.Contains("Transmitter") && fromPortalName == targetPortalName)
                {
                    foundTransmitter = fromNode;
                    break;
                }
            }

            if (foundTransmitter != null)
            {
                toNode.SetInput(0, foundTransmitter, 0);
            }
            else
            {
                GD.PrintErr($"[GraphEvaluator] Warning: No matching PortalTransmitterNode found for portal name '{targetPortalName}'");
            }
        }

        return runtimeNodes;
    }

    /// <summary>
    /// Instantiates a connected web of runtime <see cref="TerrainNode"/> instances from a serialized <see cref="TerrainGraphResource"/>.
    /// </summary>
    /// <param name="resource">The serialized graph resource containing node configurations and connection data.</param>
    /// <returns>The primary terminal/output node of the instantiated graph.</returns>
    /// <exception cref="InvalidOperationException">Thrown when node creation fails or reference mapping fails.</exception>
    public static TerrainNode InstantiateGraph(TerrainGraphResource resource)
    {
        var runtimeNodes = InstantiateGraphNodes(resource);
        var allNodesList = new List<TerrainNode>(runtimeNodes.Values);

        if (allNodesList.Count == 0)
        {
            throw new InvalidOperationException("Cannot instantiate an empty graph resource.");
        }

        // 1. Prioritize finding a HeightOutputNode in the graph
        TerrainNode heightOutput = null;
        foreach (var node in allNodesList)
        {
            if (node.GetType().Name == "HeightOutputNode")
            {
                heightOutput = node;
                break;
            }
        }

        if (heightOutput != null)
        {
            return heightOutput;
        }

        // 2. Fallback to standard terminal node detection (nodes that are NOT used as inputs)
        var inputNodeIds = new HashSet<string>();
        foreach (var conn in resource.Connections)
        {
            if (conn != null)
            {
                inputNodeIds.Add(conn.FromNodeId);
            }
        }

        TerrainNode terminalNode = null;
        foreach (var node in allNodesList)
        {
            if (!inputNodeIds.Contains(node.NodeId))
            {
                terminalNode = node;
                break;
            }
        }

        // Fallback to the first node if all nodes are interconnected or no connections exist
        return terminalNode ?? allNodesList[0];
    }

    /// <summary>
    /// Instantiates a C# class runtime node of the specified type name using reflection.
    /// </summary>
    public static TerrainNode CreateNodeInstance(string nodeType)
    {
        if (string.IsNullOrWhiteSpace(nodeType))
        {
            throw new ArgumentException("Node type cannot be null or empty.", nameof(nodeType));
        }

        // Try exact type name, and namespace lookups
        Type type = Type.GetType(nodeType)
                    ?? Type.GetType($"SimpleXTerrain.{nodeType}")
                    ?? Type.GetType($"SimpleXTerrain.Core.Nodes.{nodeType}");

        if (type == null)
        {
            // Scan currently loaded assemblies for the type
            foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                type = assembly.GetType(nodeType)
                       ?? assembly.GetType($"SimpleXTerrain.{nodeType}")
                       ?? assembly.GetType($"SimpleXTerrain.Core.Nodes.{nodeType}");

                if (type != null)
                {
                    break;
                }
            }
        }

        if (type == null)
        {
            throw new InvalidOperationException($"Could not resolve C# type for node type name '{nodeType}'. Make sure the node class exists and is compiled.");
        }

        if (!typeof(TerrainNode).IsAssignableFrom(type))
        {
            throw new InvalidOperationException($"Type '{type.FullName}' does not inherit from '{nameof(TerrainNode)}'.");
        }

        try
        {
            return (TerrainNode)Activator.CreateInstance(type);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Failed to instantiate node of type '{type.FullName}'. Ensure it has a public parameterless constructor.", ex);
        }
    }
}
