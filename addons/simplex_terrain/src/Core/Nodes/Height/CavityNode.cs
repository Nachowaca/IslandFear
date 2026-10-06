using Godot;
using System;

namespace SimpleXTerrain;

#region Resources

/// <summary>
/// Specifies the feature mode of the Cavity selection node.
/// </summary>
public enum CavityMode
{
    Concave,
    Convex,
    Both
}


#endregion

#region Nodes

/// <summary>
/// Runtime node that highlights concave depressions (valleys) and/or convex ridges using discrete Laplacian curvature.
/// </summary>
public partial class CavityNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public CavityNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="CavityNode"/> class.
    /// </summary>
    public CavityNode()
    {
        Inputs.Add(new Port("HeightIn", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("CavityOut", PortType.Mask, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Evaluates the discrete Laplacian curvature over the input height matrix.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        CavityMode mode = AssociatedResource != null ? AssociatedResource.Mode : CavityMode.Concave;
        float strength = AssociatedResource != null ? AssociatedResource.Strength : 1.0f;

        // Fetch upstream height matrix
        HeightMatrix inputHM = null;
        var link = InputLinks[0];
        if (link.SourceNode != null)
        {
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix mask = ctx.AllocateHeightMatrix();
        if (inputHM == null)
        {
            return mask;
        }

        int width = inputHM.Width;
        int height = inputHM.Height;

        // Special check: if matrix is too small, return empty
        if (width < 3 || height < 3)
        {
            return mask;
        }

        // Temporary rented HeightMatrix to hold raw curvature before boundary replication
        HeightMatrix rawC = ctx.AllocateHeightMatrix();
        try
        {
            // 1. Calculate discrete Laplacian for interior cells
            for (int z = 1; z < height - 1; z++)
            {
                for (int x = 1; x < width - 1; x++)
                {
                    float center = inputHM[x, z];
                    float sumNeighbors = inputHM[x - 1, z] + inputHM[x + 1, z] + inputHM[x, z - 1] + inputHM[x, z + 1];
                    
                    // C(x,z) = average of neighbors - center
                    rawC[x, z] = (sumNeighbors * 0.25f) - center;
                }
            }

            // 2. Perform boundary replication
            for (int z = 0; z < height; z++)
            {
                rawC[0, z] = rawC[1, z];
                rawC[width - 1, z] = rawC[width - 2, z];
            }
            for (int x = 0; x < width; x++)
            {
                rawC[x, 0] = rawC[x, 1];
                rawC[x, height - 1] = rawC[x, height - 2];
            }

            // 3. Extract and map cavity features to mask values
            for (int z = 0; z < height; z++)
            {
                for (int x = 0; x < width; x++)
                {
                    float cVal = rawC[x, z];
                    float outputVal = 0.0f;

                    switch (mode)
                    {
                        case CavityMode.Concave:
                            outputVal = MathF.Max(0.0f, cVal);
                            break;
                        case CavityMode.Convex:
                            outputVal = MathF.Max(0.0f, -cVal);
                            break;
                        case CavityMode.Both:
                            outputVal = MathF.Abs(cVal);
                            break;
                    }

                    mask[x, z] = Math.Clamp(outputVal * strength, 0.0f, 1.0f);
                }
            }
        }
        finally
        {
            rawC.Dispose();
        }

        return mask;
    }
}

#endregion
