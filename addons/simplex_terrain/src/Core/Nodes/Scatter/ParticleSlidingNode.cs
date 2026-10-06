using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that simulates particles sliding downhill along slope gradients of a height field.
/// </summary>
public partial class ParticleSlidingNode : TerrainNode
{
    public ParticleSlidingNodeResource AssociatedResource { get; set; }

    public ParticleSlidingNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int maxSteps = AssociatedResource != null ? AssociatedResource.MaxSteps : 100;
        float stopSlopeDeg = AssociatedResource != null ? AssociatedResource.StopSlopeDeg : 15.0f;
        float stepSize = AssociatedResource != null ? AssociatedResource.StepSize : 0.5f;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

        HeightMatrix heightHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            heightHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        InstanceSet instanceSetIn = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            instanceSetIn = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        var instanceSetOut = new InstanceSet();
        if (instanceSetIn == null)
        {
            return instanceSetOut;
        }

        if (heightHM == null)
        {
            // No heightmap to slide on, return original instances
            foreach (var inst in instanceSetIn.Instances)
            {
                instanceSetOut.Add(inst);
            }
            return instanceSetOut;
        }

        float deltaPixel = ctx.WorldSize / ctx.Resolution;
        // Stop slope threshold remapped to height delta limit (Ref: §10.B)
        float tanTheta = MathF.Tan(stopSlopeDeg * MathF.PI / 180.0f);
        float deltaStop = tanTheta * deltaPixel / heightScale;

        foreach (var inst in instanceSetIn.Instances)
        {
            Vector3 currentPos = inst.Position;

            for (int step = 0; step < maxSteps; step++)
            {
                Vector2 pixelPos = CoordinateMapping.WorldToPixel(currentPos, ctx);
                
                // If it goes outside the height matrix boundary, stop sliding
                if (pixelPos.X < 0 || pixelPos.X >= heightHM.Width - 1 || pixelPos.Y < 0 || pixelPos.Y >= heightHM.Height - 1)
                {
                    break;
                }

                int ix = Math.Clamp((int)MathF.Floor(pixelPos.X), 0, heightHM.Width - 2);
                int iz = Math.Clamp((int)MathF.Floor(pixelPos.Y), 0, heightHM.Height - 2);

                float h_00 = heightHM.GetValue(ix, iz);
                float h_10 = heightHM.GetValue(ix + 1, iz);
                float h_01 = heightHM.GetValue(ix, iz + 1);
                float h_11 = heightHM.GetValue(ix + 1, iz + 1);

                // Compute horizontal normal gradients (Ref: §10.A)
                float xNormal = (h_01 - h_11 + h_00 - h_10) / 2.0f;
                float zNormal = (h_10 - h_11 + h_00 - h_01) / 2.0f;

                // Max slope gradient
                float deltaSlope = MathF.Max(MathF.Abs(xNormal), MathF.Abs(zNormal));

                // Incline threshold check
                if (deltaSlope < deltaStop)
                {
                    break;
                }

                // Downhill coordinate integration (Ref: §10.C)
                float nextX = currentPos.X + xNormal * heightScale * stepSize;
                float nextZ = currentPos.Z + zNormal * heightScale * stepSize;

                // Snap elevation to the local terrain height
                Vector3 nextPos = new Vector3(nextX, 0f, nextZ);
                float rawHeight = CoordinateMapping.SampleBilinearWorld(heightHM, nextPos, ctx);
                float nextY = rawHeight * heightScale;
                
                currentPos = new Vector3(nextX, nextY, nextZ);
            }

            // Add final slid instance
            instanceSetOut.Add(new InstanceTransform(
                currentPos,
                inst.Rotation,
                inst.Scale,
                inst.MeshAssetId,
                inst.Hash,
                inst.Id
            ));
        }

        return instanceSetOut;
    }
}

#endregion
