namespace SimpleXTerrain;

using Godot;
using System;

/// <summary>
/// Utility class to compile height matrices into optimized standard 3D static meshes.
/// </summary>
public static class MeshCompiler
{
    /// <summary>
    /// Compiles a HeightMatrix into a Godot ArrayMesh.
    /// </summary>
    /// <param name="heightMatrix">The input height matrix.</param>
    /// <param name="heightScale">Scale factor applied to heights.</param>
    /// <param name="worldSize">Physical size of the mesh boundary in world meters.</param>
    /// <param name="lod">Level of detail step factor (1 = full detail, 2 = half resolution, etc.)</param>
    /// <returns>A committed ArrayMesh representation of the height matrix.</returns>
    public static ArrayMesh CompileMesh(HeightMatrix heightMatrix, float heightScale, float worldSize, int lod = 1)
    {
        if (heightMatrix == null)
        {
            throw new ArgumentNullException(nameof(heightMatrix));
        }

        if (lod < 1)
        {
            lod = 1;
        }

        int width = heightMatrix.Width;
        int height = heightMatrix.Height;

        SurfaceTool st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);

        float cellX = worldSize / (width - 1);
        float cellZ = worldSize / (height - 1);

        // Generate vertices
        for (int z = 0; z < height; z += lod)
        {
            for (int x = 0; x < width; x += lod)
            {
                float h = heightMatrix[x, z] * heightScale;
                Vector3 pos = new Vector3(x * cellX, h, z * cellZ);
                Vector2 uv = new Vector2((float)x / (width - 1), (float)z / (height - 1));

                st.SetUV(uv);
                st.AddVertex(pos);
            }
        }

        // Calculate actual grid dimensions based on LOD step
        int cols = 0;
        for (int x = 0; x < width; x += lod) cols++;
        
        int rows = 0;
        for (int z = 0; z < height; z += lod) rows++;

        // Generate indices
        for (int r = 0; r < rows - 1; r++)
        {
            for (int c = 0; c < cols - 1; c++)
            {
                int i0 = r * cols + c;
                int i1 = r * cols + (c + 1);
                int i2 = (r + 1) * cols + c;
                int i3 = (r + 1) * cols + (c + 1);

                // Triangle 1 (Clockwise winding)
                st.AddIndex(i0);
                st.AddIndex(i2);
                st.AddIndex(i1);

                // Triangle 2 (Clockwise winding)
                st.AddIndex(i1);
                st.AddIndex(i2);
                st.AddIndex(i3);
            }
        }

        st.GenerateNormals();
        return st.Commit();
    }
}
