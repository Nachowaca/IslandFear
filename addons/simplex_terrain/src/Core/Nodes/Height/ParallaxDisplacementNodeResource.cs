using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a ParallaxDisplacementNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class ParallaxDisplacementNodeResource : TerrainNodeResource
{
    [Export]
    public float DirectionX { get; set; } = 1.0f;

    [Export]
    public float DirectionZ { get; set; } = 0.0f;

    [Export]
    public float MaxOffset { get; set; } = 16.0f;

    [Export]
    public ParallaxInterpolationMode Interpolation { get; set; } = ParallaxInterpolationMode.Bilinear;

    public ParallaxDisplacementNodeResource()
    {
        NodeType = nameof(ParallaxDisplacementNode);
    }
}
