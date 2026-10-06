using Godot;
using System;
using System.Collections.Generic;

namespace SimpleXTerrain;

#region Resources


#endregion

#region Nodes

/// <summary>
/// Runtime node that downsamples a continuous density mask and stochastically discretizes instances.
/// </summary>
public partial class FoliageDensityNode : TerrainNode
{
    public FoliageDensityNodeResource AssociatedResource { get; set; }

    public FoliageDensityNode()
    {
        Inputs.Add(new Port("density_in", PortType.Mask, PortDirection.Input));
        Inputs.Add(new Port("biome_mask", PortType.Mask, PortDirection.Input)); // Optional
        Outputs.Add(new Port("instance_out", PortType.Instance, PortDirection.Output));
        InitializePorts();
    }

    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        float densityFactor = AssociatedResource != null ? AssociatedResource.DensityFactor : 10.0f;
        int downscaleFactor = AssociatedResource != null ? Math.Max(1, AssociatedResource.DownscaleFactor) : 4;
        int seedVal = AssociatedResource != null ? AssociatedResource.Seed : 1337;
        int meshAssetId = AssociatedResource != null ? AssociatedResource.MeshAssetId : 1;
        float minScale = AssociatedResource != null ? AssociatedResource.MinScale : 0.8f;
        float maxScale = AssociatedResource != null ? AssociatedResource.MaxScale : 1.2f;
        float minHeightOffset = AssociatedResource != null ? AssociatedResource.MinHeightOffset : 0.0f;
        float maxHeightOffset = AssociatedResource != null ? AssociatedResource.MaxHeightOffset : 0.0f;

        HeightMatrix densityHM = null;
        if (InputLinks.Length > 0 && InputLinks[0].SourceNode != null)
        {
            var link = InputLinks[0];
            densityHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        HeightMatrix biomeMaskHM = null;
        if (InputLinks.Length > 1 && InputLinks[1].SourceNode != null)
        {
            var link = InputLinks[1];
            biomeMaskHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        var instanceSetOut = new InstanceSet();
        if (densityHM == null)
        {
            return instanceSetOut;
        }

        int N_full = ctx.PaddedSize;
        int R = downscaleFactor;

        // Target downscaled resolution: N_target = (N_full - 1) / R + 1 (Ref: Module 15 §2)
        int N_target = (N_full - 1) / R + 1;
        N_target = Math.Max(1, N_target);

        float cellSize = ctx.WorldSize / ctx.Resolution;

        // Core chunk bounds for output filtering
        float xMin = ctx.WorldOrigin.X;
        float xMax = ctx.WorldOrigin.X + ctx.WorldSize;
        float zMin = ctx.WorldOrigin.Z;
        float zMax = ctx.WorldOrigin.Z + ctx.WorldSize;

        int chunkSeed = seedVal ^ ctx.Coord.GetHashCode();
        int nextId = 1;

        // Local helpers for bilinear cross-resolution sampling
        float SampleBilinear(HeightMatrix hm, float u, float v)
        {
            if (hm == null) return 0.0f;
            float px = u * (hm.Width - 1);
            float pz = v * (hm.Height - 1);

            int x0 = Math.Clamp((int)MathF.Floor(px), 0, hm.Width - 1);
            int x1 = Math.Clamp(x0 + 1, 0, hm.Width - 1);
            int z0 = Math.Clamp((int)MathF.Floor(pz), 0, hm.Height - 1);
            int z1 = Math.Clamp(z0 + 1, 0, hm.Height - 1);

            float fx = px - MathF.Floor(px);
            float fz = pz - MathF.Floor(pz);

            float v00 = hm.GetValue(x0, z0);
            float v10 = hm.GetValue(x1, z0);
            float v01 = hm.GetValue(x0, z1);
            float v11 = hm.GetValue(x1, z1);

            float v0 = Mathf.Lerp(v00, v10, fx);
            float v1 = Mathf.Lerp(v01, v11, fx);

            return Mathf.Lerp(v0, v1, fz);
        }

        float GetDensityVal(int sx, int sz)
        {
            float u = Math.Clamp((float)sx / (N_full - 1), 0.0f, 1.0f);
            float v = Math.Clamp((float)sz / (N_full - 1), 0.0f, 1.0f);
            return SampleBilinear(densityHM, u, v);
        }

        float GetBiomeMaskVal(int sx, int sz)
        {
            if (biomeMaskHM == null) return 1.0f;
            float u = Math.Clamp((float)sx / (N_full - 1), 0.0f, 1.0f);
            float v = Math.Clamp((float)sz / (N_full - 1), 0.0f, 1.0f);
            return SampleBilinear(biomeMaskHM, u, v);
        }

        for (int z = 0; z < N_target; z++)
        {
            int srcZ = Math.Clamp(z * R, 0, N_full - 2);

            for (int x = 0; x < N_target; x++)
            {
                int srcX = Math.Clamp(x * R, 0, N_full - 2);

                // 1. Neighborhood-Minimum Downscaling using bilinear cross-resolution sampling
                float v00 = GetDensityVal(srcX, srcZ);
                float v10 = GetDensityVal(srcX + 1, srcZ);
                float v01 = GetDensityVal(srcX, srcZ + 1);
                float v11 = GetDensityVal(srcX + 1, srcZ + 1);

                float vInterp = MathF.Min(MathF.Min(v00, v10), MathF.Min(v01, v11));

                // 2. Biome Masking
                float maskVal = GetBiomeMaskVal(srcX, srcZ);

                float vWeighted = Math.Clamp(vInterp * maskVal, 0.0f, 1.0f);
                if (vWeighted <= 0.0001f)
                {
                    continue;
                }

                // 3. Area Density Scaling (Ref: Module 15 §2)
                // Expected continuous density: mu = vWeighted * D * P_x * P_z * R^2
                float mu = vWeighted * densityFactor * (cellSize * cellSize) * (R * R);

                // 4. Stochastic Integer Rounding (Ref: Module 15 §2)
                int k = (int)MathF.Floor(mu);
                float f = mu - k;

                float r = GetDeterministicFloat(x, z, chunkSeed);
                int nInstances = f > r ? k + 1 : k;

                // 5. Spawn instances in cell
                for (int j = 0; j < nInstances; j++)
                {
                    // Generate pseudo-random offset within cell bounds in pixel units [0, R)
                    float offsetX = GetDeterministicFloat(x, z, chunkSeed + j * 10 + 1) * R;
                    float offsetZ = GetDeterministicFloat(x, z, chunkSeed + j * 10 + 2) * R;

                    float px = x * R + offsetX;
                    float pz = z * R + offsetZ;

                    Vector3 pos = CoordinateMapping.PixelToWorld(new Vector2(px, pz), ctx);

                    // Output only instances that reside within core chunk boundaries
                    if (pos.X >= xMin && pos.X < xMax && pos.Z >= zMin && pos.Z < zMax)
                    {
                        uint hash = (uint)x ^ (uint)z ^ (uint)chunkSeed ^ (uint)j;

                        // Random yaw rotation
                        float yaw = GetDeterministicFloat(x, z, chunkSeed + j * 10 + 3) * 360.0f;
                        Quaternion rot = Quaternion.FromEuler(new Vector3(0f, Mathf.DegToRad(yaw), 0f));

                        // Random scale
                        float sVar = minScale + GetDeterministicFloat(x, z, chunkSeed + j * 10 + 4) * (maxScale - minScale);
                        Vector3 scale = new Vector3(sVar, sVar, sVar);

                        // Random height offset
                        float hOffset = minHeightOffset + GetDeterministicFloat(x, z, chunkSeed + j * 10 + 5) * (maxHeightOffset - minHeightOffset);
                        Vector3 finalPos = new Vector3(pos.X, pos.Y + hOffset, pos.Z);

                        instanceSetOut.Add(new InstanceTransform(
                            finalPos,
                            rot,
                            scale,
                            meshAssetId,
                            hash,
                            nextId++
                        ));
                    }
                }
            }
        }

        return instanceSetOut;
    }

    private static float GetDeterministicFloat(int x, int z, int seed)
    {
        uint hash = (uint)x;
        hash = (hash ^ 0x12345678) + (uint)z;
        hash = (hash ^ 0x9e3779b9) + (uint)seed;
        hash = hash ^ (hash >> 16);
        hash *= 0x7feb352d;
        hash = hash ^ (hash >> 15);
        hash *= 0x846ca68b;
        hash = hash ^ (hash >> 16);
        return (float)(hash & 0x7FFFFFFF) / 0x7FFFFFFF;
    }
}

#endregion
