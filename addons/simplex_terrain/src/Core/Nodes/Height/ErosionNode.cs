using Godot;
using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace SimpleXTerrain;

/// <summary>
/// Runtime node that performs a multi-stage cellular hydraulic and soil erosion simulation.
/// All three output ports (Height, Water, Sediment) are computed in a single simulation pass
/// and cached together, so pulling any port only runs the simulation once per chunk.
/// </summary>
public partial class ErosionNode : TerrainNode
{
    /// <summary>
    /// Gets or sets the associated configuration parameters resource.
    /// </summary>
    public ErosionNodeResource AssociatedResource { get; set; }

    /// <summary>
    /// Internal cache holding all 3 erosion outputs for a given chunk so the
    /// simulation is never run more than once per chunk coordinate.
    /// </summary>
    private readonly ConcurrentDictionary<ChunkCoordinate, Lazy<ErosionResult>> _erosionCache = new();

    /// <summary>
    /// Simple container for the three outputs of a single erosion simulation.
    /// </summary>
    private sealed class ErosionResult : IDisposable
    {
        public HeightMatrix Height;
        public HeightMatrix Water;
        public HeightMatrix Sediment;

        public void Dispose()
        {
            Height?.Dispose();
            Water?.Dispose();
            Sediment?.Dispose();
        }
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="ErosionNode"/> class.
    /// </summary>
    public ErosionNode()
    {
        Inputs.Add(new Port("Height", PortType.Height, PortDirection.Input));
        Outputs.Add(new Port("Height", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("Water", PortType.Height, PortDirection.Output));
        Outputs.Add(new Port("Sediment", PortType.Height, PortDirection.Output));
        InitializePorts();
    }

    private struct CellInfo
    {
        public int Index;
        public float Height;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static uint FloatToSortableUint(float val)
    {
        uint bits = BitConverter.SingleToUInt32Bits(val);
        return (bits & 0x80000000) != 0 ? ~bits : bits ^ 0x80000000;
    }

    // High-performance float radix sort (O(N))
    private static void RadixSortCells(CellInfo[] source, CellInfo[] temp, int count)
    {
        // 4 passes (8 bits per pass) for 32-bit uint keys
        int[] countBuffer = ArrayPool<int>.Shared.Rent(256);
        try
        {
            CellInfo[] from = source;
            CellInfo[] to = temp;

            for (int byteOffset = 0; byteOffset < 4; byteOffset++)
            {
                int shift = byteOffset * 8;
                Array.Clear(countBuffer, 0, 256);

                // 1. Calculate histograms
                for (int i = 0; i < count; i++)
                {
                    uint key = FloatToSortableUint(from[i].Height);
                    int bucket = (int)((key >> shift) & 0xFF);
                    countBuffer[bucket]++;
                }

                // 2. Prefix sums
                int sum = 0;
                for (int i = 0; i < 256; i++)
                {
                    int prevSum = sum;
                    sum += countBuffer[i];
                    countBuffer[i] = prevSum;
                }

                // 3. Scatter into destination
                for (int i = 0; i < count; i++)
                {
                    uint key = FloatToSortableUint(from[i].Height);
                    int bucket = (int)((key >> shift) & 0xFF);
                    int destIndex = countBuffer[bucket]++;
                    to[destIndex] = from[i];
                }

                // Swap buffers
                var swap = from;
                from = to;
                to = swap;
            }

            // Ensure output is in the source array
            if (from != source)
            {
                Array.Copy(from, source, count);
            }
        }
        finally
        {
            ArrayPool<int>.Shared.Return(countBuffer);
        }
    }

    /// <summary>
    /// Runs the full erosion simulation once and returns all 3 outputs.
    /// </summary>
    private ErosionResult RunSimulation(GenerationContext ctx)
    {
        float durability = AssociatedResource != null ? AssociatedResource.Durability : 0.5f;
        float erosionStrength = AssociatedResource != null ? AssociatedResource.ErosionStrength : 0.3f;
        float sedimentDensity = AssociatedResource != null ? AssociatedResource.SedimentDensity : 0.1f;
        int fluidity = AssociatedResource != null ? AssociatedResource.Fluidity : 5;
        int numIterations = AssociatedResource != null ? AssociatedResource.Iterations : 10;

        durability = Math.Clamp(durability, 0.0f, 0.999f);
        erosionStrength = MathF.Max(0.0f, erosionStrength);
        sedimentDensity = MathF.Max(0.0f, sedimentDensity);
        fluidity = Math.Clamp(fluidity, 0, 100);
        numIterations = Math.Clamp(numIterations, 1, 100);

        HeightMatrix inputHM = null;
        var link = InputLinks[0];
        if (link.SourceNode != null)
        {
            inputHM = link.SourceNode.PullReadOnlyHeight(ctx, link.SourcePortIndex);
        }

        if (inputHM == null)
        {
            return new ErosionResult
            {
                Height = ctx.AllocateHeightMatrix(),
                Water = ctx.AllocateHeightMatrix(),
                Sediment = ctx.AllocateHeightMatrix(),
            };
        }

        int width = inputHM.Width;
        int height = inputHM.Height;

        HeightMatrix H = ctx.AllocateHeightMatrix();
        HeightMatrix W = ctx.AllocateHeightMatrix();
        HeightMatrix M = ctx.AllocateHeightMatrix();
        HeightMatrix prePourM = ctx.AllocateHeightMatrix();

        var spanInput = inputHM.AsReadOnlySpan();
        var spanH = H.AsSpan();
        var spanW = W.AsSpan();
        var spanM = M.AsSpan();
        var spanPrePourM = prePourM.AsSpan();

        spanInput.CopyTo(spanH);

        int numNonBoundary = (width - 2) * (height - 2);
        if (numNonBoundary <= 0)
        {
            prePourM.Dispose();
            return new ErosionResult { Height = H, Water = W, Sediment = M };
        }

        // Rent coordinate array and temp array for radix sort ping-ponging
        CellInfo[] cells = ArrayPool<CellInfo>.Shared.Rent(numNonBoundary);
        CellInfo[] radixTemp = ArrayPool<CellInfo>.Shared.Rent(numNonBoundary);
        try
        {
            // Seed coordinates once
            int idx = 0;
            for (int z = 1; z < height - 1; z++)
            {
                int rowOff = z * width;
                for (int x = 1; x < width - 1; x++)
                {
                    int cIdx = rowOff + x;
                    cells[idx++] = new CellInfo
                    {
                        Index = cIdx,
                        Height = spanInput[cIdx]
                    };
                }
            }

            // O(N) Radix Sort: run only once at the beginning
            RadixSortCells(cells, radixTemp, numNonBoundary);

            // Get direct bounds-check-free data references for extreme performance in hot loops
            ref float refH = ref MemoryMarshal.GetArrayDataReference(H.RawData);
            ref float refW = ref MemoryMarshal.GetArrayDataReference(W.RawData);
            ref float refM = ref MemoryMarshal.GetArrayDataReference(M.RawData);
            ref float refPrePourM = ref MemoryMarshal.GetArrayDataReference(prePourM.RawData);

            for (int iterPass = 0; iterPass < numIterations; iterPass++)
            {
                ctx.CancellationToken.ThrowIfCancellationRequested();

                spanW.Fill(1.0f);
                spanM.Fill(0.0f);

                // ----------------------------------------------------
                // Stage 1: Moore Flow Accumulation (Torrents) - Sorted Order
                // ----------------------------------------------------
                for (int j = numNonBoundary - 1; j >= 0; j--)
                {
                    CellInfo cell = cells[j];
                    int cIdx = cell.Index;

                    float W_c = Unsafe.Add(ref refW, cIdx);
                    W_c = MathF.Min(W_c, 200000000.0f);
                    Unsafe.Add(ref refW, cIdx) = W_c;

                    float hCenter = Unsafe.Add(ref refH, cIdx);
                    float sumDelta = 0.0f;

                    // Unrolled 8-neighbor offsets
                    int nTL = cIdx - width - 1; float dTL = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nTL));
                    int nTC = cIdx - width;     float dTC = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nTC));
                    int nTR = cIdx - width + 1; float dTR = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nTR));
                    int nCL = cIdx - 1;         float dCL = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nCL));
                    int nCR = cIdx + 1;         float dCR = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nCR));
                    int nBL = cIdx + width - 1; float dBL = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nBL));
                    int nBC = cIdx + width;     float dBC = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nBC));
                    int nBR = cIdx + width + 1; float dBR = MathF.Max(0.0f, hCenter - Unsafe.Add(ref refH, nBR));

                    sumDelta = dTL + dTC + dTR + dCL + dCR + dBL + dBC + dBR;

                    if (sumDelta > 1e-5f)
                    {
                        float invSum = W_c / sumDelta;
                        if (dTL > 0f) Unsafe.Add(ref refW, nTL) += dTL * invSum;
                        if (dTC > 0f) Unsafe.Add(ref refW, nTC) += dTC * invSum;
                        if (dTR > 0f) Unsafe.Add(ref refW, nTR) += dTR * invSum;
                        if (dCL > 0f) Unsafe.Add(ref refW, nCL) += dCL * invSum;
                        if (dCR > 0f) Unsafe.Add(ref refW, nCR) += dCR * invSum;
                        if (dBL > 0f) Unsafe.Add(ref refW, nBL) += dBL * invSum;
                        if (dBC > 0f) Unsafe.Add(ref refW, nBC) += dBC * invSum;
                        if (dBR > 0f) Unsafe.Add(ref refW, nBR) += dBR * invSum;
                    }
                }

                // ----------------------------------------------------
                // Stage 2: Von Neumann Soil Erosion - Cache-Friendly Spatial Order
                // ----------------------------------------------------
                for (int z = 1; z < height - 1; z++)
                {
                    int rowOff = z * width;
                    for (int x = 1; x < width - 1; x++)
                    {
                        int cIdx = rowOff + x;
                        float waterVal = Unsafe.Add(ref refW, cIdx);
                        if (waterVal < 1.001f) continue;

                        float hCenter = Unsafe.Add(ref refH, cIdx);

                        float hW = Unsafe.Add(ref refH, cIdx - 1);
                        float hE = Unsafe.Add(ref refH, cIdx + 1);
                        float hN = Unsafe.Add(ref refH, cIdx - width);
                        float hS = Unsafe.Add(ref refH, cIdx + width);
                        float hMin = MathF.Min(MathF.Min(hW, hE), MathF.Min(hN, hS));

                        float hErode = (hCenter + hMin) * 0.5f;
                        if (hCenter <= hErode) continue;

                        float dS_potential = hCenter - hErode;
                        float dS_capacity = dS_potential * (waterVal - 1.0f) * (1.0f - durability);
                        float sLift = MathF.Min(dS_potential, dS_capacity) * erosionStrength;

                        Unsafe.Add(ref refH, cIdx) -= sLift;
                        Unsafe.Add(ref refM, cIdx) += sLift * sedimentDensity;
                    }
                }

                if (iterPass == numIterations - 1)
                {
                    spanM.CopyTo(spanPrePourM);
                }

                // ----------------------------------------------------
                // Stage 3: Von Neumann Sediment Spreading & Settling - Spatial Order
                // ----------------------------------------------------
                for (int iter = 0; iter < fluidity; iter++)
                {
                    ctx.CancellationToken.ThrowIfCancellationRequested();
                    for (int z = 1; z < height - 1; z++)
                    {
                        int rowOff = z * width;
                        for (int x = 1; x < width - 1; x++)
                        {
                            int cIdx = rowOff + x;
                            float mC = Unsafe.Add(ref refM, cIdx);
                            
                            int wIdx = cIdx - 1;
                            int eIdx = cIdx + 1;
                            int nIdx = cIdx - width;
                            int sIdx = cIdx + width;

                            if (mC < 1e-5f)
                            {
                                if (Unsafe.Add(ref refM, wIdx) < 1e-5f &&
                                    Unsafe.Add(ref refM, eIdx) < 1e-5f &&
                                    Unsafe.Add(ref refM, nIdx) < 1e-5f &&
                                    Unsafe.Add(ref refM, sIdx) < 1e-5f)
                                {
                                    continue;
                                }
                            }

                            float mW = Unsafe.Add(ref refM, wIdx);
                            float mE = Unsafe.Add(ref refM, eIdx);
                            float mN = Unsafe.Add(ref refM, nIdx);
                            float mS = Unsafe.Add(ref refM, sIdx);

                            float sumMud = mC + mW + mE + mN + mS;
                            if (sumMud < 0.00001f) continue;

                            float hC = Unsafe.Add(ref refH, cIdx);
                            float hW = Unsafe.Add(ref refH, wIdx);
                            float hE = Unsafe.Add(ref refH, eIdx);
                            float hN = Unsafe.Add(ref refH, nIdx);
                            float hS = Unsafe.Add(ref refH, sIdx);

                            float sumHM = (hC + mC) + (hW + mW) + (hE + mE) + (hN + mN) + (hS + mS);
                            float avg = sumHM * 0.2f;

                            float pC = MathF.Max(0.0f, avg - hC);
                            float pW = MathF.Max(0.0f, avg - hW);
                            float pE = MathF.Max(0.0f, avg - hE);
                            float pN = MathF.Max(0.0f, avg - hN);
                            float pS = MathF.Max(0.0f, avg - hS);

                            float sumP = pC + pW + pE + pN + pS;
                            int activeCount = 0;
                            if (pC > 0.0001f) activeCount++;
                            if (pW > 0.0001f) activeCount++;
                            if (pE > 0.0001f) activeCount++;
                            if (pN > 0.0001f) activeCount++;
                            if (pS > 0.0001f) activeCount++;

                            if (activeCount > 0)
                            {
                                float deltaOffset = (sumP - sumMud) / activeCount;
                                pC = pC > 0.0001f ? MathF.Max(0.0f, pC - deltaOffset) : 0.0f;
                                pW = pW > 0.0001f ? MathF.Max(0.0f, pW - deltaOffset) : 0.0f;
                                pE = pE > 0.0001f ? MathF.Max(0.0f, pE - deltaOffset) : 0.0f;
                                pN = pN > 0.0001f ? MathF.Max(0.0f, pN - deltaOffset) : 0.0f;
                                pS = pS > 0.0001f ? MathF.Max(0.0f, pS - deltaOffset) : 0.0f;
                                sumP = pC + pW + pE + pN + pS;
                            }

                            if (sumP < 0.000001f)
                            {
                                pC = pW = pE = pN = pS = 0.0f;
                            }
                            else if (MathF.Abs(sumP - sumMud) > 0.00001f)
                            {
                                float scale = sumMud / sumP;
                                pC *= scale;
                                pW *= scale;
                                pE *= scale;
                                pN *= scale;
                                pS *= scale;
                            }

                            Unsafe.Add(ref refM, cIdx) = pC;
                            Unsafe.Add(ref refM, wIdx) = (x - 1 == 0) ? 0.0f : pW;
                            Unsafe.Add(ref refM, eIdx) = (x + 1 == width - 1) ? 0.0f : pE;
                            Unsafe.Add(ref refM, nIdx) = (z - 1 == 0) ? 0.0f : pN;
                            Unsafe.Add(ref refM, sIdx) = (z + 1 == height - 1) ? 0.0f : pS;
                        }
                    }
                }

                // Settling Pass (Exact clamping in Spatial Order)
                for (int z = 1; z < height - 1; z++)
                {
                    int rowOff = z * width;
                    for (int x = 1; x < width - 1; x++)
                    {
                        int cIdx = rowOff + x;
                        float originalH = Unsafe.Add(ref refH, cIdx);
                        float depositedH = originalH + Unsafe.Add(ref refM, cIdx);

                        float maxNeigh = originalH;
                        float hW = Unsafe.Add(ref refH, cIdx - 1);
                        float hE = Unsafe.Add(ref refH, cIdx + 1);
                        float hN = Unsafe.Add(ref refH, cIdx - width);
                        float hS = Unsafe.Add(ref refH, cIdx + width);

                        if (hW > maxNeigh) maxNeigh = hW;
                        if (hE > maxNeigh) maxNeigh = hE;
                        if (hN > maxNeigh) maxNeigh = hN;
                        if (hS > maxNeigh) maxNeigh = hS;

                        Unsafe.Add(ref refH, cIdx) = MathF.Min(depositedH, maxNeigh);
                    }
                }
            }

            M.Dispose(); // M was the working sediment buffer; prePourM has the final snapshot
            return new ErosionResult { Height = H, Water = W, Sediment = prePourM };
        }
        finally
        {
            ArrayPool<CellInfo>.Shared.Return(cells);
            ArrayPool<CellInfo>.Shared.Return(radixTemp);
        }
    }

    /// <summary>
    /// Evaluates the erosion simulation. Uses an internal multi-output cache so the
    /// heavy simulation only runs once regardless of how many ports are pulled.
    /// </summary>
    protected override object Evaluate(GenerationContext ctx, int outputPortIndex)
    {
        var lazy = _erosionCache.GetOrAdd(ctx.Coord, _ => new Lazy<ErosionResult>(() => RunSimulation(ctx)));
        var result = lazy.Value;

        return outputPortIndex switch
        {
            0 => result.Height,
            1 => result.Water,
            _ => result.Sediment,
        };
    }

    /// <summary>
    /// Clears the internal multi-output erosion cache when the base class cache is cleared.
    /// </summary>
    public override void ClearCache()
    {
        foreach (var kvp in _erosionCache)
        {
            if (kvp.Value.IsValueCreated)
            {
                kvp.Value.Value.Dispose();
            }
        }
        _erosionCache.Clear();
        base.ClearCache();
    }

    /// <summary>
    /// Clears the internal multi-output erosion cache for a specific chunk.
    /// </summary>
    public override void ClearCacheForChunk(ChunkCoordinate coord)
    {
        if (_erosionCache.TryRemove(coord, out var lazy))
        {
            if (lazy.IsValueCreated)
            {
                lazy.Value.Dispose();
            }
        }
        base.ClearCacheForChunk(coord);
    }
}
