using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that snaps objects vertically to terrain height and optionally aligns their rotations to the surface normal.
/// </summary>
public partial class TerrainSnapNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public TerrainSnapNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="TerrainSnapNode"/> class.
    /// </summary>
    public TerrainSnapNode()
    {
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Snaps instances vertically to the height field and computes normal alignments.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float normalAlign = AssociatedResource != null ? AssociatedResource.NormalAlign : 1.0f;
        float heightOffset = AssociatedResource != null ? AssociatedResource.HeightOffset : 0.0f;
        float heightScale = AssociatedResource != null ? AssociatedResource.HeightScale : 500.0f;

        InstanceSet inputInstances = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputInstances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        HeightMatrix heightHM = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            heightHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        var outputSet = new InstanceSet();
        if (inputInstances == null)
        {
            return outputSet;
        }

        if (heightHM == null)
        {
            // If height field is not connected, just copy instances over without deforming Y
            foreach (var t in inputInstances.Instances)
            {
                outputSet.Add(t);
            }
            return outputSet;
        }

        float cellSize = ctx.WorldSize / ctx.Resolution;

        foreach (var inst in inputInstances.Instances)
        {
            Vector3 pos = inst.Position;

            // 1. Bilinear snap height
            float rawHeight = CoordinateMapping.SampleBilinearWorld(heightHM, pos, ctx);
            float snappedY = rawHeight * heightScale + heightOffset;
            Vector3 snappedPos = new Vector3(pos.X, snappedY, pos.Z);

            // 2. Normal computation via bilinear offset sampling
            float hLeft = CoordinateMapping.SampleBilinearWorld(heightHM, new Vector3(pos.X - cellSize, pos.Y, pos.Z), ctx);
            float hRight = CoordinateMapping.SampleBilinearWorld(heightHM, new Vector3(pos.X + cellSize, pos.Y, pos.Z), ctx);
            float hUp = CoordinateMapping.SampleBilinearWorld(heightHM, new Vector3(pos.X, pos.Y, pos.Z - cellSize), ctx);
            float hDown = CoordinateMapping.SampleBilinearWorld(heightHM, new Vector3(pos.X, pos.Y, pos.Z + cellSize), ctx);

            float dx = (hLeft - hRight) * heightScale / (2f * cellSize);
            float dy = 1.0f;
            float dz = (hUp - hDown) * heightScale / (2f * cellSize);
            Vector3 normal = new Vector3(dx, dy, dz).Normalized();

            // 3. Compute alignment quaternion
            Quaternion qAlign = GetRotationTo(Vector3.Up, normal);
            Quaternion finalRot = Quaternion.Identity.Slerp(qAlign, normalAlign) * inst.Rotation;

            outputSet.Add(new InstanceTransform(snappedPos, finalRot, inst.Scale, inst.MeshAssetId, inst.Hash, inst.Id));
        }

        return outputSet;
    }

    private static Quaternion GetRotationTo(Vector3 from, Vector3 to)
    {
        float dot = from.Dot(to);
        if (dot < -0.9999f)
        {
            Vector3 ortho = MathF.Abs(from.X) < 0.8f ? new Vector3(1, 0, 0) : new Vector3(0, 0, 1);
            return new Quaternion(ortho.Normalized(), MathF.PI);
        }
        if (dot > 0.9999f)
        {
            return Quaternion.Identity;
        }
        Vector3 cross = from.Cross(to);
        float w = MathF.Sqrt(from.LengthSquared() * to.LengthSquared()) + dot;
        return new Quaternion(cross.X, cross.Y, cross.Z, w).Normalized();
    }
}

#endregion
