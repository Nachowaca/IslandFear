using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that processes a SplatWeightSet, runs the ControlMapPacker to encode it into a 32-bit float Image,
/// and pushes it dynamically to a Terrain3D node.
/// </summary>
public partial class Terrain3DControlOutputNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public Terrain3DControlOutputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="Terrain3DControlOutputNode"/> class.
    /// </summary>
    public Terrain3DControlOutputNode()
    {
        Inputs.Add(new Port("splat_in", PortType.Splat, PortDirection.Input));
        Outputs.Add(new Port("control_out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the node, generating and returning the formatted packed control map Godot Image.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        return GenerateControlMap(ctx);
    }

    /// <summary>
    /// Generates the control map Godot Image from the connected input.
    /// </summary>
    /// <param name="ctx">The active generation context.</param>
    /// <returns>A Godot Image containing the packed control map, or <c>null</c> if input is missing.</returns>
    public Image GenerateControlMap(GenerationContext ctx)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] Error: No input connected to port 0.");
            return null;
        }

        var splat = link.SourceNode.PullData(ctx, link.SourcePortIndex) as SplatWeightSet;
        if (splat == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] Error: Pulled data is not a SplatWeightSet.");
            return null;
        }

        return ControlMapPacker.PackToControlMap(splat);
    }

    /// <summary>
    /// Pushes the generated control map image to a Terrain3D node in the scene tree.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="sceneRoot">The active scene root node used to resolve the Terrain3D NodePath.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="controlImage">The pre-generated control map image.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3D(Node sceneRoot, GenerationContext ctx, Image controlImage)
    {
        if (sceneRoot == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3D failed: sceneRoot is null.");
            return false;
        }

        if (controlImage == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3D failed: controlImage is null.");
            return false;
        }

        NodePath path = AssociatedResource != null ? AssociatedResource.TerrainNodePath : new NodePath("");
        if (path == null || path.IsEmpty)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3D failed: TerrainNodePath is not configured.");
            return false;
        }

        Node terrainNode = sceneRoot.GetNodeOrNull(path);
        if (terrainNode == null)
        {
            GD.PrintErr($"[Terrain3DControlOutputNode] PushToTerrain3D failed: Terrain3D node not found at path '{path}'.");
            return false;
        }

        return PushToTerrain3DNode(terrainNode, ctx, controlImage);
    }

    /// <summary>
    /// Directly pushes the generated control map image to the specified Terrain3D node.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="terrainNode">The Terrain3D node.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="controlImage">The pre-generated control map image.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3DNode(Node terrainNode, GenerationContext ctx, Image controlImage)
    {
        if (terrainNode == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3DNode failed: terrainNode is null.");
            return false;
        }

        if (controlImage == null)
        {
            GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3DNode failed: controlImage is null.");
            return false;
        }

        try
        {
            // Dynamic GDExtension binding via reflection-free dynamic calls
            // Retrieve Terrain3DData object: terrainNode.Get("data")
            var dataVar = terrainNode.Get("data");
            if (dataVar.Obj == null)
            {
                GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3DNode failed: 'data' property on Terrain3D is null.");
                return false;
            }

            GodotObject dataObject = dataVar.As<GodotObject>();
            if (dataObject == null)
            {
                GD.PrintErr("[Terrain3DControlOutputNode] PushToTerrain3DNode failed: Could not cast 'data' to GodotObject.");
                return false;
            }

            // Prepare images array [Nil, controlImage, Nil]
            var imagesArray = new Godot.Collections.Array();
            imagesArray.Resize(3);
            imagesArray[0] = new Variant();
            imagesArray[1] = controlImage;
            imagesArray[2] = new Variant();

            // Import parameters
            float scale = 1.0f;
            float offset = 0.0f;
            Vector3 globalPosition = ctx.WorldOrigin;

            // Call Terrain3DData.import_images(...)
            dataObject.Call("import_images", imagesArray, globalPosition, offset, scale);

            // Call Terrain3DData.update_maps() to trigger GPU texture arrays update
            dataObject.Call("update_maps");

            // GD.Print($"[Terrain3DControlOutputNode] Successfully pushed control map chunk {ctx.Coord} to Terrain3D at origin {globalPosition}.");
            return true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[Terrain3DControlOutputNode] Exception pushing control map to Terrain3D: {ex.Message}");
            GD.PrintErr(ex.StackTrace);
            return false;
        }
    }
}

#endregion
