using Godot;
using System;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that stochastically prunes scattered instances based on a weight/survival mask and seed-based LCG hash values.
/// </summary>
public partial class PruneNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public PruneNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="PruneNode"/> class.
    /// </summary>
    public PruneNode()
    {
        Inputs.Add(new Port("instance_in", PortType.Instance, PortDirection.Input));
        Inputs.Add(new Port("survival_mask", PortType.Mask, PortDirection.Input));
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    /// <summary>
    /// Prunes incoming instances based on the connected mask value and LCG-based lottery.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        int seed = AssociatedResource != null ? AssociatedResource.Seed : 2;

        InstanceSet inputInstances = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            inputInstances = link.SourceNode.PullData(ctx, link.SourcePortIndex) as InstanceSet;
        }

        HeightMatrix survivalMask = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            survivalMask = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        var outputSet = new InstanceSet();
        if (inputInstances == null)
        {
            return outputSet;
        }

        foreach (var inst in inputInstances.Instances)
        {
            float vMask = 1.0f;
            if (survivalMask != null)
            {
                vMask = CoordinateMapping.SampleBilinearWorld(survivalMask, inst.Position, ctx);
            }

            // Mix seed with entity's Hash and apply LCG step to generate a high-quality deterministic pseudo-random float
            uint mixed = (uint)seed ^ inst.Hash;
            mixed = mixed * 1664525u + 1013904223u;
            float r = (float)(mixed & 0xFFFFFF) / 16777216f; // maps to [0, 1)

            if (vMask >= r)
            {
                outputSet.Add(inst);
            }
        }

        return outputSet;
    }
}

#endregion
