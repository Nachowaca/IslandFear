namespace SimpleXTerrain;

using Godot;
using System;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that processes a <see cref="HeightMatrix"/>, extracts the core chunk region,
/// packages it as a Godot Float Image, and pushes it dynamically to a Terrain3D node.
/// </summary>
public partial class HeightOutputNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public HeightOutputNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="HeightOutputNode"/> class.
    /// </summary>
    public HeightOutputNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the node, generating the scaled HeightMatrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        if (outputPortIndex == 0)
        {
            var link = InputLinks[0];
            if (link.SourceNode == null)
            {
                GD.PrintErr("[HeightOutputNode] Error: No input connected to port 0.");
                return null;
            }

            var hm = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
            if (hm == null)
            {
                GD.PrintErr("[HeightOutputNode] Error: Pulled data is not a HeightMatrix.");
                return null;
            }

            float scale = AssociatedResource != null ? AssociatedResource.HeightScale : ctx.HeightScale;

            var scaledHM = new HeightMatrix(hm.Width, hm.Height);
            ReadOnlySpan<float> srcSpan = hm.AsReadOnlySpan();
            Span<float> destSpan = scaledHM.AsSpan();
            int total = hm.Width * hm.Height;
            for (int i = 0; i < total; i++)
            {
                destSpan[i] = srcSpan[i] * scale;
            }
            return scaledHM;
        }
        return null;
    }

    /// <summary>
    /// Generates the heightmap Godot Image from the connected input.
    /// </summary>
    /// <param name="ctx">The active generation context.</param>
    /// <returns>A Godot Image containing the normalized heightmap, or <c>null</c> if input is missing.</returns>
    public Image GenerateHeightmap(GenerationContext ctx)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            GD.PrintErr("[HeightOutputNode] Error: No input connected to port 0.");
            return null;
        }

        var hm = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        if (hm == null)
        {
            GD.PrintErr("[HeightOutputNode] Error: Pulled data is not a HeightMatrix.");
            return null;
        }

        int resolution = ctx.Resolution;
        int padding = ctx.Padding;

        float scale = AssociatedResource != null ? AssociatedResource.HeightScale : ctx.HeightScale;

        float[] rawFloats = new float[resolution * resolution];
        ReadOnlySpan<float> srcSpan = hm.AsReadOnlySpan();
        int hmWidth = hm.Width;

        // Extract the unpadded N x N core region
        for (int z = 0; z < resolution; z++)
        {
            int pz = z + padding;
            int rowOffset = z * resolution;
            int srcRowOffset = pz * hmWidth;
            for (int x = 0; x < resolution; x++)
            {
                int px = x + padding;
                float rawHeight = srcSpan[srcRowOffset + px];
                rawFloats[rowOffset + x] = rawHeight * scale;
            }
        }

        byte[] byteArray = new byte[rawFloats.Length * sizeof(float)];
        Buffer.BlockCopy(rawFloats, 0, byteArray, 0, byteArray.Length);

        Image heightImage = Image.CreateFromData(resolution, resolution, false, Image.Format.Rf, byteArray);

        return heightImage;
    }

    /// <summary>
    /// Pushes the generated heightmap image to a Terrain3D node in the scene tree.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="sceneRoot">The active scene root node used to resolve the Terrain3D NodePath.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="heightImage">The pre-generated heightmap image.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3D(Node sceneRoot, GenerationContext ctx, Image heightImage)
    {
        if (sceneRoot == null)
        {
            GD.PrintErr("[HeightOutputNode] PushToTerrain3D failed: sceneRoot is null.");
            return false;
        }

        if (heightImage == null)
        {
            GD.PrintErr("[HeightOutputNode] PushToTerrain3D failed: heightImage is null.");
            return false;
        }

        NodePath path = AssociatedResource != null ? AssociatedResource.TerrainNodePath : new NodePath("");
        if (path == null || path.IsEmpty)
        {
            GD.PrintErr("[HeightOutputNode] PushToTerrain3D failed: TerrainNodePath is not configured.");
            return false;
        }

        Node terrainNode = sceneRoot.GetNodeOrNull(path);
        if (terrainNode == null)
        {
            GD.PrintErr($"[HeightOutputNode] PushToTerrain3D failed: Terrain3D node not found at path '{path}'.");
            return false;
        }

        return PushToTerrain3DNode(terrainNode, ctx, heightImage);
    }

    /// <summary>
    /// Directly pushes the generated heightmap image to the specified Terrain3D node.
    /// MUST be called on the main/UI thread.
    /// </summary>
    /// <param name="terrainNode">The Terrain3D node.</param>
    /// <param name="ctx">The active generation context.</param>
    /// <param name="heightImage">The pre-generated heightmap image.</param>
    /// <returns><c>true</c> if successfully pushed; otherwise, <c>false</c>.</returns>
    public bool PushToTerrain3DNode(Node terrainNode, GenerationContext ctx, Image heightImage)
    {
        if (terrainNode == null)
        {
            GD.PrintErr("[HeightOutputNode] PushToTerrain3DNode failed: terrainNode is null.");
            return false;
        }

        if (heightImage == null)
        {
            GD.PrintErr("[HeightOutputNode] PushToTerrain3DNode failed: heightImage is null.");
            return false;
        }

        try
        {
            // Dynamic GDExtension binding via reflection-free dynamic calls
            // Retrieve Terrain3DData object: terrainNode.Get("data")
            var dataVar = terrainNode.Get("data");
            if (dataVar.Obj == null)
            {
                GD.PrintErr("[HeightOutputNode] PushToTerrain3DNode failed: 'data' property on Terrain3D is null.");
                return false;
            }

            GodotObject dataObject = dataVar.As<GodotObject>();
            if (dataObject == null)
            {
                GD.PrintErr("[HeightOutputNode] PushToTerrain3DNode failed: Could not cast 'data' to GodotObject.");
                return false;
            }

            // Prepare images array [heightImage, Nil, Nil]
            var imagesArray = new Godot.Collections.Array();
            imagesArray.Resize(3);
            imagesArray[0] = heightImage;
            imagesArray[1] = new Variant();
            imagesArray[2] = new Variant();

            // Import parameters
            // We have pre-scaled the pixel heights in the image to represent absolute world meters.
            // Therefore, we pass offset = 0.0f and scale = 1.0f to let Terrain3D read absolute meters directly.
            float scale = 1.0f;
            float offset = 0.0f;
            Vector3 globalPosition = ctx.WorldOrigin;

            // Call Terrain3DData.import_images(...)
            dataObject.Call("import_images", imagesArray, globalPosition, offset, scale);

            // Call Terrain3DData.update_maps() to trigger GPU texture arrays update
            dataObject.Call("update_maps");

            // GD.Print($"[HeightOutputNode] Successfully pushed chunk {ctx.Coord} to Terrain3D at origin {globalPosition} (scale={scale}, offset={offset}).");
            return true;
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[HeightOutputNode] Exception pushing heights to Terrain3D: {ex.Message}");
            GD.PrintErr(ex.StackTrace);
            return false;
        }
    }
}

#endregion
