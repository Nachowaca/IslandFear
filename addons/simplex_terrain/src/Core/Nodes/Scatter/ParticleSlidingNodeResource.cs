using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a ParticleSlidingNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ParticleSlidingNodeResource : TerrainNodeResource
{
    [Export]
    public int MaxSteps { get; set; } = 100;

    [Export]
    public float StopSlopeDeg { get; set; } = 15.0f;

    [Export]
    public float StepSize { get; set; } = 0.5f;

    [Export]
    public float HeightScale { get; set; } = 500.0f;

    public ParticleSlidingNodeResource()
    {
        NodeType = nameof(ParticleSlidingNode);
    }
}
