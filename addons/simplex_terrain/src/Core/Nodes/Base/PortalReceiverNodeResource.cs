using Godot;
using System;

namespace SimpleXTerrain;


/// <summary>
/// Serializable resource holding configuration parameters for a PortalReceiverNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class PortalReceiverNodeResource : TerrainNodeResource
{
    /// <summary>
    /// Gets or sets the wireless channel name token to bind to.
    /// </summary>
    [Export]
    public string PortalName { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the data type expected from the transmitter.
    /// </summary>
    [Export]
    public PortType PortType { get; set; } = PortType.Height;

    /// <summary>
    /// Initializes a new instance of the <see cref="PortalReceiverNodeResource"/> class.
    /// </summary>
    public PortalReceiverNodeResource()
    {
        NodeType = nameof(PortalReceiverNode);
    }
}
