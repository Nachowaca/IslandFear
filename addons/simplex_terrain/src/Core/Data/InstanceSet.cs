namespace SimpleXTerrain;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// Represents a single procedurally placed object instance transform and its associated mesh asset ID.
/// </summary>
public struct InstanceTransform
{
    /// <summary>
    /// Gets the 3D position of the instance.
    /// </summary>
    public Vector3 Position { get; }

    /// <summary>
    /// Gets the 3D orientation rotation quaternion of the instance.
    /// </summary>
    public Quaternion Rotation { get; }

    /// <summary>
    /// Gets the 3D scale of the instance.
    /// </summary>
    public Vector3 Scale { get; }

    /// <summary>
    /// Gets the mesh asset identifier associated with this instance.
    /// </summary>
    public int MeshAssetId { get; }

    /// <summary>
    /// Gets the deterministic hash of the entity position.
    /// </summary>
    public uint Hash { get; }

    /// <summary>
    /// Gets the unique persistent identifier of the entity.
    /// </summary>
    public int Id { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="InstanceTransform"/> struct.
    /// </summary>
    /// <param name="position">The 3D position of the instance.</param>
    /// <param name="rotation">The orientation rotation quaternion of the instance.</param>
    /// <param name="scale">The 3D scale of the instance.</param>
    /// <param name="meshAssetId">The mesh asset ID to scatter.</param>
    /// <param name="hash">The deterministic hash of the entity.</param>
    /// <param name="id">The unique persistent identifier.</param>
    public InstanceTransform(Vector3 position, Quaternion rotation, Vector3 scale, int meshAssetId, uint hash = 0, int id = 0)
    {
        Position = position;
        Rotation = rotation;
        Scale = scale;
        MeshAssetId = meshAssetId;
        Hash = hash;
        Id = id;
    }
}

/// <summary>
/// A collection of scattered object instance transforms, suitable for streaming into foliage or instancer engines.
/// </summary>
public class InstanceSet
{
    private readonly List<InstanceTransform> _instances = new List<InstanceTransform>();

    /// <summary>
    /// Gets the read-only list of instance transforms.
    /// </summary>
    public IReadOnlyList<InstanceTransform> Instances => _instances;

    /// <summary>
    /// Adds an instance transform to the set.
    /// </summary>
    /// <param name="t">The instance transform to add.</param>
    public void Add(InstanceTransform t)
    {
        _instances.Add(t);
    }

    /// <summary>
    /// Gets the total number of instances in this set.
    /// </summary>
    public int Count => _instances.Count;
}
