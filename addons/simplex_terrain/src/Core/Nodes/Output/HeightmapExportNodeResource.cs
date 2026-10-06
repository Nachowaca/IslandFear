using Godot;
using System;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace SimpleXTerrain;


/// <summary>
/// Configuration resource for the HeightmapExportNode.
/// </summary>
[GlobalClass]
[Tool]
public partial class HeightmapExportNodeResource : TerrainNodeResource
{
    [Export]
    public string ExportPath { get; set; } = "res://heightmap.exr";

    [Export]
    public ExportFormat Format { get; set; } = ExportFormat.EXR_32bit;

    public HeightmapExportNodeResource()
    {
        NodeType = nameof(HeightmapExportNode);
    }
}
