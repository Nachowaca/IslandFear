using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that disperses a set of child object instances radially around each parent instance position.
/// </summary>
public partial class RadialDispersalNode : TerrainNode
{
    public RadialDispersalNodeResource AssociatedResource { get; set; }

    public RadialDispersalNode()
    {
        Inputs.Add(new Port("Instance In", PortType.Instance, PortDirection.Input));
        Outputs.Add(new Port("Instance Out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            return new InstanceSet();
        }

        var instanceSetIn = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        if (instanceSetIn == null)
        {
            return new InstanceSet();
        }

        int childrenPerParent = AssociatedResource != null ? Math.Max(0, AssociatedResource.ChildrenPerParent) : 5;
        float minRadius = AssociatedResource != null ? AssociatedResource.MinRadius : 2.0f;
        float maxRadius = AssociatedResource != null ? AssociatedResource.MaxRadius : 15.0f;
        int seedVal = AssociatedResource != null ? AssociatedResource.Seed : 3;

        InstanceSet instanceSetOut = new InstanceSet();

        // 1. Keep original parents
        foreach (var parent in instanceSetIn.Instances)
        {
            instanceSetOut.Add(parent);
        }

        // Global sequence counter to ensure unique child IDs
        int nextChildId = instanceSetIn.Count + 1;

        // 2. Spawn children for each parent
        foreach (var parent in instanceSetIn.Instances)
        {
            uint parentHash = parent.Hash;

            for (int n = 0; n < childrenPerParent; n++)
            {
                // Generate a unique, deterministic hash for each child (Ref: 11_OBJECTS_AND_ECOSYSTEM_MODIFIERS.md §5.B)
                uint childHash = (parentHash << 1) + (uint)n + (uint)seedVal;

                // Deterministic angle using SplitMix32-style integer hashing
                uint hAngle = childHash ^ 0x9e3779b9;
                hAngle = (hAngle ^ (hAngle >> 16)) * 0x7feb352d;
                hAngle = (hAngle ^ (hAngle >> 15)) * 0x846ca68b;
                float angle = (float)(hAngle & 0x7FFFFFFF) / 0x7FFFFFFF * MathF.PI * 2.0f;

                // Deterministic distance
                uint hDist = childHash ^ 0x12345678;
                hDist = (hDist ^ (hDist >> 16)) * 0x7feb352d;
                hDist = (hDist ^ (hDist >> 15)) * 0x846ca68b;
                float normDist = (float)(hDist & 0x7FFFFFFF) / 0x7FFFFFFF;
                float dist = minRadius + normDist * (maxRadius - minRadius);

                // Offset child position horizontally relative to parent
                Vector3 childPos = parent.Position + new Vector3(dist * MathF.Sin(angle), 0f, dist * MathF.Cos(angle));

                // Create child transform, preserving scale and rotation of parent (Ref: §5.B)
                InstanceTransform child = new InstanceTransform(
                    childPos,
                    parent.Rotation,
                    parent.Scale,
                    parent.MeshAssetId,
                    childHash,
                    nextChildId++
                );

                instanceSetOut.Add(child);
            }
        }

        return instanceSetOut;
    }
}

#endregion
