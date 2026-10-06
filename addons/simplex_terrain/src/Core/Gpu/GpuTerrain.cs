namespace SimpleXTerrain;

using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>
/// Bridge class that coordinates Godot 4 RenderingDevice local compute dispatches
/// and transfers buffer data between CPU Memory and GPU VRAM with minimum overhead.
/// </summary>
public static class GpuTerrain
{
    private static RenderingDevice _rd;
    private static readonly Dictionary<string, Rid> _shaders = new();
    private static int _mainThreadId;
    private static readonly object _lock = new();

    public static void InitializeMainThread()
    {
        if (_mainThreadId == 0)
        {
            _mainThreadId = System.Environment.CurrentManagedThreadId;
            GD.Print($"[GpuTerrain] Main thread registered: {_mainThreadId}");
        }
    }

    /// <summary>
    /// Gets the shared local RenderingDevice instance.
    /// Returns null if compute shaders are not supported on the hardware.
    /// </summary>
    public static RenderingDevice Device
    {
        get
        {
            lock (_lock)
            {
                if (_rd == null)
                {
                    try
                    {
                        _rd = RenderingServer.CreateLocalRenderingDevice();
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[GpuTerrain] Failed to create local rendering device: {ex.Message}");
                    }
                }
                return _rd;
            }
        }
    }

    /// <summary>
    /// Checks if GPU acceleration is supported on the current hardware.
    /// </summary>
    public static bool IsSupported => Device != null;

    /// <summary>
    /// Loads, compiles, and caches a GLSL compute shader from a resource path.
    /// </summary>
    public static Rid LoadShader(string path)
    {
        lock (_lock)
        {
            var rd = Device;
            if (rd == null)
            {
                return new Rid();
            }

            if (!_shaders.TryGetValue(path, out Rid shader))
            {
                try
                {
                    var file = GD.Load<RDShaderFile>(path);
                    if (file == null)
                    {
                        GD.PrintErr($"[GpuTerrain] Failed to load shader file: {path}");
                        return new Rid();
                    }
                    shader = rd.ShaderCreateFromSpirV(file.GetSpirV());
                    _shaders[path] = shader;
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[GpuTerrain] Error creating shader from {path}: {ex.Message}");
                    return new Rid();
                }
            }
            return shader;
        }
    }

    /// <summary>
    /// Dispatches a single compute generator shader synchronously and copies the result directly
    /// into the HeightMatrix memory without temp arrays.
    /// </summary>
    public static void DispatchAndReadback(Rid shader, HeightMatrix output, byte[] paramsBytes, uint groupsX, uint groupsY)
    {
        lock (_lock)
        {
            var rd = Device;
            if (rd == null || !shader.IsValid) return;

            int totalBytes = output.Width * output.Height * 4;

            // Create GPU buffers
            Rid outBuf = rd.StorageBufferCreate((uint)totalBytes);
            Rid paramBuf = rd.StorageBufferCreate((uint)paramsBytes.Length, paramsBytes);

            // Define uniform bindings: Out is bound to binding 0, Params to binding 1
            var u0 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0 };
            u0.AddId(outBuf);
            var u1 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1 };
            u1.AddId(paramBuf);

            var uniforms = new Godot.Collections.Array<RDUniform> { u0, u1 };
            Rid uniformSet = rd.UniformSetCreate(uniforms, shader, 0);

            // Record & dispatch commands
            Rid pipeline = rd.ComputePipelineCreate(shader);
            long cl = rd.ComputeListBegin();
            rd.ComputeListBindComputePipeline(cl, pipeline);
            rd.ComputeListBindUniformSet(cl, uniformSet, 0);
            rd.ComputeListDispatch(cl, groupsX, groupsY, 1);
            rd.ComputeListEnd();

            rd.Submit();
            rd.Sync(); // Block until GPU finishes

            // Readback directly into HeightMatrix memory view
            byte[] result = rd.BufferGetData(outBuf);
            var span = output.AsSpan();
            result.AsSpan().CopyTo(MemoryMarshal.AsBytes(span));

            // Free resources
            rd.FreeRid(outBuf);
            rd.FreeRid(paramBuf);
            rd.FreeRid(uniformSet);
            rd.FreeRid(pipeline);
        }
    }

    /// <summary>
    /// Dispatches a single compute modifier shader synchronously, reading from an input HeightMatrix
    /// and writing results directly into the output HeightMatrix.
    /// </summary>
    public static void DispatchModifier(Rid shader, HeightMatrix input, HeightMatrix output, byte[] paramsBytes, uint groupsX, uint groupsY)
    {
        lock (_lock)
        {
            var rd = Device;
            if (rd == null || !shader.IsValid) return;

            int totalBytes = output.Width * output.Height * 4;

            // Copy input to a temp byte array for upload
            byte[] inputBytes = new byte[totalBytes];
            MemoryMarshal.AsBytes(input.AsReadOnlySpan()).CopyTo(inputBytes);

            // Create GPU buffers
            Rid inBuf = rd.StorageBufferCreate((uint)totalBytes, inputBytes);
            Rid outBuf = rd.StorageBufferCreate((uint)totalBytes);
            Rid paramBuf = rd.StorageBufferCreate((uint)paramsBytes.Length, paramsBytes);

            var u0 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0 };
            u0.AddId(inBuf);
            var u1 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1 };
            u1.AddId(outBuf);
            var u2 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2 };
            u2.AddId(paramBuf);

            var uniforms = new Godot.Collections.Array<RDUniform> { u0, u1, u2 };
            Rid uniformSet = rd.UniformSetCreate(uniforms, shader, 0);

            Rid pipeline = rd.ComputePipelineCreate(shader);
            long cl = rd.ComputeListBegin();
            rd.ComputeListBindComputePipeline(cl, pipeline);
            rd.ComputeListBindUniformSet(cl, uniformSet, 0);
            rd.ComputeListDispatch(cl, groupsX, groupsY, 1);
            rd.ComputeListEnd();

            rd.Submit();
            rd.Sync();

            byte[] result = rd.BufferGetData(outBuf);
            result.AsSpan().CopyTo(MemoryMarshal.AsBytes(output.AsSpan()));

            rd.FreeRid(inBuf);
            rd.FreeRid(outBuf);
            rd.FreeRid(paramBuf);
            rd.FreeRid(uniformSet);
            rd.FreeRid(pipeline);
        }
    }

    /// <summary>
    /// Runs an entire sub-chain of GPU-capable nodes in a single dispatch batch.
    /// Intermediate data stays entirely in VRAM using ping-pong buffers.
    /// </summary>
    public static void DispatchChain(List<(Rid shader, byte[] paramBytes)> stages, HeightMatrix output, uint groupsX, uint groupsY)
    {
        lock (_lock)
        {
            var rd = Device;
            if (rd == null || stages.Count == 0) return;

            int totalBytes = output.Width * output.Height * 4;

            // Two ping-pong buffers for intermediate reads and writes
            Rid buf0 = rd.StorageBufferCreate((uint)totalBytes);
            Rid buf1 = rd.StorageBufferCreate((uint)totalBytes);

            var paramBufs = new Rid[stages.Count];
            var uniformSets = new Rid[stages.Count];
            var pipelines = new Rid[stages.Count];

            Rid currentIn = buf0, currentOut = buf1;
            for (int i = 0; i < stages.Count; i++)
            {
                var (shader, paramBytes) = stages[i];
                paramBufs[i] = rd.StorageBufferCreate((uint)paramBytes.Length, paramBytes);

                var u0 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0 };
                u0.AddId(currentIn);
                var u1 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1 };
                u1.AddId(currentOut);
                var u2 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2 };
                u2.AddId(paramBufs[i]);

                var uniforms = new Godot.Collections.Array<RDUniform> { u0, u1, u2 };
                uniformSets[i] = rd.UniformSetCreate(uniforms, shader, 0);
                pipelines[i] = rd.ComputePipelineCreate(shader);

                // Swap inputs and outputs for next stage
                (currentIn, currentOut) = (currentOut, currentIn);
            }

            long cl = rd.ComputeListBegin();
            for (int i = 0; i < stages.Count; i++)
            {
                rd.ComputeListBindComputePipeline(cl, pipelines[i]);
                rd.ComputeListBindUniformSet(cl, uniformSets[i], 0);
                rd.ComputeListDispatch(cl, groupsX, groupsY, 1);

                // Barrier to prevent read-after-write hazards
                if (i < stages.Count - 1)
                {
                    rd.ComputeListAddBarrier(cl);
                }
            }
            rd.ComputeListEnd();

            rd.Submit();
            rd.Sync(); // Block until complete

            // Final result readback
            Rid finalBuf = (stages.Count % 2 == 0) ? buf0 : buf1;
            byte[] result = rd.BufferGetData(finalBuf);
            result.AsSpan().CopyTo(MemoryMarshal.AsBytes(output.AsSpan()));

            // Free resources
            rd.FreeRid(buf0);
            rd.FreeRid(buf1);
            for (int i = 0; i < stages.Count; i++)
            {
                rd.FreeRid(paramBufs[i]);
                rd.FreeRid(uniformSets[i]);
                rd.FreeRid(pipelines[i]);
            }
        }
    }

    /// <summary>
    /// Dispatches the blending shader synchronously, mapping two input heightfields
    /// and an optional mask buffer on the GPU.
    /// </summary>
    public static void DispatchBlend(Rid shader, HeightMatrix inputA, HeightMatrix inputB, HeightMatrix mask, HeightMatrix output, byte[] paramsBytes, uint groupsX, uint groupsY)
    {
        lock (_lock)
        {
            var rd = Device;
            if (rd == null || !shader.IsValid) return;

            int totalBytes = output.Width * output.Height * 4;

            byte[] bytesA = new byte[totalBytes];
            MemoryMarshal.AsBytes(inputA.AsReadOnlySpan()).CopyTo(bytesA);
            Rid inBufA = rd.StorageBufferCreate((uint)totalBytes, bytesA);

            byte[] bytesB = new byte[totalBytes];
            MemoryMarshal.AsBytes(inputB.AsReadOnlySpan()).CopyTo(bytesB);
            Rid inBufB = rd.StorageBufferCreate((uint)totalBytes, bytesB);

            Rid maskBuf;
            if (mask != null)
            {
                byte[] bytesM = new byte[totalBytes];
                MemoryMarshal.AsBytes(mask.AsReadOnlySpan()).CopyTo(bytesM);
                maskBuf = rd.StorageBufferCreate((uint)totalBytes, bytesM);
            }
            else
            {
                maskBuf = rd.StorageBufferCreate((uint)totalBytes); // Empty dummy buffer
            }

            Rid outBuf = rd.StorageBufferCreate((uint)totalBytes);
            Rid paramBuf = rd.StorageBufferCreate((uint)paramsBytes.Length, paramsBytes);

            var u0 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0 };
            u0.AddId(inBufA);
            var u1 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1 };
            u1.AddId(outBuf);
            var u2 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2 };
            u2.AddId(paramBuf);
            var u3 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3 };
            u3.AddId(inBufB);
            var u4 = new RDUniform { UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4 };
            u4.AddId(maskBuf);

            var uniforms = new Godot.Collections.Array<RDUniform> { u0, u1, u2, u3, u4 };
            Rid uniformSet = rd.UniformSetCreate(uniforms, shader, 0);

            Rid pipeline = rd.ComputePipelineCreate(shader);
            long cl = rd.ComputeListBegin();
            rd.ComputeListBindComputePipeline(cl, pipeline);
            rd.ComputeListBindUniformSet(cl, uniformSet, 0);
            rd.ComputeListDispatch(cl, groupsX, groupsY, 1);
            rd.ComputeListEnd();

            rd.Submit();
            rd.Sync();

            byte[] result = rd.BufferGetData(outBuf);
            result.AsSpan().CopyTo(MemoryMarshal.AsBytes(output.AsSpan()));

            rd.FreeRid(inBufA);
            rd.FreeRid(inBufB);
            rd.FreeRid(maskBuf);
            rd.FreeRid(outBuf);
            rd.FreeRid(paramBuf);
            rd.FreeRid(uniformSet);
            rd.FreeRid(pipeline);
        }
    }

    /// <summary>
    public static void CleanUp()
    {
        lock (_lock)
        {
            int currentThread = System.Environment.CurrentManagedThreadId;
            GD.Print($"[GpuTerrain] CleanUp called. _rd={(_rd != null ? "not null" : "null")}, shaders count={_shaders.Count}, currentThread={currentThread}, mainThread={_mainThreadId}");
            if (_rd != null)
            {
                if (GodotObject.IsInstanceValid(_rd))
                {


                    foreach (var shader in _shaders.Values)
                    {
                        if (shader.IsValid)
                        {
                            try
                            {
                                GD.Print($"[GpuTerrain] Freeing shader RID: {shader.Id}");
                                _rd.FreeRid(shader);
                            }
                            catch (Exception ex)
                            {
                                GD.PrintErr($"[GpuTerrain] Error freeing shader RID: {ex.Message}");
                            }
                        }
                    }
                    _shaders.Clear();

                    try
                    {
                        GD.Print("[GpuTerrain] Freeing native rendering device _rd");
                        _rd.Free();
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[GpuTerrain] Error freeing RenderingDevice: {ex.Message}");
                    }
                }
                _rd = null;
            }
        }
    }
}

