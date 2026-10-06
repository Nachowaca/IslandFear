namespace SimpleXTerrain;

using Godot;
using System;
using System.Reflection;

/// <summary>
/// Utility class to serialize and deserialize TerrainGraphResource objects to/from JSON.
/// </summary>
public static class JsonGraphSerializer
{
    /// <summary>
    /// Serializes a TerrainGraphResource graph to a JSON string.
    /// </summary>
    public static string Serialize(TerrainGraphResource graph)
    {
        if (graph == null)
        {
            throw new ArgumentNullException(nameof(graph));
        }

        var rootDict = new Godot.Collections.Dictionary<string, Variant>();

        // 1. Serialize Nodes
        var nodesArray = new Godot.Collections.Array<Godot.Collections.Dictionary<string, Variant>>();
        foreach (var nodeRes in graph.Nodes)
        {
            if (nodeRes == null) continue;

            var nodeDict = new Godot.Collections.Dictionary<string, Variant>();
            nodeDict["NodeId"] = nodeRes.NodeId;
            nodeDict["NodeType"] = nodeRes.NodeType;

            var posArray = new Godot.Collections.Array<float> { nodeRes.EditorPosition.X, nodeRes.EditorPosition.Y };
            nodeDict["EditorPosition"] = posArray;

            var propsDict = new Godot.Collections.Dictionary<string, Variant>();
            var properties = nodeRes.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance);
            foreach (var prop in properties)
            {
                // Only serialize properties marked with [Export]
                if (prop.GetCustomAttribute<ExportAttribute>() == null)
                {
                    continue;
                }

                // Skip base metadata properties handled at the root level
                if (prop.Name == "NodeId" || prop.Name == "NodeType" || prop.Name == "EditorPosition")
                {
                    continue;
                }

                if (prop.CanRead && prop.CanWrite)
                {
                    object val = prop.GetValue(nodeRes);
                    if (val == null)
                    {
                        propsDict[prop.Name] = new Variant();
                        continue;
                    }

                    Type t = prop.PropertyType;
                    if (t == typeof(Vector2))
                    {
                        Vector2 v = (Vector2)val;
                        propsDict[prop.Name] = new Godot.Collections.Array<float> { v.X, v.Y };
                    }
                    else if (t == typeof(Color))
                    {
                        Color c = (Color)val;
                        propsDict[prop.Name] = new Godot.Collections.Array<float> { c.R, c.G, c.B, c.A };
                    }
                    else if (t == typeof(NodePath))
                    {
                        propsDict[prop.Name] = ((NodePath)val).ToString();
                    }
                    else if (t.IsEnum)
                    {
                        propsDict[prop.Name] = val.ToString();
                    }
                    else if (typeof(Resource).IsAssignableFrom(t))
                    {
                        Resource r = (Resource)val;
                        propsDict[prop.Name] = r.ResourcePath;
                    }
                    else
                    {
                        propsDict[prop.Name] = ConvertToVariant(val);
                    }
                }
            }

            nodeDict["Properties"] = propsDict;
            nodesArray.Add(nodeDict);
        }
        rootDict["Nodes"] = nodesArray;

        // 2. Serialize Connections
        var connsArray = new Godot.Collections.Array<Godot.Collections.Dictionary<string, Variant>>();
        foreach (var conn in graph.Connections)
        {
            if (conn == null) continue;

            var connDict = new Godot.Collections.Dictionary<string, Variant>
            {
                { "FromNodeId", conn.FromNodeId },
                { "FromPort", conn.FromPort },
                { "ToNodeId", conn.ToNodeId },
                { "ToPort", conn.ToPort }
            };
            connsArray.Add(connDict);
        }
        rootDict["Connections"] = connsArray;

        return Json.Stringify(rootDict, "  ");
    }

    /// <summary>
    /// Deserializes a JSON string back into a TerrainGraphResource object.
    /// </summary>
    public static TerrainGraphResource Deserialize(string jsonString)
    {
        if (string.IsNullOrWhiteSpace(jsonString))
        {
            throw new ArgumentException("JSON string cannot be empty.", nameof(jsonString));
        }

        Json json = new Json();
        Error err = json.Parse(jsonString);
        if (err != Error.Ok)
        {
            throw new InvalidOperationException($"JSON Parse failed with error: {err} at line {json.GetErrorLine()}: {json.GetErrorMessage()}");
        }

        var rootDict = json.Data.AsGodotDictionary();
        var graph = new TerrainGraphResource();

        // 1. Deserialize Nodes
        if (rootDict.TryGetValue("Nodes", out Variant nodesVar))
        {
            var nodesArray = nodesVar.AsGodotArray();
            foreach (var nodeVal in nodesArray)
            {
                var nodeDict = nodeVal.AsGodotDictionary();
                string nodeId = nodeDict["NodeId"].AsString();
                string nodeType = nodeDict["NodeType"].AsString();

                TerrainNodeResource nodeRes = CreateNodeResourceInstance(nodeType);
                nodeRes.NodeId = nodeId;

                // Load EditorPosition
                if (nodeDict.TryGetValue("EditorPosition", out Variant posVar))
                {
                    var posArr = posVar.AsGodotArray();
                    if (posArr.Count >= 2)
                    {
                        nodeRes.EditorPosition = new Vector2(posArr[0].AsSingle(), posArr[1].AsSingle());
                    }
                }

                // Load Properties
                if (nodeDict.TryGetValue("Properties", out Variant propsVar))
                {
                    var propsDict = propsVar.AsGodotDictionary();
                    foreach (var pair in propsDict)
                    {
                        string propName = pair.Key.AsString();
                        Variant valVar = pair.Value;

                        PropertyInfo prop = nodeRes.GetType().GetProperty(propName, BindingFlags.Public | BindingFlags.Instance);
                        if (prop != null && prop.CanWrite)
                        {
                            if (valVar.Obj == null && valVar.VariantType == Variant.Type.Nil)
                            {
                                prop.SetValue(nodeRes, null);
                                continue;
                            }

                            Type targetType = prop.PropertyType;

                            if (targetType == typeof(float))
                            {
                                prop.SetValue(nodeRes, valVar.AsSingle());
                            }
                            else if (targetType == typeof(double))
                            {
                                prop.SetValue(nodeRes, valVar.AsDouble());
                            }
                            else if (targetType == typeof(int))
                            {
                                prop.SetValue(nodeRes, valVar.AsInt32());
                            }
                            else if (targetType == typeof(uint))
                            {
                                prop.SetValue(nodeRes, valVar.AsUInt32());
                            }
                            else if (targetType == typeof(bool))
                            {
                                prop.SetValue(nodeRes, valVar.AsBool());
                            }
                            else if (targetType == typeof(string))
                            {
                                prop.SetValue(nodeRes, valVar.AsString());
                            }
                            else if (targetType == typeof(Vector2))
                            {
                                var arr = valVar.AsGodotArray();
                                prop.SetValue(nodeRes, new Vector2(arr[0].AsSingle(), arr[1].AsSingle()));
                            }
                            else if (targetType == typeof(Color))
                            {
                                var arr = valVar.AsGodotArray();
                                prop.SetValue(nodeRes, new Color(arr[0].AsSingle(), arr[1].AsSingle(), arr[2].AsSingle(), arr[3].AsSingle()));
                            }
                            else if (targetType == typeof(NodePath))
                            {
                                prop.SetValue(nodeRes, new NodePath(valVar.AsString()));
                            }
                            else if (targetType.IsEnum)
                            {
                                prop.SetValue(nodeRes, Enum.Parse(targetType, valVar.AsString()));
                            }
                            else if (typeof(Resource).IsAssignableFrom(targetType))
                            {
                                string path = valVar.AsString();
                                if (!string.IsNullOrEmpty(path))
                                {
                                    Resource res = GD.Load(path);
                                    prop.SetValue(nodeRes, res);
                                }
                            }
                            else
                            {
                                prop.SetValue(nodeRes, valVar.Obj);
                            }
                        }
                    }
                }

                graph.Nodes.Add(nodeRes);
            }
        }

        // 2. Deserialize Connections
        if (rootDict.TryGetValue("Connections", out Variant connsVar))
        {
            var connsArray = connsVar.AsGodotArray();
            foreach (var connVal in connsArray)
            {
                var connDict = connVal.AsGodotDictionary();
                ConnectionData conn = new ConnectionData
                {
                    FromNodeId = connDict["FromNodeId"].AsString(),
                    FromPort = connDict["FromPort"].AsInt32(),
                    ToNodeId = connDict["ToNodeId"].AsString(),
                    ToPort = connDict["ToPort"].AsInt32()
                };
                graph.Connections.Add(conn);
            }
        }

        return graph;
    }

    private static TerrainNodeResource CreateNodeResourceInstance(string nodeType)
    {
        string resTypeName1 = $"{nodeType}Resource";
        string resTypeName2 = $"{nodeType}NodeResource";

        Type type = null;
        foreach (var name in new[] { resTypeName1, resTypeName2 })
        {
            type = Type.GetType(name)
                   ?? Type.GetType($"SimpleXTerrain.{name}")
                   ?? Type.GetType($"SimpleXTerrain.Core.Nodes.{name}");

            if (type == null)
            {
                foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
                {
                    type = assembly.GetType(name)
                           ?? assembly.GetType($"SimpleXTerrain.{name}")
                           ?? assembly.GetType($"SimpleXTerrain.Core.Nodes.{name}");
                    if (type != null) break;
                }
            }
            if (type != null) break;
        }

        if (type == null)
        {
            throw new InvalidOperationException($"Could not resolve C# Resource class for '{nodeType}'. Tried '{resTypeName1}' and '{resTypeName2}'.");
        }

        return (TerrainNodeResource)Activator.CreateInstance(type);
    }

    private static Variant ConvertToVariant(object val)
    {
        if (val == null) return new Variant();
        if (val is string s) return Variant.From(s);
        if (val is bool b) return Variant.From(b);
        if (val is int i) return Variant.From(i);
        if (val is float f) return Variant.From(f);
        if (val is double d) return Variant.From(d);
        if (val is Vector2 v) return Variant.From(v);
        if (val is Color c) return Variant.From(c);
        if (val is NodePath np) return Variant.From(np);
        if (val is GodotObject go) return Variant.From(go);

        try
        {
            return Variant.From((dynamic)val);
        }
        catch (Exception ex)
        {
            GD.PrintErr($"[JsonGraphSerializer] Failed to convert {val.GetType()} to Variant: {ex.Message}");
            return new Variant();
        }
    }
}
