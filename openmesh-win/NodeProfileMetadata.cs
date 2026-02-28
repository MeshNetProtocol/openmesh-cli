using System.Text.Json;

namespace OpenMeshWin;

internal sealed class NodeProfileMetadata
{
    public Dictionary<string, string> OutboundAddressByTag { get; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, List<string>> GroupOutboundsByTag { get; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, string> GroupDefaultOutboundByTag { get; } = new(StringComparer.OrdinalIgnoreCase);

    public static NodeProfileMetadata TryLoad(string profilePath)
    {
        var meta = new NodeProfileMetadata();
        if (string.IsNullOrWhiteSpace(profilePath) || !File.Exists(profilePath))
        {
            return meta;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(profilePath));
            var root = doc.RootElement;
            var configRoot = TryUnwrapConfig(root);

            if (configRoot.TryGetProperty("outbounds", out var outbounds) && outbounds.ValueKind == JsonValueKind.Array)
            {
                foreach (var ob in outbounds.EnumerateArray())
                {
                    if (ob.ValueKind != JsonValueKind.Object) continue;
                    if (!TryGetString(ob, "tag", out var tag) || string.IsNullOrWhiteSpace(tag)) continue;

                    if (TryGetString(ob, "type", out var type))
                    {
                        var typeNorm = (type ?? string.Empty).Trim().ToLowerInvariant();
                        if (typeNorm == "selector" || typeNorm == "urltest" || typeNorm == "url_test")
                        {
                            var list = new List<string>();
                            if (ob.TryGetProperty("outbounds", out var outs) && outs.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var v in outs.EnumerateArray())
                                {
                                    if (v.ValueKind == JsonValueKind.String)
                                    {
                                        var s = v.GetString();
                                        if (!string.IsNullOrWhiteSpace(s)) list.Add(s);
                                    }
                                }
                            }

                            if (list.Count > 0)
                            {
                                meta.GroupOutboundsByTag[tag] = list;
                            }

                            if (TryGetString(ob, "default", out var def) && !string.IsNullOrWhiteSpace(def))
                            {
                                meta.GroupDefaultOutboundByTag[tag] = def!;
                            }
                            continue;
                        }
                    }

                    var addr = ResolveOutboundAddress(ob);
                    if (!string.IsNullOrWhiteSpace(addr))
                    {
                        meta.OutboundAddressByTag[tag] = addr!;
                    }
                }
            }
        }
        catch
        {
        }

        return meta;
    }

    public string PickPreferredGroupTag()
    {
        if (GroupOutboundsByTag.ContainsKey("proxy")) return "proxy";
        if (GroupOutboundsByTag.ContainsKey("auto")) return "auto";
        foreach (var kv in GroupOutboundsByTag)
        {
            return kv.Key;
        }
        return string.Empty;
    }

    private static JsonElement TryUnwrapConfig(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object) return root;
        if (root.TryGetProperty("config", out var config) && config.ValueKind == JsonValueKind.Object) return config;
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object)
        {
            if (data.TryGetProperty("config", out var cfg2) && cfg2.ValueKind == JsonValueKind.Object) return cfg2;
        }
        if (root.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Object)
        {
            if (result.TryGetProperty("config", out var cfg3) && cfg3.ValueKind == JsonValueKind.Object) return cfg3;
        }
        return root;
    }

    private static bool TryGetString(JsonElement obj, string name, out string? value)
    {
        value = null;
        if (!obj.TryGetProperty(name, out var prop)) return false;
        if (prop.ValueKind != JsonValueKind.String) return false;
        value = prop.GetString();
        return true;
    }

    private static string? ResolveOutboundAddress(JsonElement outbound)
    {
        string? host = null;
        if (TryGetString(outbound, "server", out var s1)) host = s1;
        else if (TryGetString(outbound, "address", out var s2)) host = s2;
        else if (TryGetString(outbound, "host", out var s3)) host = s3;
        else if (TryGetString(outbound, "server_address", out var s4)) host = s4;

        if (string.IsNullOrWhiteSpace(host))
        {
            return null;
        }

        if (outbound.TryGetProperty("server_port", out var port) && port.ValueKind == JsonValueKind.Number && port.TryGetInt32(out var p) && p > 0)
        {
            return $"{host}:{p}";
        }

        return host;
    }
}

