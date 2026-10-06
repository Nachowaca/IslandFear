using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a PortalTransmitterNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class PortalTransmitterNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the wireless channel name token for this portal.
    /// </summary>
    [Export]
    public string PortalName { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the data type carried by this portal.
    /// </summary>
    [Export]
    public PortType PortType { get; set; } = PortType.Height;

    /// <summary>
    /// Initializes a new instance of the <see cref="PortalTransmitterNodeResource"/> class.
    /// </summary>
    public PortalTransmitterNodeResource()
    {
        NodeType = nameof(PortalTransmitterNode);
    }
}
