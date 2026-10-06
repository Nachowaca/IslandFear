using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a LakeExcavatorNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class LakeExcavatorNodeResource : TerrainNodeResource
{
    [Export]
    public float ExcavationDepth { get; set; } = 0.05f;

    [Export]
    public float DepthScale { get; set; } = 0.02f;

    public LakeExcavatorNodeResource()
    {
        NodeType = nameof(LakeExcavatorNode);
    }
}
