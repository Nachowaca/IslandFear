using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a ForestSimulationNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ForestSimulationNodeResource : TerrainNodeResource
{
    [Export]
    public int Years { get; set; } = 20;

    [Export]
    public float SeedRate { get; set; } = 0.05f;

    [Export]
    public float SurvivalThreshold { get; set; } = 0.3f;

    [Export]
    public int CrowdingRadius { get; set; } = 2;

    [Export]
    public float Density { get; set; } = 1000.0f; // Trees per km^2

    [Export]
    public int Seed { get; set; } = 42;

    [Export]
    public float MaxLifespan { get; set; } = 30.0f;

    [Export]
    public int CrowdingThreshold { get; set; } = 8;

    public ForestSimulationNodeResource()
    {
        NodeType = nameof(ForestSimulationNode);
    }
}
