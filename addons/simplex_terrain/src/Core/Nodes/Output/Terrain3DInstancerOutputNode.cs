using Godot;
using System;
using System.Linq;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime output node that registers procedurally scattered object instances with the Terrain3D instancer.
/// </summary>
public partial class Terrain3DInstancerOutputNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public Terrain3DInstancerOutputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="Terrain3DInstancerOutputNode"/> class.
    /// </summary>
    public Terrain3DInstancerOutputNode()
    {
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the node, pulling the generated InstanceSet.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] Error: No input connected to port 0.");
            return null;
        }

        return link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
    }

    /// <summary>
    /// Pushes the instances to the Terrain3D instancer in the scene tree.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="sceneRoot">The active scene root node used to resolve the Terrain3D NodePath.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="instances">The pre-generated InstanceSet.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3D(Node sceneRoot, GenerationContext ctx, InstanceSet instances)
    {
        if (sceneRoot == null)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3D failed: sceneRoot is null.");
            return false;
        }

        if (instances == null)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3D failed: instances is null.");
            return false;
        }

        NodePath path = AssociatedResource != null ? AssociatedResource.TerrainNodePath : new NodePath("");
        if (path == null || path.IsEmpty)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3D failed: TerrainNodePath is not configured.");
            return false;
        }

        Node terrainNode = sceneRoot.GetNodeOrNull(path);
        if (terrainNode == null)
        {
            GD.PrintErr($"[Terrain3DInstancerOutputNode] PushToTerrain3D failed: Terrain3D node not found at path '{path}'.");
            return false;
        }

        return PushToTerrain3DNode(terrainNode, ctx, instances);
    }

    /// <summary>
    /// Directly pushes the instances to the specified Terrain3D instancer.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="terrainNode">The Terrain3D node.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="instances">The pre-generated InstanceSet.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3DNode(Node terrainNode, GenerationContext ctx, InstanceSet instances)
    {
        if (terrainNode == null)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3DNode failed: terrainNode is null.");
            return false;
        }

        if (instances == null)
        {
            GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3DNode failed: instances is null.");
            return false;
        }

        int meshAssetId = AssociatedResource != null ? AssociatedResource.MeshAssetId : 0;
        bool clearExisting = AssociatedResource != null ? AssociatedResource.ClearExisting : true;

        try
        {
            // Dynamic GDExtension binding via reflection-free dynamic calls
            // Retrieve Terrain3DInstancer object: terrainNode.Get("instancer")
            var instancerVar = terrainNode.Get("instancer");
            if (instancerVar.Obj == null)
            {
                GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3DNode failed: 'instancer' property on Terrain3D is null.");
                return false;
            }

            GodotObject instancerObject = instancerVar.As<GodotObject>();
            if (instancerObject == null)
            {
                GD.PrintErr("[Terrain3DInstancerOutputNode] PushToTerrain3DNode failed: Could not cast 'instancer' to GodotObject.");
                return false;
            }

            // Group instances by finalMeshId:
            var groups = instances.Instances
                .GroupBy(i => i.MeshAssetId == 0 ? meshAssetId : i.MeshAssetId);

            foreach (var group in groups)
            {
                int currentMeshId = group.Key;

                // Optional clear by mesh
                if (clearExisting)
                {
                    instancerObject.Call("clear_by_mesh", currentMeshId);
                }

                // Convert InstanceSet to Array[Transform3D]
                var transformsArray = new Godot.Collections.Array();
                foreach (var inst in group)
                {
                    Transform3D t = new Transform3D(new Basis(inst.Rotation), inst.Position);
                    t.Basis = t.Basis.Scaled(inst.Scale);
                    transformsArray.Add(t);
                }

                // Call Terrain3DInstancer.add_transforms(...)
                instancerObject.Call("add_transforms", currentMeshId, transformsArray);
            }

            // GD.Print($"[Terrain3DInstancerOutputNode] Successfully registered {instances.Count} instances with Terrain3DInstancer.");
            return true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[Terrain3DInstancerOutputNode] Exception pushing instances to Terrain3DInstancer: {ex.Message}");
            GD.PrintErr(ex.StackTrace);
            return false;
        }
    }
}

#endregion
