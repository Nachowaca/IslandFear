namespace SimpleXTerrain;

/// <summary>
/// Defines the types of data that can be carried by a port in the terrain generation graph.
/// </summary>
public enum PortType
{
    /// <summary>
    /// Represents heightmap data, typically carrying a <see cref="HeightMatrix"/>.
    /// </summary>
    Height,

    /// <summary>
    /// Represents mask data, typically carrying a single channel <see cref="HeightMatrix"/> used as a weight mask.
    /// </summary>
    Mask,

    /// <summary>
    /// Represents texture splat weights, typically carrying a <see cref="SplatWeightSet"/>.
    /// </summary>
    Splat,

    /// <summary>
    /// Represents spline curves, typically carrying a <see cref="SplineSet"/>.
    /// </summary>
    Spline,

    /// <summary>
    /// Represents placed object transforms, typically carrying an <see cref="InstanceSet"/>.
    /// </summary>
    Instance,

    /// <summary>
    /// Represents scalar numbers, typically carrying a float or int value.
    /// </summary>
    Scalar
}

/// <summary>
/// Specifies the direction of data flow through a port.
/// </summary>
public enum PortDirection
{
    /// <summary>
    /// An input port that receives data from upstream nodes.
    /// </summary>
    Input,

    /// <summary>
    /// An output port that pushes calculated data downstream.
    /// </summary>
    Output
}

/// <summary>
/// Represents a typed data connection slot on a graph node.
/// </summary>
public class Port
{
    /// <summary>
    /// Gets the unique (per-node, per-direction) name of the port.
    /// </summary>
    public string Name { get; }

    /// <summary>
    /// Gets the data type accepted or produced by this port.
    /// </summary>
    public PortType Type { get; }

    /// <summary>
    /// Gets the flow direction of this port.
    /// </summary>
    public PortDirection Direction { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="Port"/> class.
    /// </summary>
    /// <param name="name">The name of the port.</param>
    /// <param name="type">The type of the port.</param>
    /// <param name="direction">The direction of the port.</param>
    public Port(string name, PortType type, PortDirection direction)
    {
        Name = name;
        Type = type;
        Direction = direction;
    }
}
