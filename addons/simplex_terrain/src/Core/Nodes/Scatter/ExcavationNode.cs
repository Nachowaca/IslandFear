using Godot;
using System;

namespace SimpleXTerrain;

#region Enums

/// <summary>
/// Defines how the terrain is deformed under scattered objects.
/// </summary>
public enum ExcavationMode
{
    Flatten,
    Lower,
    Raise
}

#endregion

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that deforms the height matrix under scattered objects (e.g. flattening terrain under buildings).
/// </summary>
public partial class ExcavationNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public ExcavationNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="ExcavationNode"/> class.
    /// </summary>
    public ExcavationNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("height_out", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Locally deforms/excavates the heightmap under the scattered instances.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float radius = AssociatedResource != null ? AssociatedResource.Radius : 3.0f;
        float blendEdge = AssociatedResource != null ? AssociatedResource.BlendEdge : 1.5f;
        ExcavationMode mode = AssociatedResource != null ? AssociatedResource.Mode : ExcavationMode.Flatten;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

        HeightMatrix inputHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        InstanceSet instances = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            instances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        HeightMatrix hm = ctx.AllocateHeightMatrix();
        if (inputHM == null)
        {
            return hm;
        }

        // Copy input height values
        int width = inputHM.Width;
        int height = inputHM.Height;
        for (int z = 0; z < height; z++)
        {
            for (int x = 0; x < width; x++)
            {
                hm[x, z] = inputHM[x, z];
            }
        }

        if (instances == null || instances.Count == 0)
        {
            return hm;
        }

        float totalRadius = radius + blendEdge;
        float heightScaleVal = MathF.Abs(heightScale) > 1e-5f ? heightScale : 1.0f;

        foreach (var inst in instances.Instances)
        {
            Vector3 pos = inst.Position;

            // Target raw height level in height matrix
            float targetVal = pos.Y / heightScaleVal;

            // Calculate world space bounds for this stamp
            Vector3 minWorld = new Vector3(pos.X - totalRadius, pos.Y, pos.Z - totalRadius);
            Vector3 maxWorld = new Vector3(pos.X + totalRadius, pos.Y, pos.Z + totalRadius);

            // Map world space bounds to pixel bounding box on padded matrix
            Vector2 minPixel = CoordinateMapping.WorldToPixel(minWorld, ctx);
            Vector2 maxPixel = CoordinateMapping.WorldToPixel(maxWorld, ctx);

            int minX = Math.Clamp((int)MathF.Floor(minPixel.X), 0, width - 1);
            int maxX = Math.Clamp((int)MathF.Ceiling(maxPixel.X), 0, width - 1);
            int minZ = Math.Clamp((int)MathF.Floor(minPixel.Y), 0, height - 1);
            int maxZ = Math.Clamp((int)MathF.Ceiling(maxPixel.Y), 0, height - 1);

            for (int pz = minZ; pz <= maxZ; pz++)
            {
                for (int px = minX; px <= maxX; px++)
                {
                    Vector3 worldP = CoordinateMapping.PixelToWorld(new Vector2(px, pz), ctx);

                    float dx = worldP.X - pos.X;
                    float dz = worldP.Z - pos.Z;
                    float d = MathF.Sqrt(dx * dx + dz * dz);

                    if (d < totalRadius)
                    {
                        float t = 0.0f;
                        if (d > radius)
                        {
                            t = (d - radius) / (blendEdge > 0.001f ? blendEdge : 0.001f);
                            t = Math.Clamp(t, 0.0f, 1.0f);
                        }
                        float w = 2.0f * t * t * t - 3.0f * t * t + 1.0f;

                        float origVal = hm[px, pz];
                        float blended = targetVal * w + origVal * (1.0f - w);

                        if (mode == ExcavationMode.Flatten)
                        {
                            hm[px, pz] = blended;
                        }
                        else if (mode == ExcavationMode.Lower)
                        {
                            hm[px, pz] = MathF.Min(origVal, blended);
                        }
                        else if (mode == ExcavationMode.Raise)
                        {
                            hm[px, pz] = MathF.Max(origVal, blended);
                        }
                    }
                }
            }
        }

        return hm;
    }
}

#endregion
