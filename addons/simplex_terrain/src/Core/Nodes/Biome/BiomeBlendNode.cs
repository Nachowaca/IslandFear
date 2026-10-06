using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that normalizes and blends heights and splats from multiple biomes satisfying Partition of Unity.
/// </summary>
public partial class BiomeBlendNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public BiomeBlendNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="BiomeBlendNode"/> class.
    /// </summary>
    public BiomeBlendNode()
    {
        OnResourceSet();
    }

    /// <summary>
    /// Dynamically defines ports based on the associated parameter resource.
    /// </summary>
    public void OnResourceSet()
    {
        Inputs.Clear();
        int count = AssociatedResource != null ? AssociatedResource.BiomeCount : 2;
        if (count < 2) count = 2;

        for (int i = 0; i < count; i++)
        {
            Inputs.Add(new Port($"biome_{i}_height", PortType.Height, PortDirection.Input));
            Inputs.Add(new Port($"biome_{i}_splat", PortType.Splat, PortDirection.Input));
            Inputs.Add(new Port($"biome_{i}_weight", PortType.Mask, PortDirection.Input));
        }

        Outputs.Clear();
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("splat_out", PortType.Splat, PortDirection.Output));

        InitializePorts();
    }

    /// <summary>
    /// Blends inputs, performing height normalization and texture splat aggregation.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int count = AssociatedResource != null ? AssociatedResource.BiomeCount : 2;
        if (count < 2) count = 2;

        // Pull inputs
        HeightMatrix[] heights = new HeightMatrix[count];
        SplatWeightSet[] splats = new SplatWeightSet[count];
        HeightMatrix[] weights = new HeightMatrix[count];

        for (int i = 0; i < count; i++)
        {
            var heightLink = InputLinks[3 * i];
            if (heightLink.SourceNode != null)
            {
                heights[i] = heightLink.SourceNode.PullReadOnlyHeight(ctx, heightLink.SourcePortIndex);
            }

            var splatLink = InputLinks[3 * i + 1];
            if (splatLink.SourceNode != null)
            {
                splats[i] = splatLink.SourceNode.PullData(ctx, splatLink.SourcePortIndex) as SplatWeightSet;
            }

            var weightLink = InputLinks[3 * i + 2];
            if (weightLink.SourceNode != null)
            {
                weights[i] = weightLink.SourceNode.PullReadOnlyHeight(ctx, weightLink.SourcePortIndex);
            }
        }

        // Establish output dimensions
        int width = ctx.PaddedSize;
        int heightDimension = ctx.PaddedSize;
        
        for (int i = 0; i < count; i++)
        {
            if (heights[i] != null)
            {
                width = heights[i].Width;
                heightDimension = heights[i].Height;
                break;
            }
            if (weights[i] != null)
            {
                width = weights[i].Width;
                heightDimension = weights[i].Height;
                break;
            }
        }

        if (outputPortIndex == 0) // height_out (PortType.Height)
        {
            var blendedHeight = ctx.AllocateHeightMatrix();

            // Pre-gather active height and weight matrices to avoid inner loop null checks and indexer overhead
            var activeHeights = new HeightMatrix[count];
            var activeWeights = new HeightMatrix[count];
            int activeCount = 0;

            for (int i = 0; i < count; i++)
            {
                if (heights[i] != null && weights[i] != null)
                {
                    activeHeights[activeCount] = heights[i];
                    activeWeights[activeCount] = weights[i];
                    activeCount++;
                }
            }

            var outH = blendedHeight.RawData;

            for (int z = 0; z < heightDimension; z++)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
                int rowOff = z * width;
                for (int x = 0; x < width; x++)
                {
                    int idx = rowOff + x;
                    float sumH = 0.0f;
                    float sumW = 0.0f;

                    for (int i = 0; i < activeCount; i++)
                    {
                        float h = activeHeights[i].RawData[idx];
                        float w = activeWeights[i].RawData[idx];

                        sumH += h * w;
                        sumW += w;
                    }

                    if (sumW > 0.0f)
                    {
                        outH[idx] = sumH / sumW;
                    }
                    else
                    {
                        outH[idx] = 0.0f;
                    }
                }
            }

            return blendedHeight;
        }
        else if (outputPortIndex == 1) // splat_out (PortType.Splat)
        {
            // 1. Gather unique texture IDs
            var uniqueTexIds = new List<int>();
            SplatWeightSet firstNonNullSplat = null;

            for (int i = 0; i < count; i++)
            {
                var s = splats[i];
                if (s == null) continue;
                
                if (firstNonNullSplat == null)
                {
                    firstNonNullSplat = s;
                }

                if (s.TextureIdMap != null)
                {
                    foreach (int id in s.TextureIdMap)
                    {
                        if (!uniqueTexIds.Contains(id))
                        {
                            uniqueTexIds.Add(id);
                        }
                    }
                }
            }

            if (uniqueTexIds.Count == 0)
            {
                uniqueTexIds.Add(0);
                uniqueTexIds.Add(1);
            }
            uniqueTexIds.Sort();

            int splatWidth = firstNonNullSplat?.Width ?? width;
            int splatHeight = firstNonNullSplat?.Height ?? heightDimension;

            var blendedSplat = new SplatWeightSet(splatWidth, splatHeight, uniqueTexIds.Count);
            blendedSplat.TextureIdMap = uniqueTexIds.ToArray();

            // 2. Pre-build texture ID lookup array to avoid List.IndexOf in inner loop
            int maxId = 0;
            foreach (int id in uniqueTexIds)
            {
                if (id > maxId) maxId = id;
            }
            int[] texIdToAccumIndex = new int[maxId + 1];
            Array.Fill(texIdToAccumIndex, -1);
            for (int i = 0; i < uniqueTexIds.Count; i++)
            {
                texIdToAccumIndex[uniqueTexIds[i]] = i;
            }

            // Pre-gather active splat objects and weight matrices
            var activeSplats = new SplatWeightSet[count];
            var activeWeightsForSplat = new HeightMatrix[count];
            int activeSplatCount = 0;
            for (int i = 0; i < count; i++)
            {
                if (splats[i] != null && weights[i] != null)
                {
                    activeSplats[activeSplatCount] = splats[i];
                    activeWeightsForSplat[activeSplatCount] = weights[i];
                    activeSplatCount++;
                }
            }

            // 3. Aggregate and normalize weights per pixel
            float[] texAccum = new float[uniqueTexIds.Count];
            float[] outData = blendedSplat.RawData;
            int outWh = splatWidth * splatHeight;

            for (int z = 0; z < splatHeight; z++)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();
                int rowOff = z * splatWidth;
                for (int x = 0; x < splatWidth; x++)
                {
                    int idx = rowOff + x;
                    Array.Clear(texAccum, 0, texAccum.Length);
                    float totalSum = 0.0f;

                    for (int i = 0; i < activeSplatCount; i++)
                    {
                        float biomeWeight = activeWeightsForSplat[i].RawData[idx];
                        if (biomeWeight <= 0.00001f) continue;

                        var s = activeSplats[i];
                        var sData = s.RawData;
                        int layerCount = s.LayerCount;

                        for (int l = 0; l < layerCount; l++)
                        {
                            int texId = s.TextureIdMap[l];
                            int targetIdx = texIdToAccumIndex[texId];
                            if (targetIdx >= 0)
                            {
                                float val = sData[l * outWh + idx] * biomeWeight;
                                texAccum[targetIdx] += val;
                                totalSum += val;
                            }
                        }
                    }

                    if (totalSum > 0.0f)
                    {
                        float invTotalSum = 1.0f / totalSum;
                        for (int t = 0; t < uniqueTexIds.Count; t++)
                        {
                            outData[t * outWh + idx] = Math.Clamp(texAccum[t] * invTotalSum, 0.0f, 1.0f);
                        }
                    }
                    else
                    {
                        outData[idx] = 1.0f;
                        for (int t = 1; t < uniqueTexIds.Count; t++)
                        {
                            outData[t * outWh + idx] = 0.0f;
                        }
                    }
                }
            }

            return blendedSplat;
        }

        throw new ArgumentOutOfRangeException(nameof(outputPortIndex), $"Invalid output port index {outputPortIndex}.");
    }
}

#endregion
