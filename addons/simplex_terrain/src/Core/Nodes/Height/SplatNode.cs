using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that normalizes multi-layered texture masks using Partition of Unity blending
/// and outputs a SplatWeightSet.
/// </summary>
public partial class SplatNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public SplatNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SplatNode"/> class.
    /// </summary>
    public SplatNode()
    {
        // Default constructor calls OnResourceSet to initialize with default parameters
        OnResourceSet();
    }

    /// <summary>
    /// Re-evaluates ports based on the associated parameter resource.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        int layerCount = AssociatedResource != null ? AssociatedResource.LayerCount : 2;
        if (layerCount < 2) layerCount = 2;

        for (int i = 0; i < layerCount; i++)
        {
            Inputs.Add(new Port($"layer_{i}_mask", PortType.Mask, PortDirection.Input));
            Inputs.Add(new Port($"layer_{i}_biome_mask", PortType.Mask, PortDirection.Input));
        }

        Outputs.Clear();
        Outputs.Add(new Port("splat_out", PortType.Splat, PortDirection.Output));

        InitializePorts();
    }

    /// <summary>
    /// Evaluates dynamic multi-layer blending satisfying Partition of Unity.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int layerCount = AssociatedResource != null ? AssociatedResource.LayerCount : 2;
        if (layerCount < 2) layerCount = 2;

        // Fetch first non-null input mask to establish dimensions
        HeightMatrix firstMask = null;
        for (int i = 0; i < layerCount; i++)
        {
            var link = InputLinks[2 * i];
            if (link.SourceNode != null)
            {
                firstMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
                if (firstMask != null)
                {
                    break;
                }
            }
        }

        int width = firstMask != null ? firstMask.Width : ctx.PaddedSize;
        int height = firstMask != null ? firstMask.Height : ctx.PaddedSize;

        SplatWeightSet splat = new SplatWeightSet(width, height, layerCount);

        // Map local layers to Terrain3D texture asset IDs
        int[] texIds = new int[layerCount];
        for (int i = 0; i < layerCount; i++)
        {
            bool resolved = false;
            if (AssociatedResource != null && AssociatedResource.TextureNames != null && i < AssociatedResource.TextureNames.Count)
            {
                string texName = AssociatedResource.TextureNames[i];
                if (!string.IsNullOrEmpty(texName) && ctx.TextureNameToIdMap != null && ctx.TextureNameToIdMap.TryGetValue(texName, out int resolvedId))
                {
                    texIds[i] = resolvedId;
                    resolved = true;
                }
            }

            if (!resolved)
            {
                if (AssociatedResource != null && AssociatedResource.TextureIds != null && i < AssociatedResource.TextureIds.Count)
                {
                    texIds[i] = AssociatedResource.TextureIds[i];
                }
                else
                {
                    texIds[i] = i;
                }
            }
        }
        splat.TextureIdMap = texIds;

        // Pull mask inputs and biome mask inputs
        HeightMatrix[] masks = new HeightMatrix[layerCount];
        HeightMatrix[] biomeMasks = new HeightMatrix[layerCount];

        for (int i = 0; i < layerCount; i++)
        {
            var maskLink = InputLinks[2 * i];
            if (maskLink.SourceNode != null)
            {
                masks[i] = maskLink.SourceNode.PullReadOnlyHeight(ctx, maskLink.SourcePortIndex);
            }

            var biomeLink = InputLinks[2 * i + 1];
            if (biomeLink.SourceNode != null)
            {
                biomeMasks[i] = biomeLink.SourceNode.PullReadOnlyHeight(ctx, biomeLink.SourcePortIndex);
            }
        }

        // Retrieve raw backing float arrays for all input masks and biome masks to avoid virtual lookups inside loop
        float[][] maskArrays = new float[layerCount][];
        float[][] biomeArrays = new float[layerCount][];
        for (int i = 0; i < layerCount; i++)
        {
            if (masks[i] != null) maskArrays[i] = masks[i].RawData;
            if (biomeMasks[i] != null) biomeArrays[i] = biomeMasks[i].RawData;
        }

        float[] splatData = splat.RawData;
        Span<float> unnorm = stackalloc float[layerCount];
        int total = width * height;

        for (int idx = 0; idx < total; idx++)
        {
            if (idx % 1024 == 0)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
            }

            float sum = 0.0f;
            for (int i = 0; i < layerCount; i++)
            {
                float v = (maskArrays[i] != null) ? MathF.Max(0.0f, maskArrays[i][idx]) : 0.0f;
                float m = (biomeArrays[i] != null) ? MathF.Max(0.0f, biomeArrays[i][idx]) : 1.0f;
                float val = v * m;
                unnorm[i] = val;
                sum += val;
            }

            if (sum > 0.0f)
            {
                float invSum = 1.0f / sum;
                for (int i = 0; i < layerCount; i++)
                {
                    float w = unnorm[i] * invSum;
                    if (w < 0.0f) w = 0.0f;
                    else if (w > 1.0f) w = 1.0f;
                    splatData[i * total + idx] = w;
                }
            }
            else
            {
                for (int i = 0; i < layerCount; i++)
                {
                    splatData[i * total + idx] = 0.0f;
                }
            }
        }

        return splat;
    }
}

#endregion
