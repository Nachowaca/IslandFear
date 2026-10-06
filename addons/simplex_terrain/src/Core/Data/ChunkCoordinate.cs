namespace SimpleXTerrain;

using System;
using Godot;

/// <summary>
/// A lightweight, immutable value-type wrapper representing a 2D grid coordinate for a terrain chunk.
/// Implements high-performance equality operations and a Cantor-pairing-based hash function.
/// </summary>
public readonly struct ChunkCoordinate : IEquatable<ChunkCoordinate>
{
    /// <summary>
    /// The X coordinate of the chunk in the grid.
    /// </summary>
    public readonly int X;

    /// <summary>
    /// The Z coordinate of the chunk in the grid.
    /// </summary>
    public readonly int Z;

    /// <summary>
    /// Initializes a new instance of the <see cref="ChunkCoordinate"/> struct.
    /// </summary>
    /// <param name="x">The X coordinate.</param>
    /// <param name="z">The Z coordinate.</param>
    public ChunkCoordinate(int x, int z)
    {
        X = x;
        Z = z;
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="ChunkCoordinate"/> struct from a Godot Vector2I.
    /// </summary>
    /// <param name="vector">The Godot Vector2I coordinate.</param>
    public ChunkCoordinate(Vector2I vector)
    {
        X = vector.X;
        Z = vector.Y;
    }

    /// <summary>
    /// Converts this ChunkCoordinate into a Godot Vector2I.
    /// </summary>
    public Vector2I ToVector2I()
    {
        return new Vector2I(X, Z);
    }

    /// <summary>
    /// Checks for equality between this coordinate and another.
    /// </summary>
    public bool Equals(ChunkCoordinate other)
    {
        return X == other.X && Z == other.Z;
    }

    /// <summary>
    /// Determines whether the specified object is equal to the current object.
    /// </summary>
    public override bool Equals(object obj)
    {
        return obj is ChunkCoordinate other && Equals(other);
    }

    /// <summary>
    /// Serves as the default hash function using a signed Cantor-pairing-style algorithm.
    /// </summary>
    public override int GetHashCode()
    {
        // Cantor pairing function is defined for non-negative integers.
        // Map X and Z to non-negative integers:
        // nonNegative = 2 * n if n >= 0, and -2 * n - 1 if n < 0
        long ux = X >= 0 ? 2L * X : -2L * X - 1L;
        long uz = Z >= 0 ? 2L * Z : -2L * Z - 1L;

        // Cantor pairing: ((ux + uz) * (ux + uz + 1)) / 2 + uz
        long sum = ux + uz;
        long pair = ((sum * (sum + 1L)) >> 1) + uz;

        // Fold the 64-bit pair to a 32-bit int hash
        return (int)(pair ^ (pair >> 32));
    }

    /// <summary>
    /// Compares two ChunkCoordinate instances for equality.
    /// </summary>
    public static bool operator ==(ChunkCoordinate left, ChunkCoordinate right)
    {
        return left.Equals(right);
    }

    /// <summary>
    /// Compares two ChunkCoordinate instances for inequality.
    /// </summary>
    public static bool operator !=(ChunkCoordinate left, ChunkCoordinate right)
    {
        return !left.Equals(right);
    }

    /// <summary>
    /// Returns a string representation of the ChunkCoordinate.
    /// </summary>
    public override string ToString()
    {
        return $"({X}, {Z})";
    }
}
