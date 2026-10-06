namespace SimpleXTerrain;

/// <summary>
/// Defines a modular, continuous two-dimensional pseudo-random noise generator.
/// Enables stacking, composition, and wrapping of different noise nodes.
/// </summary>
public interface INoiseSource
{
    /// <summary>
    /// Deterministically samples the raw continuous noise value in [0, 1] range at the given world coordinates.
    /// </summary>
    /// <param name="x">The world-space X coordinate.</param>
    /// <param name="z">The world-space Z coordinate.</param>
    /// <returns>A normalized noise value in the range [0.0, 1.0].</returns>
    float Sample(float x, float z, int subSeed = 0);

    /// <summary>
    /// Gets the underlying permutation table of this noise source.
    /// </summary>
    PermutationTable Table { get; }
}
