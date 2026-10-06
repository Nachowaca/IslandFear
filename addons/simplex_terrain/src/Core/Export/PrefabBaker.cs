namespace SimpleXTerrain;

using Godot;
using System;
using System.Collections.Generic;

/// <summary>
/// Utility class to bake scattered coordinates into persistent instanced scenes using MultiMeshInstance3D.
/// </summary>
public static class PrefabBaker
{
    /// <summary>
    /// Converts an InstanceSet into a PackedScene containing a MultiMeshInstance3D hierarchy.
    /// </summary>
    /// <param name="instanceSet">The set of scattered object transforms.</param>
    /// <param name="terrainNode">The active Terrain3D node containing the mesh asset reference definitions.</param>
    /// <returns>A PackedScene representing the baked hierarchy.</returns>
    public static PackedScene BakeInstancesToScene(InstanceSet instanceSet, Node terrainNode)
    {
        if (instanceSet == null)
        {
            throw new ArgumentNullException(nameof(instanceSet));
        }

        // Create a root node for the baked scene
        Node3D root = new Node3D();
        root.Name = "BakedVegetation";

        // Group instances by MeshAssetId
        Dictionary<int, List<InstanceTransform>> groupedInstances = new Dictionary<int, List<InstanceTransform>>();
        foreach (var inst in instanceSet.Instances)
        {
            if (!groupedInstances.ContainsKey(inst.MeshAssetId))
            {
                groupedInstances[inst.MeshAssetId] = new List<InstanceTransform>();
            }
            groupedInstances[inst.MeshAssetId].Add(inst);
        }

        // Try to fetch Terrain3DAssets from the terrainNode
        Godot.Collections.Array meshAssetsArray = null;
        if (terrainNode != null)
        {
            try
            {
                var assetsVar = terrainNode.Get("assets");
                if (assetsVar.Obj != null)
                {
                    GodotObject assetsObject = assetsVar.As<GodotObject>();
                    var meshListVar = assetsObject.Get("mesh_list");
                    if (meshListVar.Obj != null)
                    {
                        meshAssetsArray = meshListVar.As<Godot.Collections.Array>();
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[PrefabBaker] Could not retrieve mesh list from Terrain3D: {ex.Message}");
            }
        }

        // For each group, create a MultiMeshInstance3D
        foreach (var pair in groupedInstances)
        {
            int assetId = pair.Key;
            var list = pair.Value;

            if (list.Count == 0) continue;

            Mesh mesh = null;
            string assetName = $"MeshAsset_{assetId}";

            if (meshAssetsArray != null && assetId >= 0 && assetId < meshAssetsArray.Count)
            {
                try
                {
                    GodotObject meshAsset = meshAssetsArray[assetId].As<GodotObject>();
                    if (meshAsset != null)
                    {
                        var nameVar = meshAsset.Get("name");
                        if (nameVar.VariantType != Variant.Type.Nil)
                        {
                            assetName = nameVar.AsString();
                        }

                        // Try to get scene first
                        var sceneVar = meshAsset.Get("scene");
                        if (sceneVar.Obj != null)
                        {
                            PackedScene pScene = sceneVar.As<PackedScene>();
                            if (pScene != null)
                            {
                                mesh = FindMeshInScene(pScene);
                            }
                        }

                        // Fallback to direct mesh reference
                        if (mesh == null)
                        {
                            var meshVar = meshAsset.Get("mesh");
                            if (meshVar.Obj != null)
                            {
                                mesh = meshVar.As<Mesh>();
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[PrefabBaker] Failed to extract mesh for asset ID {assetId}: {ex.Message}");
                }
            }

            // Fallback mesh if we couldn't resolve it
            if (mesh == null)
            {
                var box = new BoxMesh();
                box.Size = new Vector3(1, 2, 1);
                mesh = box;
            }

            // Create MultiMeshInstance3D
            MultiMeshInstance3D mmi = new MultiMeshInstance3D();
            mmi.Name = assetName;

            MultiMesh mm = new MultiMesh();
            mm.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
            mm.UseColors = false;
            mm.UseCustomData = false;
            mm.Mesh = mesh;
            mm.InstanceCount = list.Count;

            for (int i = 0; i < list.Count; i++)
            {
                var inst = list[i];
                Transform3D t = new Transform3D(new Basis(inst.Rotation), inst.Position);
                t.Basis = t.Basis.Scaled(inst.Scale);
                mm.SetInstanceTransform(i, t);
            }

            mmi.Multimesh = mm;
            root.AddChild(mmi);
            mmi.Owner = root; // Required so the nodes are saved into the PackedScene
        }

        PackedScene packedScene = new PackedScene();
        Error err = packedScene.Pack(root);
        if (err != Error.Ok)
        {
            GD.PrintErr($"[PrefabBaker] Packing scene failed with error: {err}");
        }

        // Free root node as it is cloned/packed and no longer needed in the active tree
        root.QueueFree();

        return packedScene;
    }

    private static Mesh FindMeshInScene(PackedScene pScene)
    {
        if (pScene == null) return null;
        Node instance = pScene.Instantiate();
        if (instance == null) return null;

        Mesh mesh = FindMeshInNode(instance);
        instance.Free();
        return mesh;
    }

    private static Mesh FindMeshInNode(Node node)
    {
        if (node is MeshInstance3D mi)
        {
            return mi.Mesh;
        }
        for (int i = 0; i < node.GetChildCount(); i++)
        {
            Mesh m = FindMeshInNode(node.GetChild(i));
            if (m != null) return m;
        }
        return null;
    }
}
