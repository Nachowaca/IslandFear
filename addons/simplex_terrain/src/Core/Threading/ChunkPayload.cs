namespace SimpleXTerrain;

using Godot;

/// <summary>
/// Container holding the fully evaluated procedural generation results for a single chunk.
/// Safe to transfer between background threads and the main thread.
/// </summary>
public struct ChunkPayload
{
    /// <summary>
    /// Gets the coordinate of the generated chunk.
    /// </summary>
    public ChunkCoordinate Coord { get; set; }

    /// <summary>
    /// Gets the evaluated height matrix.
    /// </summary>
    public HeightMatrix Heights { get; set; }

    /// <summary>
    /// Gets the pre-packed texture control map image.
    /// </summary>
    public Image ControlMap { get; set; }

    /// <summary>
    /// Gets the foliage/object instance collection (optional/nullable).
    /// </summary>
    public InstanceSet Instances { get; set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="ChunkPayload"/> struct.
    /// </summary>
    public ChunkPayload(ChunkCoordinate coord, HeightMatrix heights, Image controlMap = null, InstanceSet instances = null)
    {
        Coord = coord;
        Heights = heights;
        ControlMap = controlMap;
        Instances = instances;
    }
}
