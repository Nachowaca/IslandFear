namespace SimpleXTerrain;

using Godot;
using System;
using System.IO;
using System.IO.Compression;
using System.Text;

#region Resources

public enum ExportFormat
{
    EXR_32bit,
    EXR_16bit,
    PNG_16bit,
    RAW_R16
}


#endregion

#region Nodes

/// <summary>
/// A terminal or inline node that exports a heightfield to EXR, 16-bit PNG, or raw files.
/// </summary>
public partial class HeightmapExportNode : TerrainNode
{
    private static readonly uint[] CrcTable = new uint[256];

    static HeightmapExportNode()
    {
        for (uint i = 0; i < 256; i++)
        {
            uint c = i;
            for (int k = 0; k < 8; k++)
            {
                if ((c & 1) != 0)
                {
                    c = 0xedb88320U ^ (c >> 1);
                }
                else
                {
                    c = c >> 1;
                }
            }
            CrcTable[i] = c;
        }
    }

    public HeightmapExportNodeResource AssociatedResource { get; set; }

    public HeightmapExportNode()
    {
        Inputs.Add(new Port("height_in", PortType.Height, PortDirection.Input));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var link = InputLinks[0];
        if (link.SourceNode == null)
        {
            GD.PrintErr("[HeightmapExportNode] Error: No input connected to port 0.");
            return null;
        }

        var hm = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        if (hm == null)
        {
            GD.PrintErr("[HeightmapExportNode] Error: Pulled data is not a HeightMatrix.");
            return null;
        }

        Export(hm, ctx);
        return hm; // Pass-through
    }

    public void Export(HeightMatrix hm, GenerationContext ctx)
    {
        string rawPath = AssociatedResource != null ? AssociatedResource.ExportPath : "res://heightmap.exr";
        ExportFormat format = AssociatedResource != null ? AssociatedResource.Format : ExportFormat.EXR_32bit;

        string formattedPath = rawPath.Replace("{x}", ctx.Coord.X.ToString()).Replace("{z}", ctx.Coord.Z.ToString());
        string systemPath = ProjectSettings.GlobalizePath(formattedPath);

        string dir = Path.GetDirectoryName(systemPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        int W = ctx.Resolution;
        int padding = ctx.Padding;

        switch (format)
        {
            case ExportFormat.EXR_32bit:
                {
                    Image img = Image.CreateEmpty(W, W, false, Image.Format.Rf);
                    for (int z = 0; z < W; z++)
                    {
                        for (int x = 0; x < W; x++)
                        {
                            float heightVal = Math.Clamp(hm[x + padding, z + padding], 0.0f, 1.0f);
                            img.SetPixel(x, z, new Color(heightVal, 0, 0));
                        }
                    }
                    img.SaveExr(systemPath, true);
                    break;
                }
            case ExportFormat.EXR_16bit:
                {
                    Image img = Image.CreateEmpty(W, W, false, Image.Format.Rh);
                    for (int z = 0; z < W; z++)
                    {
                        for (int x = 0; x < W; x++)
                        {
                            float heightVal = Math.Clamp(hm[x + padding, z + padding], 0.0f, 1.0f);
                            img.SetPixel(x, z, new Color(heightVal, 0, 0));
                        }
                    }
                    img.SaveExr(systemPath, true);
                    break;
                }
            case ExportFormat.PNG_16bit:
                {
                    ushort[] pixels = new ushort[W * W];
                    for (int z = 0; z < W; z++)
                    {
                        for (int x = 0; x < W; x++)
                        {
                            float heightVal = Math.Clamp(hm[x + padding, z + padding], 0.0f, 1.0f);
                            pixels[z * W + x] = (ushort)Math.Clamp(Math.Round(heightVal * 65535.0f), 0.0, 65535.0);
                        }
                    }
                    WritePng16Bit(systemPath, pixels, W, W);
                    break;
                }
            case ExportFormat.RAW_R16:
                {
                    ushort[] pixels = new ushort[W * W];
                    for (int z = 0; z < W; z++)
                    {
                        for (int x = 0; x < W; x++)
                        {
                            float heightVal = Math.Clamp(hm[x + padding, z + padding], 0.0f, 1.0f);
                            pixels[z * W + x] = (ushort)Math.Clamp(Math.Round(heightVal * 65535.0f), 0.0, 65535.0);
                        }
                    }
                    WriteRawR16(systemPath, pixels);
                    break;
                }
        }
        // GD.Print($"[HeightmapExportNode] Successfully exported heightmap chunk {ctx.Coord} to: {systemPath} ({format})");
    }

    private static byte[] CompressZlib(byte[] data)
    {
        using (var ms = new MemoryStream())
        {
            using (var zs = new ZLibStream(ms, CompressionLevel.Optimal, true))
            {
                zs.Write(data, 0, data.Length);
            }
            return ms.ToArray();
        }
    }

    private static void WritePng16Bit(string path, ushort[] pixels, int width, int height)
    {
        int scanlineLength = 1 + 2 * width;
        byte[] uncompressed = new byte[scanlineLength * height];
        for (int y = 0; y < height; y++)
        {
            int offset = y * scanlineLength;
            uncompressed[offset] = 0; // Filter type 0 (None)
            for (int x = 0; x < width; x++)
            {
                ushort val = pixels[y * width + x];
                uncompressed[offset + 1 + 2 * x] = (byte)(val >> 8);
                uncompressed[offset + 2 + 2 * x] = (byte)(val & 0xFF);
            }
        }

        byte[] compressed = CompressZlib(uncompressed);

        using (var fs = File.Create(path))
        {
            fs.Write(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, 0, 8);

            // IHDR chunk
            byte[] ihdrData = new byte[13];
            byte[] wBytes = BitConverter.GetBytes((uint)width);
            byte[] hBytes = BitConverter.GetBytes((uint)height);
            if (BitConverter.IsLittleEndian)
            {
                Array.Reverse(wBytes);
                Array.Reverse(hBytes);
            }
            Array.Copy(wBytes, 0, ihdrData, 0, 4);
            Array.Copy(hBytes, 0, ihdrData, 4, 4);
            ihdrData[8] = 16; // 16-bit depth
            ihdrData[9] = 0;  // Grayscale color type
            ihdrData[10] = 0; // Compression method
            ihdrData[11] = 0; // Filter method
            ihdrData[12] = 0; // Interlace method
            WriteChunk(fs, "IHDR", ihdrData);

            // IDAT chunk
            WriteChunk(fs, "IDAT", compressed);

            // IEND chunk
            WriteChunk(fs, "IEND", null);
        }
    }

    private static void WriteRawR16(string path, ushort[] pixels)
    {
        using (var fs = File.Create(path))
        using (var bw = new BinaryWriter(fs))
        {
            for (int i = 0; i < pixels.Length; i++)
            {
                bw.Write(pixels[i]);
            }
        }
    }

    private static uint CalculateCrc(byte[] bytes, int offset, int length)
    {
        uint c = 0xffffffffU;
        for (int i = 0; i < length; i++)
        {
            c = CrcTable[(c ^ bytes[offset + i]) & 0xff] ^ (c >> 8);
        }
        return c ^ 0xffffffffU;
    }

    private static void WriteChunk(Stream stream, string type, byte[] data)
    {
        uint len = (uint)(data?.Length ?? 0);
        byte[] lenBytes = BitConverter.GetBytes(len);
        if (BitConverter.IsLittleEndian) Array.Reverse(lenBytes);
        stream.Write(lenBytes, 0, 4);

        byte[] typeBytes = Encoding.ASCII.GetBytes(type);
        stream.Write(typeBytes, 0, 4);

        if (data != null && data.Length > 0)
        {
            stream.Write(data, 0, data.Length);
        }

        byte[] crcBuf = new byte[4 + (data?.Length ?? 0)];
        Array.Copy(typeBytes, 0, crcBuf, 0, 4);
        if (data != null && data.Length > 0)
        {
            Array.Copy(data, 0, crcBuf, 4, data.Length);
        }
        uint crc = CalculateCrc(crcBuf, 0, crcBuf.Length);
        byte[] crcBytes = BitConverter.GetBytes(crc);
        if (BitConverter.IsLittleEndian) Array.Reverse(crcBytes);
        stream.Write(crcBytes, 0, 4);
    }
}

#endregion
