using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace OpenMeshWin.Core;

internal static class Program
{
    private const string PipeName = "openmesh-win-core";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };
    private static readonly CoreState State = new();

    private static async Task Main()
    {
        State.InitializeRuntime();
        Console.WriteLine("OpenMeshWin.Core is running.");

        while (true)
        {
            var server = new NamedPipeServerStream(
                PipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous
            );

            try
            {
                await server.WaitForConnectionAsync();
                _ = Task.Run(() => HandleClientAsync(server));
            }
            catch
            {
                server.Dispose();
            }
        }
    }

    private static async Task HandleClientAsync(NamedPipeServerStream server)
    {
        using (server)
        using (var reader = new StreamReader(server, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true))
        using (var writer = new StreamWriter(server, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true) { AutoFlush = true })
        {
            var requestLine = await reader.ReadLineAsync();
            if (string.IsNullOrWhiteSpace(requestLine))
            {
                return;
            }

            CoreRequest? request = null;
            try
            {
                request = JsonSerializer.Deserialize<CoreRequest>(requestLine, JsonOptions);
            }
            catch (JsonException)
            {
                // Invalid JSON will be handled by the default response below.
            }

            var response = State.Handle(request);
            var responseJson = JsonSerializer.Serialize(response, JsonOptions);
            await writer.WriteLineAsync(responseJson);
        }
    }

    private sealed class CoreState
    {
        private readonly object _gate = new();
        private readonly DateTimeOffset _startedAtUtc = DateTimeOffset.UtcNow;
        private bool _vpnRunning;
        private CoreRuntimeLayout _layout = CoreRuntimeLayout.Empty;
        private string _selectedProfilePath = string.Empty;
        private string _effectiveConfigPath = string.Empty;
        private string _lastConfigHash = string.Empty;
        private int _injectedRuleCount;
        private DateTimeOffset? _lastReloadAtUtc;
        private string _lastReloadError = string.Empty;

        public void InitializeRuntime()
        {
            lock (_gate)
            {
                _layout = CoreRuntimeLayout.Initialize();
                EnsureSampleFiles(_layout);
                _selectedProfilePath = _layout.DefaultProfilePath;
                _effectiveConfigPath = _layout.EffectiveConfigPath;
            }
        }

        public CoreResponse Handle(CoreRequest? request)
        {
            lock (_gate)
            {
                var action = request?.Action?.Trim().ToLowerInvariant() ?? string.Empty;
                try
                {
                    return action switch
                    {
                        "ping" => BuildResponse(ok: true, message: "pong"),
                        "status" => BuildResponse(ok: true, message: "status"),
                        "reload" => ReloadConfig(),
                        "set_profile" => SetProfile(request?.ProfilePath ?? string.Empty),
                        "start_vpn" => StartVpn(),
                        "stop_vpn" => StopVpn(),
                        _ => BuildResponse(ok: false, message: "unknown action")
                    };
                }
                catch (Exception ex)
                {
                    _lastReloadError = ex.Message;
                    return BuildResponse(ok: false, message: ex.Message);
                }
            }
        }

        private CoreResponse SetProfile(string profilePath)
        {
            if (string.IsNullOrWhiteSpace(profilePath))
            {
                return BuildResponse(ok: false, message: "profile path is empty");
            }

            var resolvedPath = ResolveProfilePath(profilePath);
            if (!File.Exists(resolvedPath))
            {
                return BuildResponse(ok: false, message: $"profile not found: {resolvedPath}");
            }

            _selectedProfilePath = resolvedPath;
            var reload = ReloadConfig();
            if (!reload.Ok)
            {
                return reload;
            }

            return BuildResponse(ok: true, message: $"profile set: {_selectedProfilePath}");
        }

        private CoreResponse StartVpn()
        {
            if (string.IsNullOrWhiteSpace(_lastConfigHash))
            {
                var reload = ReloadConfig();
                if (!reload.Ok)
                {
                    return BuildResponse(ok: false, message: $"reload failed before start_vpn: {reload.Message}");
                }
            }

            _vpnRunning = true;
            return BuildResponse(ok: true, message: "vpn started");
        }

        private CoreResponse StopVpn()
        {
            _vpnRunning = false;
            return BuildResponse(ok: true, message: "vpn stopped");
        }

        private CoreResponse ReloadConfig()
        {
            var profilePath = string.IsNullOrWhiteSpace(_selectedProfilePath)
                ? _layout.DefaultProfilePath
                : _selectedProfilePath;

            var profileContentRaw = File.ReadAllText(profilePath, Encoding.UTF8);
            var profileContentClean = JsonRelaxed.Normalize(profileContentRaw);
            var configRoot = JsonNode.Parse(profileContentClean) as JsonObject
                ?? throw new InvalidOperationException("profile config is not a JSON object.");

            var routingRulesRaw = File.Exists(_layout.RoutingRulesPath)
                ? File.ReadAllText(_layout.RoutingRulesPath, Encoding.UTF8)
                : "{}";
            var routingRules = DynamicRoutingRules.Parse(routingRulesRaw);

            // Phase 2 keeps raw profile route mode behavior. We only inject dynamic rules.
            var injectedCount = InjectRoutingRules(configRoot, routingRules);

            Directory.CreateDirectory(Path.GetDirectoryName(_layout.EffectiveConfigPath) ?? _layout.RuntimeRoot);
            var effectiveConfig = configRoot.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_layout.EffectiveConfigPath, effectiveConfig, Encoding.UTF8);

            _selectedProfilePath = profilePath;
            _effectiveConfigPath = _layout.EffectiveConfigPath;
            _lastConfigHash = ComputeSha256Hex(effectiveConfig);
            _injectedRuleCount = injectedCount;
            _lastReloadAtUtc = DateTimeOffset.UtcNow;
            _lastReloadError = string.Empty;

            return BuildResponse(ok: true, message: $"config reloaded, injected_rules={injectedCount}");
        }

        private int InjectRoutingRules(JsonObject configRoot, DynamicRoutingRules routingRules)
        {
            var routeObject = configRoot["route"] as JsonObject ?? new JsonObject();
            var routeRules = routeObject["rules"] as JsonArray ?? new JsonArray();

            var sniffIndex = FindSniffRuleIndex(routeRules);
            if (sniffIndex < 0)
            {
                routeRules.Insert(0, new JsonObject { ["action"] = "sniff" });
                sniffIndex = 0;
            }

            var injectedRules = routingRules.ToSingBoxRouteRules("proxy");
            var managedCanonical = injectedRules
                .Select(CanonicalizeRule)
                .ToHashSet(StringComparer.Ordinal);

            for (var i = routeRules.Count - 1; i >= 0; i--)
            {
                if (routeRules[i] is not JsonObject existingRule)
                {
                    continue;
                }

                if (managedCanonical.Contains(CanonicalizeRule(existingRule)))
                {
                    routeRules.RemoveAt(i);
                }
            }

            var insertIndex = Math.Min(sniffIndex + 1, routeRules.Count);
            foreach (var injectedRule in injectedRules)
            {
                routeRules.Insert(insertIndex, DeepClone(injectedRule));
                insertIndex++;
            }

            routeObject["rules"] = routeRules;
            configRoot["route"] = routeObject;
            return injectedRules.Count;
        }

        private static int FindSniffRuleIndex(JsonArray rules)
        {
            for (var i = 0; i < rules.Count; i++)
            {
                if (rules[i] is JsonObject obj &&
                    string.Equals(obj["action"]?.GetValue<string>(), "sniff", StringComparison.OrdinalIgnoreCase))
                {
                    return i;
                }
            }

            return -1;
        }

        private static JsonObject DeepClone(JsonObject source)
        {
            return JsonNode.Parse(source.ToJsonString()) as JsonObject ?? new JsonObject();
        }

        private static string CanonicalizeRule(JsonObject rule)
        {
            var normalized = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            foreach (var kvp in rule)
            {
                if (kvp.Value is null)
                {
                    normalized[kvp.Key] = null;
                    continue;
                }

                if (kvp.Value is JsonArray array)
                {
                    var values = array
                        .Select(x => x?.GetValue<string>() ?? string.Empty)
                        .OrderBy(x => x, StringComparer.Ordinal)
                        .ToList();
                    normalized[kvp.Key] = values;
                    continue;
                }

                normalized[kvp.Key] = kvp.Value.ToJsonString();
            }

            return JsonSerializer.Serialize(normalized);
        }

        private string ResolveProfilePath(string profilePath)
        {
            if (Path.IsPathRooted(profilePath))
            {
                return profilePath;
            }

            return Path.GetFullPath(Path.Combine(_layout.RuntimeRoot, profilePath));
        }

        private CoreResponse BuildResponse(bool ok, string message)
        {
            return new CoreResponse
            {
                Ok = ok,
                Message = message,
                CoreRunning = true,
                VpnRunning = _vpnRunning,
                StartedAtUtc = _startedAtUtc.ToString("O"),
                ProfilePath = _selectedProfilePath,
                EffectiveConfigPath = _effectiveConfigPath,
                LastConfigHash = _lastConfigHash,
                InjectedRuleCount = _injectedRuleCount,
                LastReloadAtUtc = _lastReloadAtUtc?.ToString("O") ?? string.Empty,
                LastReloadError = _lastReloadError
            };
        }

        private static string ComputeSha256Hex(string content)
        {
            var bytes = Encoding.UTF8.GetBytes(content);
            var hash = SHA256.HashData(bytes);
            return Convert.ToHexString(hash);
        }

        private static void EnsureSampleFiles(CoreRuntimeLayout layout)
        {
            Directory.CreateDirectory(layout.RuntimeRoot);
            Directory.CreateDirectory(layout.ProfilesRoot);
            Directory.CreateDirectory(layout.EffectiveRoot);

            if (!File.Exists(layout.DefaultProfilePath))
            {
                var sampleProfile = """
                {
                  // phase2 sample profile
                  "outbounds": [
                    { "type": "direct", "tag": "direct" },
                    { "type": "selector", "tag": "proxy", "outbounds": ["node-a", "node-b"], "default": "node-a", },
                    { "type": "shadowsocks", "tag": "node-a", "server": "1.1.1.1", "server_port": 443 },
                    { "type": "shadowsocks", "tag": "node-b", "server": "8.8.8.8", "server_port": 443 }
                  ],
                  "route": {
                    "final": "direct",
                    "rules": [
                      { "action": "sniff" },
                    ],
                  }
                }
                """;
                File.WriteAllText(layout.DefaultProfilePath, sampleProfile, Encoding.UTF8);
            }

            if (!File.Exists(layout.RoutingRulesPath))
            {
                var sampleRules = """
                {
                  "ip_cidr": ["1.1.1.1/32"],
                  "domain": ["chatgpt.com"],
                  "domain_suffix": ["openai.com", ".github.com"]
                }
                """;
                File.WriteAllText(layout.RoutingRulesPath, sampleRules, Encoding.UTF8);
            }
        }
    }

    private sealed class CoreRuntimeLayout
    {
        public static readonly CoreRuntimeLayout Empty = new()
        {
            RuntimeRoot = string.Empty,
            ProfilesRoot = string.Empty,
            EffectiveRoot = string.Empty,
            DefaultProfilePath = string.Empty,
            RoutingRulesPath = string.Empty,
            EffectiveConfigPath = string.Empty
        };

        public string RuntimeRoot { get; init; } = string.Empty;
        public string ProfilesRoot { get; init; } = string.Empty;
        public string EffectiveRoot { get; init; } = string.Empty;
        public string DefaultProfilePath { get; init; } = string.Empty;
        public string RoutingRulesPath { get; init; } = string.Empty;
        public string EffectiveConfigPath { get; init; } = string.Empty;

        public static CoreRuntimeLayout Initialize()
        {
            var runtimeRoot = Path.Combine(AppContext.BaseDirectory, "runtime");
            var profilesRoot = Path.Combine(runtimeRoot, "profiles");
            var effectiveRoot = Path.Combine(runtimeRoot, "effective");

            return new CoreRuntimeLayout
            {
                RuntimeRoot = runtimeRoot,
                ProfilesRoot = profilesRoot,
                EffectiveRoot = effectiveRoot,
                DefaultProfilePath = Path.Combine(profilesRoot, "default_profile.json"),
                RoutingRulesPath = Path.Combine(runtimeRoot, "routing_rules.json"),
                EffectiveConfigPath = Path.Combine(effectiveRoot, "effective_config.json")
            };
        }
    }

    private static class JsonRelaxed
    {
        public static string Normalize(string input)
        {
            var noComments = StripComments(input);
            return StripTrailingCommas(noComments);
        }

        private static string StripComments(string input)
        {
            var chars = input.ToCharArray();
            var sb = new StringBuilder(chars.Length);
            var inString = false;
            var escaped = false;
            var i = 0;

            while (i < chars.Length)
            {
                var c = chars[i];

                if (inString)
                {
                    sb.Append(c);
                    if (escaped)
                    {
                        escaped = false;
                    }
                    else if (c == '\\')
                    {
                        escaped = true;
                    }
                    else if (c == '"')
                    {
                        inString = false;
                    }
                    i++;
                    continue;
                }

                if (c == '"')
                {
                    inString = true;
                    sb.Append(c);
                    i++;
                    continue;
                }

                if (c == '/' && i + 1 < chars.Length)
                {
                    var next = chars[i + 1];
                    if (next == '/')
                    {
                        i += 2;
                        while (i < chars.Length && chars[i] != '\n')
                        {
                            i++;
                        }
                        continue;
                    }

                    if (next == '*')
                    {
                        i += 2;
                        while (i + 1 < chars.Length)
                        {
                            if (chars[i] == '*' && chars[i + 1] == '/')
                            {
                                i += 2;
                                break;
                            }
                            i++;
                        }
                        continue;
                    }
                }

                sb.Append(c);
                i++;
            }

            return sb.ToString();
        }

        private static string StripTrailingCommas(string input)
        {
            var chars = input.ToCharArray();
            var sb = new StringBuilder(chars.Length);
            var inString = false;
            var escaped = false;

            for (var i = 0; i < chars.Length; i++)
            {
                var c = chars[i];
                if (inString)
                {
                    sb.Append(c);
                    if (escaped)
                    {
                        escaped = false;
                    }
                    else if (c == '\\')
                    {
                        escaped = true;
                    }
                    else if (c == '"')
                    {
                        inString = false;
                    }
                    continue;
                }

                if (c == '"')
                {
                    inString = true;
                    sb.Append(c);
                    continue;
                }

                if (c == ',')
                {
                    var j = i + 1;
                    while (j < chars.Length && char.IsWhiteSpace(chars[j]))
                    {
                        j++;
                    }
                    if (j < chars.Length && (chars[j] == ']' || chars[j] == '}'))
                    {
                        continue;
                    }
                }

                sb.Append(c);
            }

            return sb.ToString();
        }
    }

    private sealed class DynamicRoutingRules
    {
        public List<string> IpCidr { get; } = [];
        public List<string> Domain { get; } = [];
        public List<string> DomainSuffix { get; } = [];
        public List<string> DomainRegex { get; } = [];

        public static DynamicRoutingRules Parse(string content)
        {
            var cleaned = JsonRelaxed.Normalize(content);
            var root = JsonNode.Parse(cleaned) as JsonObject ?? new JsonObject();
            if (root["proxy"] is JsonObject proxyObject)
            {
                root = proxyObject;
            }

            var rules = new DynamicRoutingRules();

            if (root["rules"] is JsonArray rulesArray)
            {
                foreach (var item in rulesArray)
                {
                    if (item is not JsonObject ruleObject)
                    {
                        continue;
                    }
                    rules.IpCidr.AddRange(ReadStringArray(ruleObject, "ip_cidr"));
                    rules.Domain.AddRange(ReadStringArray(ruleObject, "domain"));
                    rules.DomainSuffix.AddRange(ReadStringArray(ruleObject, "domain_suffix"));
                    rules.DomainRegex.AddRange(ReadStringArray(ruleObject, "domain_regex"));
                }
            }
            else
            {
                rules.IpCidr.AddRange(ReadStringArray(root, "ip_cidr"));
                rules.Domain.AddRange(ReadStringArray(root, "domain"));
                rules.DomainSuffix.AddRange(ReadStringArray(root, "domain_suffix"));
                rules.DomainRegex.AddRange(ReadStringArray(root, "domain_regex"));
            }

            rules.Normalize();
            return rules;
        }

        public List<JsonObject> ToSingBoxRouteRules(string outboundTag)
        {
            var result = new List<JsonObject>();

            if (IpCidr.Count > 0)
            {
                result.Add(new JsonObject
                {
                    ["ip_cidr"] = ToJsonArray(IpCidr),
                    ["outbound"] = outboundTag
                });
            }

            var normalizedSuffix = DomainSuffix
                .Select(x => x.StartsWith('.') ? x : "." + x)
                .ToList();
            var mainDomainsFromSuffix = DomainSuffix
                .Where(x => !x.StartsWith('.'))
                .ToList();
            var domainCombined = Domain
                .Concat(mainDomainsFromSuffix)
                .Distinct(StringComparer.Ordinal)
                .ToList();

            if (domainCombined.Count > 0)
            {
                result.Add(new JsonObject
                {
                    ["domain"] = ToJsonArray(domainCombined),
                    ["outbound"] = outboundTag
                });
            }

            if (normalizedSuffix.Count > 0)
            {
                result.Add(new JsonObject
                {
                    ["domain_suffix"] = ToJsonArray(normalizedSuffix),
                    ["outbound"] = outboundTag
                });
            }

            if (DomainRegex.Count > 0)
            {
                result.Add(new JsonObject
                {
                    ["domain_regex"] = ToJsonArray(DomainRegex),
                    ["outbound"] = outboundTag
                });
            }

            return result;
        }

        private void Normalize()
        {
            NormalizeList(IpCidr);
            NormalizeList(Domain);
            NormalizeList(DomainSuffix);
            NormalizeList(DomainRegex);
        }

        private static void NormalizeList(List<string> list)
        {
            var set = new HashSet<string>(StringComparer.Ordinal);
            var normalized = new List<string>(list.Count);
            foreach (var item in list)
            {
                var value = (item ?? string.Empty).Trim();
                if (value.Length == 0)
                {
                    continue;
                }
                if (set.Add(value))
                {
                    normalized.Add(value);
                }
            }
            list.Clear();
            list.AddRange(normalized);
        }

        private static List<string> ReadStringArray(JsonObject obj, string key)
        {
            if (obj[key] is JsonArray array)
            {
                return array
                    .Select(x => x?.GetValue<string>() ?? string.Empty)
                    .Where(x => !string.IsNullOrWhiteSpace(x))
                    .ToList();
            }

            if (obj[key] is JsonValue value)
            {
                var text = value.GetValue<string>();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    return [text];
                }
            }

            return [];
        }

        private static JsonArray ToJsonArray(IEnumerable<string> values)
        {
            var array = new JsonArray();
            foreach (var value in values)
            {
                array.Add(value);
            }
            return array;
        }
    }

    private sealed class CoreRequest
    {
        public string Action { get; set; } = string.Empty;
        public string ProfilePath { get; set; } = string.Empty;
    }

    private sealed class CoreResponse
    {
        public bool Ok { get; set; }
        public string Message { get; set; } = string.Empty;
        public bool CoreRunning { get; set; }
        public bool VpnRunning { get; set; }
        public string StartedAtUtc { get; set; } = string.Empty;
        public string ProfilePath { get; set; } = string.Empty;
        public string EffectiveConfigPath { get; set; } = string.Empty;
        public string LastConfigHash { get; set; } = string.Empty;
        public int InjectedRuleCount { get; set; }
        public string LastReloadAtUtc { get; set; } = string.Empty;
        public string LastReloadError { get; set; } = string.Empty;
    }
}
