using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a SplineClipNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class SplineClipNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Initializes a new instance of the <see cref="SplineClipNodeResource"/> class.
    /// </summary>
    public SplineClipNodeResource()
    {
        NodeType = nameof(SplineClipNode);
    }
}
