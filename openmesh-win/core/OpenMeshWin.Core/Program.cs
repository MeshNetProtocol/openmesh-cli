using System.IO.Pipes;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Globalization;
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
        CoreFileLogger.Log("OpenMeshWin.Core started in legacy/mock mode.");
        Console.WriteLine("OpenMeshWin.Core (legacy/mock) is running.");

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
            catch (Exception ex)
            {
                CoreFileLogger.Log($"Pipe wait failure: {ex.Message}");
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
                CoreFileLogger.Log($"Invalid JSON request: {requestLine}");
            }

            var response = State.Handle(request);
            var responseJson = JsonSerializer.Serialize(response, JsonOptions);
            await writer.WriteLineAsync(responseJson);
        }
    }

    private sealed class CoreState
    {
        private readonly object _gate = new();
        private static readonly HttpClient HttpClient = new();
        private readonly DateTimeOffset _startedAtUtc = DateTimeOffset.UtcNow;
        private bool _vpnRunning;
        private CoreRuntimeLayout _layout = CoreRuntimeLayout.Empty;
        private string _selectedProfilePath = string.Empty;
        private string _effectiveConfigPath = string.Empty;
        private string _lastConfigHash = string.Empty;
        private int _injectedRuleCount;
        private DateTimeOffset? _lastReloadAtUtc;
        private string _lastReloadError = string.Empty;
        private JsonObject? _currentConfigRoot;
        private List<OutboundGroupState> _outboundGroups = [];
        private readonly Dictionary<string, string> _selectedOutboundByGroup = new(StringComparer.OrdinalIgnoreCase);
        private readonly List<ConnectionState> _connections = [];
        private DateTimeOffset _lastRuntimeTickUtc = DateTimeOffset.UtcNow;
        private long _totalUploadBytes;
        private long _totalDownloadBytes;
        private long _uploadRateBytesPerSec;
        private long _downloadRateBytesPerSec;
        private int _nextConnectionId = 1;
        private bool _heartbeatGuardTripped;
        private WalletState _wallet = WalletState.Empty;
        private string _lastGeneratedMnemonic = string.Empty;
        private static readonly string[] SampleProcesses =
        [
            "chrome.exe",
            "msedge.exe",
            "openmesh-agent.exe",
            "powershell.exe",
            "code.exe",
            "discord.exe"
        ];
        private static readonly string[] SampleDestinations =
        [
            "api.openai.com:443",
            "github.com:443",
            "cloudflare-dns.com:443",
            "chat.openai.com:443",
            "market.openmesh.network:443",
            "8.8.8.8:53"
        ];
        private static readonly string[] SampleProtocols = ["tcp", "udp"];
        private static readonly string[] MnemonicWords =
        [
            "apple", "binary", "cactus", "delta", "ember", "fluent", "globe", "harbor",
            "input", "jungle", "kernel", "lunar", "matrix", "nebula", "orbit", "pixel",
            "quantum", "rocket", "signal", "tensor", "uplink", "vector", "window", "xenon",
            "yellow", "zenith", "anchor", "beacon", "cipher", "drift", "engine", "fusion",
            "galaxy", "helium", "island", "jacket", "kitten", "legend", "memory", "native",
            "object", "plasma", "radar", "stream", "tunnel", "update", "vortex", "wallet"
        ];

        public void InitializeRuntime()
        {
            lock (_gate)
            {
                _layout = CoreRuntimeLayout.Initialize();
                EnsureSampleFiles(_layout);
                CoreFileLogger.Initialize(_layout.RuntimeRoot);
                _selectedProfilePath = _layout.DefaultProfilePath;
                _effectiveConfigPath = _layout.EffectiveConfigPath;
                LoadWalletFromDisk();
                CoreFileLogger.Log("Runtime initialized.");
            }
        }

        public CoreResponse Handle(CoreRequest? request)
        {
            lock (_gate)
            {
                var action = request?.Action?.Trim().ToLowerInvariant() ?? string.Empty;
                TickRuntimeState();
                try
                {
                    return action switch
                    {
                        "ping" => BuildResponse(ok: true, message: "pong (legacy/mock core)"),
                        "status" => BuildResponse(ok: true, message: "status (legacy/mock core)"),
                        "groups" => BuildResponse(ok: true, message: "groups"),
                        "connections" => QueryConnections(
                            request?.Search ?? string.Empty,
                            request?.SortBy ?? string.Empty,
                            request?.Descending ?? true),
                        "close_connection" => CloseConnection(request?.ConnectionId ?? 0),
                        "wallet_generate_mnemonic" => GenerateMnemonic(),
                        "wallet_create" => CreateWallet(request?.Mnemonic ?? string.Empty, request?.Password ?? string.Empty),
                        "wallet_unlock" => UnlockWallet(request?.Password ?? string.Empty),
                        "wallet_balance" => GetWalletBalance(request?.Network ?? string.Empty, request?.TokenSymbol ?? string.Empty),
                        "x402_pay" => MakeX402Payment(
                            request?.To ?? string.Empty,
                            request?.Resource ?? string.Empty,
                            request?.Amount ?? string.Empty,
                            request?.Password ?? string.Empty),
                        "reload" => ReloadConfig(),
                        "set_profile" => SetProfile(request?.ProfilePath ?? string.Empty),
                        "urltest" => UrlTest(request?.Group ?? string.Empty),
                        "select_outbound" => SelectOutbound(request?.Group ?? string.Empty, request?.Outbound ?? string.Empty),
                        "start_vpn" => StartVpn(),
                        "stop_vpn" => StopVpn(),
                        _ => BuildResponse(ok: false, message: "unknown action")
                    };
                }
                catch (Exception ex)
                {
                    _lastReloadError = ex.Message;
                    CoreFileLogger.Log($"Action '{action}' failed: {ex}");
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
            _heartbeatGuardTripped = false;
            EnsureConnectionPool(minimumConnections: 4);
            CoreFileLogger.Log("VPN started.");
            return BuildResponse(ok: true, message: "vpn started");
        }

        private CoreResponse StopVpn()
        {
            _vpnRunning = false;
            _uploadRateBytesPerSec = 0;
            _downloadRateBytesPerSec = 0;
            foreach (var connection in _connections)
            {
                connection.State = "idle";
            }
            CoreFileLogger.Log("VPN stopped.");
            return BuildResponse(ok: true, message: "vpn stopped");
        }

        private CoreResponse UrlTest(string requestedGroup)
        {
            if (_outboundGroups.Count == 0)
            {
                return BuildResponse(ok: false, message: "no outbound groups available");
            }

            OutboundGroupState? group = null;
            if (!string.IsNullOrWhiteSpace(requestedGroup))
            {
                group = _outboundGroups.FirstOrDefault(g =>
                    string.Equals(g.Tag, requestedGroup, StringComparison.OrdinalIgnoreCase));
            }

            group ??= PickPreferredGroup();
            if (group is null)
            {
                return BuildResponse(ok: false, message: "no group selected");
            }

            var delays = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (var item in group.Items)
            {
                var delay = GenerateDelayMs(group.Tag, item.Tag);
                item.UrlTestDelay = delay;
                delays[item.Tag] = delay;
            }

            var response = BuildResponse(ok: true, message: "urltest completed");
            response.Group = group.Tag;
            response.Delays = delays;
            return response;
        }

        private CoreResponse SelectOutbound(string groupTag, string outboundTag)
        {
            if (!ValidateTag(groupTag) || !ValidateTag(outboundTag))
            {
                return BuildResponse(ok: false, message: "invalid group/outbound tag");
            }

            var group = _outboundGroups.FirstOrDefault(g =>
                string.Equals(g.Tag, groupTag, StringComparison.OrdinalIgnoreCase));
            if (group is null)
            {
                return BuildResponse(ok: false, message: $"group not found: {groupTag}");
            }

            var hasOutbound = group.Items.Any(i =>
                string.Equals(i.Tag, outboundTag, StringComparison.OrdinalIgnoreCase));
            if (!hasOutbound)
            {
                return BuildResponse(ok: false, message: $"outbound not in group: {outboundTag}");
            }

            var previousSelected = group.Selected;
            group.Selected = outboundTag;
            _selectedOutboundByGroup[group.Tag] = outboundTag;
            foreach (var connection in _connections)
            {
                if (string.Equals(connection.Outbound, previousSelected, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(connection.Outbound, group.Tag, StringComparison.OrdinalIgnoreCase))
                {
                    connection.Outbound = outboundTag;
                }
            }

            if (_currentConfigRoot is not null)
            {
                ApplyPreferredSelectionToConfig(_currentConfigRoot, _selectedOutboundByGroup);
                PersistEffectiveConfig(_currentConfigRoot);
            }

            return BuildResponse(ok: true, message: $"selected {outboundTag} in {group.Tag}");
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

            // SmartRouting V2: Handle rule-sets
            var availableRuleSets = ProcessRuleSets(configRoot);
            FilterRules(configRoot, availableRuleSets);

            // macOS Alignment: Inject fake node for single-node groups to fix UI/selection behavior
            InjectFakeNodeForSingleNodeGroups(configRoot);

            // Phase 2 keeps raw profile route mode behavior.
            // We NO LONGER inject dynamic rules from routing_rules.json.
            
            var groups = BuildOutboundGroups(configRoot);
            ApplyPreferredSelectionToConfig(configRoot, _selectedOutboundByGroup);

            foreach (var group in groups)
            {
                if (_selectedOutboundByGroup.TryGetValue(group.Tag, out var preferred) &&
                    group.Items.Any(i => string.Equals(i.Tag, preferred, StringComparison.OrdinalIgnoreCase)))
                {
                    group.Selected = preferred;
                }
            }

            PersistEffectiveConfig(configRoot);

            _selectedProfilePath = profilePath;
            _effectiveConfigPath = _layout.EffectiveConfigPath;
            _injectedRuleCount = 0; // Legacy counter
            _lastReloadAtUtc = DateTimeOffset.UtcNow;
            _lastReloadError = string.Empty;
            _currentConfigRoot = configRoot;
            _outboundGroups = groups;
            EnsureConnectionPool(minimumConnections: 3);
            CoreFileLogger.Log($"Config reloaded. rule_sets={availableRuleSets.Count}");

            return BuildResponse(ok: true, message: $"config reloaded, rule_sets={availableRuleSets.Count}");
        }

        private HashSet<string> ProcessRuleSets(JsonObject configRoot)
        {
            var availableRuleSets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (configRoot["route"] is not JsonObject route)
            {
                return availableRuleSets;
            }

            if (route["rule_set"] is not JsonArray ruleSets)
            {
                return availableRuleSets;
            }

            var missingRuleSets = new List<(string Tag, string Url)>();
            var ruleSetsToRemove = new List<int>();

            for (var i = 0; i < ruleSets.Count; i++)
            {
                if (ruleSets[i] is not JsonObject ruleSet) continue;

                var type = ruleSet["type"]?.GetValue<string>() ?? string.Empty;
                var tag = ruleSet["tag"]?.GetValue<string>() ?? string.Empty;

                if (string.IsNullOrWhiteSpace(tag)) continue;

                if (string.Equals(type, "remote", StringComparison.OrdinalIgnoreCase))
                {
                    var url = ruleSet["url"]?.GetValue<string>() ?? string.Empty;
                    var localPath = Path.Combine(_layout.RuleSetsRoot, $"{tag}.srs");

                    if (File.Exists(localPath))
                    {
                        ruleSet["type"] = "local";
                        ruleSet["format"] = "binary";
                        ruleSet["path"] = localPath;
                        ruleSet.Remove("url");
                        ruleSet.Remove("download_detour");
                        ruleSet.Remove("update_interval");
                        availableRuleSets.Add(tag);
                    }
                    else
                    {
                        if (!string.IsNullOrWhiteSpace(url))
                        {
                            missingRuleSets.Add((tag, url));
                        }
                        ruleSetsToRemove.Add(i);
                    }
                }
                else
                {
                    availableRuleSets.Add(tag);
                }
            }

            for (var i = ruleSetsToRemove.Count - 1; i >= 0; i--)
            {
                ruleSets.RemoveAt(ruleSetsToRemove[i]);
            }

            if (ruleSets.Count == 0)
            {
                route.Remove("rule_set");
            }

            if (missingRuleSets.Count > 0)
            {
                _ = Task.Run(() => DownloadRuleSetsAsync(missingRuleSets));
            }

            return availableRuleSets;
        }

        private async Task DownloadRuleSetsAsync(List<(string Tag, string Url)> items)
        {
            CoreFileLogger.Log($"Starting background download of {items.Count} rule-sets.");
            foreach (var (tag, url) in items)
            {
                try
                {
                    var data = await HttpClient.GetByteArrayAsync(url);
                    var localPath = Path.Combine(_layout.RuleSetsRoot, $"{tag}.srs");
                    var tempPath = localPath + ".tmp";
                    await File.WriteAllBytesAsync(tempPath, data);
                    File.Move(tempPath, localPath, overwrite: true);
                    CoreFileLogger.Log($"Downloaded rule-set: {tag}");
                }
                catch (Exception ex)
                {
                    CoreFileLogger.Log($"Failed to download rule-set {tag}: {ex.Message}");
                }
            }
            CoreFileLogger.Log("Rule-set download completed.");
        }

        private static void FilterRules(JsonObject configRoot, HashSet<string> availableRuleSets)
        {
            if (configRoot["route"] is not JsonObject route ||
                route["rules"] is not JsonArray rules)
            {
                return;
            }

            for (var i = rules.Count - 1; i >= 0; i--)
            {
                if (rules[i] is not JsonObject rule) continue;

                if (rule.TryGetPropertyValue("rule_set", out var ruleSetNode))
                {
                    if (ruleSetNode is JsonArray ruleSetRefs)
                    {
                        var validRefs = new JsonArray();
                        foreach (var refNode in ruleSetRefs)
                        {
                            var tag = refNode?.GetValue<string>();
                            if (!string.IsNullOrEmpty(tag) && availableRuleSets.Contains(tag))
                            {
                                validRefs.Add(tag);
                            }
                        }

                        if (validRefs.Count == 0)
                        {
                            rules.RemoveAt(i);
                            continue;
                        }

                        if (validRefs.Count < ruleSetRefs.Count)
                        {
                            rule["rule_set"] = validRefs;
                        }
                    }
                    else if (ruleSetNode is JsonValue singleRef)
                    {
                        var tag = singleRef.GetValue<string>();
                        if (!string.IsNullOrEmpty(tag) && !availableRuleSets.Contains(tag))
                        {
                            rules.RemoveAt(i);
                        }
                    }
                }
            }
        }

        private static void InjectFakeNodeForSingleNodeGroups(JsonObject configRoot)
        {
            if (configRoot["outbounds"] is not JsonArray outbounds)
            {
                return;
            }

            var needsFakeNode = false;
            foreach (var node in outbounds)
            {
                if (node is not JsonObject outbound) continue;

                var type = outbound["type"]?.GetValue<string>()?.ToLowerInvariant() ?? string.Empty;
                if (type != "selector" && type != "urltest") continue;

                var tag = outbound["tag"]?.GetValue<string>() ?? string.Empty;

                if (outbound["outbounds"] is JsonArray subOutbounds && subOutbounds.Count == 1)
                {
                    // Check if fake node already exists
                    var hasFakeNode = false;
                    foreach (var sub in subOutbounds)
                    {
                        if (string.Equals(sub?.GetValue<string>(), "fake-node-for-testing", StringComparison.OrdinalIgnoreCase))
                        {
                            hasFakeNode = true;
                            break;
                        }
                    }

                    if (!hasFakeNode)
                    {
                        subOutbounds.Add("fake-node-for-testing");
                        needsFakeNode = true;
                        CoreFileLogger.Log($"Injected fake node into group '{tag}'");
                    }
                }
            }

            if (needsFakeNode)
            {
                // Check if fake node definition already exists
                var hasFakeNodeDef = false;
                foreach (var node in outbounds)
                {
                    if (node is JsonObject outbound && 
                        string.Equals(outbound["tag"]?.GetValue<string>(), "fake-node-for-testing", StringComparison.OrdinalIgnoreCase))
                    {
                        hasFakeNodeDef = true;
                        break;
                    }
                }

                if (!hasFakeNodeDef)
                {
                    CoreFileLogger.Log("Added 'fake-node-for-testing' outbound to config");
                    var fakeNode = new JsonObject
                    {
                        ["type"] = "shadowsocks",
                        ["tag"] = "fake-node-for-testing",
                        ["server"] = "127.0.0.1",
                        ["server_port"] = 65535,
                        ["password"] = "fake",
                        ["method"] = "aes-128-gcm"
                    };
                    outbounds.Add(fakeNode);
                }
            }
        }

        private List<OutboundGroupState> BuildOutboundGroups(JsonObject configRoot)
        {
            var groups = new List<OutboundGroupState>();
            if (configRoot["outbounds"] is not JsonArray outboundsArray)
            {
                return groups;
            }

            var outboundTypeByTag = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var node in outboundsArray)
            {
                if (node is not JsonObject outbound)
                {
                    continue;
                }

                var tag = outbound["tag"]?.GetValue<string>() ?? string.Empty;
                var type = outbound["type"]?.GetValue<string>() ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(tag))
                {
                    outboundTypeByTag[tag] = type;
                }
            }

            foreach (var node in outboundsArray)
            {
                if (node is not JsonObject outbound)
                {
                    continue;
                }

                var type = outbound["type"]?.GetValue<string>() ?? string.Empty;
                if (!string.Equals(type, "selector", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(type, "urltest", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var groupTag = outbound["tag"]?.GetValue<string>() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(groupTag))
                {
                    continue;
                }

                var items = new List<OutboundGroupItemState>();
                if (outbound["outbounds"] is JsonArray itemTags)
                {
                    foreach (var itemNode in itemTags)
                    {
                        var itemTag = itemNode?.GetValue<string>() ?? string.Empty;
                        if (string.IsNullOrWhiteSpace(itemTag))
                        {
                            continue;
                        }

                        outboundTypeByTag.TryGetValue(itemTag, out var itemType);
                        items.Add(new OutboundGroupItemState
                        {
                            Tag = itemTag,
                            Type = itemType ?? "unknown",
                            UrlTestDelay = 0
                        });
                    }
                }

                var selected = outbound["default"]?.GetValue<string>() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(selected) && items.Count > 0)
                {
                    selected = items[0].Tag;
                }

                groups.Add(new OutboundGroupState
                {
                    Tag = groupTag,
                    Type = type,
                    Selected = selected,
                    Selectable = string.Equals(type, "selector", StringComparison.OrdinalIgnoreCase),
                    Items = items
                });
            }

            return groups;
        }

        private static void ApplyPreferredSelectionToConfig(JsonObject configRoot, Dictionary<string, string> selectedByGroup)
        {
            if (selectedByGroup.Count == 0)
            {
                return;
            }

            if (configRoot["outbounds"] is not JsonArray outboundsArray)
            {
                return;
            }

            foreach (var node in outboundsArray)
            {
                if (node is not JsonObject outbound)
                {
                    continue;
                }

                var groupTag = outbound["tag"]?.GetValue<string>() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(groupTag))
                {
                    continue;
                }

                if (!selectedByGroup.TryGetValue(groupTag, out var selectedOutbound))
                {
                    continue;
                }

                if (outbound["outbounds"] is not JsonArray itemTags)
                {
                    continue;
                }

                var hasSelected = itemTags.Any(n =>
                    string.Equals(n?.GetValue<string>() ?? string.Empty, selectedOutbound, StringComparison.OrdinalIgnoreCase));
                if (hasSelected)
                {
                    outbound["default"] = selectedOutbound;
                }
            }
        }

        private void PersistEffectiveConfig(JsonObject configRoot)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_layout.EffectiveConfigPath) ?? _layout.RuntimeRoot);
            var effectiveConfig = configRoot.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_layout.EffectiveConfigPath, effectiveConfig, Encoding.UTF8);
            _lastConfigHash = ComputeSha256Hex(effectiveConfig);
        }

        private OutboundGroupState? PickPreferredGroup()
        {
            foreach (var preferred in new[] { "proxy", "auto" })
            {
                var match = _outboundGroups.FirstOrDefault(g =>
                    string.Equals(g.Tag, preferred, StringComparison.OrdinalIgnoreCase));
                if (match is not null)
                {
                    return match;
                }
            }

            return _outboundGroups.FirstOrDefault();
        }

        private CoreResponse QueryConnections(string search, string sortBy, bool descending)
        {
            var response = BuildResponse(ok: true, message: "connections");
            IEnumerable<ConnectionState> query = _connections;

            if (!string.IsNullOrWhiteSpace(search))
            {
                query = query.Where(connection =>
                    connection.ProcessName.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                    connection.Destination.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                    connection.Outbound.Contains(search, StringComparison.OrdinalIgnoreCase));
            }

            response.Connections = SortConnections(query, sortBy, descending)
                .Select(ToCoreConnection)
                .ToList();
            return response;
        }

        private CoreResponse CloseConnection(int connectionId)
        {
            if (connectionId <= 0)
            {
                return BuildResponse(ok: false, message: "invalid connection id");
            }

            var connection = _connections.FirstOrDefault(x => x.Id == connectionId);
            if (connection is null)
            {
                return BuildResponse(ok: false, message: $"connection not found: {connectionId}");
            }

            _connections.Remove(connection);
            return BuildResponse(ok: true, message: $"connection closed: {connectionId}");
        }

        private void TickRuntimeState()
        {
            var now = DateTimeOffset.UtcNow;
            var elapsed = (now - _lastRuntimeTickUtc).TotalSeconds;
            if (elapsed <= 0.20)
            {
                return;
            }

            _lastRuntimeTickUtc = now;
            EnforceHeartbeatGuard(now);
            EnsureConnectionPool(minimumConnections: _vpnRunning ? 4 : 2);

            if (!_vpnRunning)
            {
                _uploadRateBytesPerSec = 0;
                _downloadRateBytesPerSec = 0;
                foreach (var connection in _connections)
                {
                    connection.State = "idle";
                }
                return;
            }

            var secondSeed = now.ToUnixTimeSeconds();
            var activeCount = Math.Max(1, _connections.Count);
            _uploadRateBytesPerSec = 45_000 + Math.Abs((secondSeed * 7919L).GetHashCode() % 55_000) + activeCount * 4_000L;
            _downloadRateBytesPerSec = 80_000 + Math.Abs((secondSeed * 3571L).GetHashCode() % 120_000) + activeCount * 8_000L;

            var uploadDelta = (long)(_uploadRateBytesPerSec * elapsed);
            var downloadDelta = (long)(_downloadRateBytesPerSec * elapsed);
            _totalUploadBytes += uploadDelta;
            _totalDownloadBytes += downloadDelta;

            var perConnUpload = uploadDelta / activeCount;
            var perConnDownload = downloadDelta / activeCount;
            foreach (var connection in _connections)
            {
                var jitterUpload = (connection.Id * 113 + secondSeed) % 2048;
                var jitterDownload = (connection.Id * 157 + secondSeed) % 4096;
                connection.UploadBytes += perConnUpload + jitterUpload;
                connection.DownloadBytes += perConnDownload + jitterDownload;
                connection.LastSeenUtc = now;
                connection.State = "active";
            }

            if (secondSeed % 22 == 0 && _connections.Count < 8)
            {
                AddSyntheticConnection(now);
            }

            if (secondSeed % 35 == 0 && _connections.Count > 4)
            {
                _connections.RemoveAt(0);
            }
        }

        private void EnforceHeartbeatGuard(DateTimeOffset now)
        {
            if (!_vpnRunning)
            {
                return;
            }

            var heartbeatPath = _layout.AppHeartbeatPath;
            if (!File.Exists(heartbeatPath))
            {
                if ((now - _startedAtUtc).TotalSeconds > 45)
                {
                    ApplyHeartbeatStop("app heartbeat missing");
                }
                return;
            }

            var heartbeatLastWriteUtc = File.GetLastWriteTimeUtc(heartbeatPath);
            var ageSeconds = (now - new DateTimeOffset(heartbeatLastWriteUtc, TimeSpan.Zero)).TotalSeconds;
            if (ageSeconds <= 45)
            {
                return;
            }

            ApplyHeartbeatStop($"app heartbeat stale ({Math.Round(ageSeconds)}s)");
        }

        private void ApplyHeartbeatStop(string reason)
        {
            if (_heartbeatGuardTripped)
            {
                return;
            }

            _heartbeatGuardTripped = true;
            _vpnRunning = false;
            _uploadRateBytesPerSec = 0;
            _downloadRateBytesPerSec = 0;
            foreach (var connection in _connections)
            {
                connection.State = "idle";
            }

            _lastReloadError = $"heartbeat guard: {reason}";
            CoreFileLogger.Log($"Heartbeat guard triggered: {reason}. VPN auto-stopped.");
        }

        private void EnsureConnectionPool(int minimumConnections)
        {
            while (_connections.Count < minimumConnections)
            {
                AddSyntheticConnection(DateTimeOffset.UtcNow);
            }
        }

        private void AddSyntheticConnection(DateTimeOffset now)
        {
            var idx = _nextConnectionId - 1;
            var outbound = PickOutboundForConnection();
            _connections.Add(new ConnectionState
            {
                Id = _nextConnectionId++,
                ProcessName = SampleProcesses[idx % SampleProcesses.Length],
                Destination = SampleDestinations[idx % SampleDestinations.Length],
                Protocol = SampleProtocols[idx % SampleProtocols.Length],
                Outbound = outbound,
                LastSeenUtc = now,
                State = _vpnRunning ? "active" : "idle"
            });
        }

        private string PickOutboundForConnection()
        {
            foreach (var group in _outboundGroups)
            {
                if (!string.IsNullOrWhiteSpace(group.Selected))
                {
                    return group.Selected;
                }
            }

            return "direct";
        }

        private static IEnumerable<ConnectionState> SortConnections(IEnumerable<ConnectionState> source, string sortBy, bool descending)
        {
            var normalized = (sortBy ?? string.Empty).Trim().ToLowerInvariant();
            IOrderedEnumerable<ConnectionState> ordered = normalized switch
            {
                "upload" => source.OrderBy(x => x.UploadBytes),
                "download" => source.OrderBy(x => x.DownloadBytes),
                "process" => source.OrderBy(x => x.ProcessName, StringComparer.OrdinalIgnoreCase),
                "destination" => source.OrderBy(x => x.Destination, StringComparer.OrdinalIgnoreCase),
                "outbound" => source.OrderBy(x => x.Outbound, StringComparer.OrdinalIgnoreCase),
                _ => source.OrderBy(x => x.LastSeenUtc)
            };

            return descending ? ordered.Reverse() : ordered;
        }

        private static CoreConnection ToCoreConnection(ConnectionState state)
        {
            return new CoreConnection
            {
                Id = state.Id,
                ProcessName = state.ProcessName,
                Destination = state.Destination,
                Protocol = state.Protocol,
                Outbound = state.Outbound,
                UploadBytes = state.UploadBytes,
                DownloadBytes = state.DownloadBytes,
                LastSeenUtc = state.LastSeenUtc.ToString("O"),
                State = state.State
            };
        }

        private CoreRuntimeStats BuildRuntimeStats()
        {
            using var process = Process.GetCurrentProcess();
            return new CoreRuntimeStats
            {
                TotalUploadBytes = _totalUploadBytes,
                TotalDownloadBytes = _totalDownloadBytes,
                UploadRateBytesPerSec = _uploadRateBytesPerSec,
                DownloadRateBytesPerSec = _downloadRateBytesPerSec,
                MemoryMb = Math.Round(process.WorkingSet64 / 1024d / 1024d, 2),
                ThreadCount = process.Threads.Count,
                UptimeSeconds = Convert.ToInt64((DateTimeOffset.UtcNow - _startedAtUtc).TotalSeconds),
                ConnectionCount = _connections.Count
            };
        }

        private CoreResponse GenerateMnemonic()
        {
            _lastGeneratedMnemonic = string.Join(" ", Enumerable.Range(0, 12)
                .Select(_ => MnemonicWords[RandomNumberGenerator.GetInt32(MnemonicWords.Length)]));

            var response = BuildResponse(ok: true, message: "mnemonic generated");
            response.GeneratedMnemonic = _lastGeneratedMnemonic;
            return response;
        }

        private CoreResponse CreateWallet(string mnemonic, string password)
        {
            var normalizedMnemonic = NormalizeMnemonic(mnemonic);
            if (string.IsNullOrWhiteSpace(normalizedMnemonic))
            {
                return BuildResponse(ok: false, message: "mnemonic is empty");
            }

            if (!ValidatePassword(password))
            {
                return BuildResponse(ok: false, message: "password must be at least 6 characters");
            }

            var address = DeriveAddress(normalizedMnemonic);
            var encrypted = EncryptSecret(normalizedMnemonic, password);
            var balance = 10m + (Math.Abs(address.GetHashCode()) % 150) / 10m;
            var keystore = new WalletKeystore
            {
                Address = address,
                Network = "base-mainnet",
                TokenSymbol = "USDC",
                SaltBase64 = encrypted.SaltBase64,
                IvBase64 = encrypted.IvBase64,
                CipherBase64 = encrypted.CipherBase64,
                Balance = decimal.Round(balance, 4)
            };

            SaveWalletKeystore(keystore);
            _wallet = WalletState.FromKeystore(keystore);
            _wallet.Unlocked = true;
            _wallet.LastUnlockedAtUtc = DateTimeOffset.UtcNow;

            var response = BuildResponse(ok: true, message: "wallet created");
            response.WalletUnlocked = true;
            response.WalletAddress = address;
            response.WalletBalance = _wallet.Balance;
            CoreFileLogger.Log($"Wallet created: {address}");
            return response;
        }

        private CoreResponse UnlockWallet(string password)
        {
            if (!_wallet.Exists)
            {
                LoadWalletFromDisk();
            }

            if (!_wallet.Exists)
            {
                return BuildResponse(ok: false, message: "wallet not found");
            }

            if (!ValidatePassword(password))
            {
                return BuildResponse(ok: false, message: "invalid password");
            }

            var keystore = ReadWalletKeystore();
            if (keystore is null)
            {
                return BuildResponse(ok: false, message: "wallet keystore is missing");
            }

            try
            {
                var mnemonic = DecryptSecret(
                    keystore.CipherBase64,
                    keystore.SaltBase64,
                    keystore.IvBase64,
                    password);
                var address = DeriveAddress(mnemonic);
                if (!string.Equals(address, keystore.Address, StringComparison.OrdinalIgnoreCase))
                {
                    return BuildResponse(ok: false, message: "wallet integrity check failed");
                }

                _wallet = WalletState.FromKeystore(keystore);
                _wallet.Unlocked = true;
                _wallet.LastUnlockedAtUtc = DateTimeOffset.UtcNow;

                var response = BuildResponse(ok: true, message: "wallet unlocked");
                response.WalletUnlocked = true;
                response.WalletAddress = _wallet.Address;
                response.WalletBalance = _wallet.Balance;
                CoreFileLogger.Log($"Wallet unlocked: {_wallet.Address}");
                return response;
            }
            catch (CryptographicException)
            {
                return BuildResponse(ok: false, message: "password is incorrect");
            }
        }

        private CoreResponse GetWalletBalance(string network, string tokenSymbol)
        {
            if (!_wallet.Exists)
            {
                LoadWalletFromDisk();
            }

            if (!_wallet.Exists)
            {
                return BuildResponse(ok: false, message: "wallet not found");
            }

            if (!string.IsNullOrWhiteSpace(network))
            {
                _wallet.Network = network.Trim();
            }

            if (!string.IsNullOrWhiteSpace(tokenSymbol))
            {
                _wallet.TokenSymbol = tokenSymbol.Trim();
            }

            var response = BuildResponse(ok: true, message: "wallet balance");
            response.WalletAddress = _wallet.Address;
            response.WalletBalance = decimal.Round(_wallet.Balance, 6);
            response.WalletNetwork = _wallet.Network;
            response.WalletToken = _wallet.TokenSymbol;
            return response;
        }

        private CoreResponse MakeX402Payment(string to, string resource, string amountText, string password)
        {
            if (!_wallet.Exists)
            {
                LoadWalletFromDisk();
            }

            if (!_wallet.Exists)
            {
                return BuildResponse(ok: false, message: "wallet not found");
            }

            if (!_wallet.Unlocked)
            {
                var unlock = UnlockWallet(password);
                if (!unlock.Ok)
                {
                    return BuildResponse(ok: false, message: "wallet is locked; unlock failed");
                }
            }

            if (!ValidateTag(to) || !ValidateTag(resource))
            {
                return BuildResponse(ok: false, message: "invalid to/resource");
            }

            if (!decimal.TryParse(amountText, NumberStyles.Number, CultureInfo.InvariantCulture, out var amount))
            {
                return BuildResponse(ok: false, message: "invalid amount");
            }

            amount = decimal.Round(amount, 6);
            if (amount <= 0m)
            {
                return BuildResponse(ok: false, message: "amount must be positive");
            }

            if (amount > _wallet.Balance)
            {
                return BuildResponse(ok: false, message: "insufficient balance");
            }

            _wallet.Balance = decimal.Round(_wallet.Balance - amount, 6);
            PersistWalletBalance();

            var paymentId = $"x402-{Guid.NewGuid():N}"[..17];
            var response = BuildResponse(ok: true, message: $"x402 payment sent: {amount.ToString(CultureInfo.InvariantCulture)} {_wallet.TokenSymbol}");
            response.WalletAddress = _wallet.Address;
            response.WalletBalance = _wallet.Balance;
            response.PaymentId = paymentId;
            CoreFileLogger.Log($"x402 payment: id={paymentId}, amount={amount.ToString(CultureInfo.InvariantCulture)}, balance={_wallet.Balance}");
            return response;
        }

        private void LoadWalletFromDisk()
        {
            var keystore = ReadWalletKeystore();
            if (keystore is null)
            {
                _wallet = WalletState.Empty;
                return;
            }

            _wallet = WalletState.FromKeystore(keystore);
        }

        private WalletKeystore? ReadWalletKeystore()
        {
            if (!File.Exists(_layout.WalletKeystorePath))
            {
                return null;
            }

            var json = File.ReadAllText(_layout.WalletKeystorePath, Encoding.UTF8);
            return JsonSerializer.Deserialize<WalletKeystore>(json, JsonOptions);
        }

        private void SaveWalletKeystore(WalletKeystore keystore)
        {
            Directory.CreateDirectory(_layout.WalletRoot);
            var json = JsonSerializer.Serialize(keystore, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            File.WriteAllText(_layout.WalletKeystorePath, json, Encoding.UTF8);
        }

        private void PersistWalletBalance()
        {
            var keystore = ReadWalletKeystore();
            if (keystore is null)
            {
                return;
            }

            keystore.Balance = _wallet.Balance;
            keystore.Network = _wallet.Network;
            keystore.TokenSymbol = _wallet.TokenSymbol;
            SaveWalletKeystore(keystore);
        }

        private static bool ValidatePassword(string password)
        {
            return !string.IsNullOrWhiteSpace(password) && password.Length >= 6;
        }

        private static string NormalizeMnemonic(string mnemonic)
        {
            var words = (mnemonic ?? string.Empty)
                .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            return string.Join(" ", words);
        }

        private static string DeriveAddress(string mnemonic)
        {
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(mnemonic));
            return "0x" + Convert.ToHexString(hash[..20]).ToLowerInvariant();
        }

        private static (string SaltBase64, string IvBase64, string CipherBase64) EncryptSecret(string plainText, string password)
        {
            var salt = RandomNumberGenerator.GetBytes(16);
            var iv = RandomNumberGenerator.GetBytes(16);
            var key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
            using var aes = Aes.Create();
            aes.Key = key;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            using var encryptor = aes.CreateEncryptor();
            var plainBytes = Encoding.UTF8.GetBytes(plainText);
            var cipherBytes = encryptor.TransformFinalBlock(plainBytes, 0, plainBytes.Length);
            return (Convert.ToBase64String(salt), Convert.ToBase64String(iv), Convert.ToBase64String(cipherBytes));
        }

        private static string DecryptSecret(string cipherBase64, string saltBase64, string ivBase64, string password)
        {
            var salt = Convert.FromBase64String(saltBase64);
            var iv = Convert.FromBase64String(ivBase64);
            var cipherBytes = Convert.FromBase64String(cipherBase64);
            var key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
            using var aes = Aes.Create();
            aes.Key = key;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            using var decryptor = aes.CreateDecryptor();
            var plainBytes = decryptor.TransformFinalBlock(cipherBytes, 0, cipherBytes.Length);
            return Encoding.UTF8.GetString(plainBytes);
        }

        private static bool ValidateTag(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return false;
            }

            if (value.Length > 256)
            {
                return false;
            }

            foreach (var c in value)
            {
                if (char.IsControl(c))
                {
                    return false;
                }
            }

            return true;
        }

        private static int GenerateDelayMs(string groupTag, string itemTag)
        {
            var seed = $"{groupTag}|{itemTag}|{DateTime.UtcNow:yyyyMMddHHmm}";
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(seed));
            var value = BitConverter.ToUInt16(hash, 0);
            return 30 + (value % 220);
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
                LastReloadError = _lastReloadError,
                Group = string.Empty,
                Delays = [],
                OutboundGroups = _outboundGroups.Select(ToCoreOutboundGroup).ToList(),
                Runtime = BuildRuntimeStats(),
                Connections = _connections
                    .OrderByDescending(x => x.LastSeenUtc)
                    .Select(ToCoreConnection)
                    .ToList(),
                WalletExists = _wallet.Exists,
                WalletUnlocked = _wallet.Unlocked,
                WalletAddress = _wallet.Address,
                WalletNetwork = _wallet.Network,
                WalletToken = _wallet.TokenSymbol,
                WalletBalance = decimal.Round(_wallet.Balance, 6),
                GeneratedMnemonic = string.Empty,
                PaymentId = string.Empty
            };
        }

        private static CoreOutboundGroup ToCoreOutboundGroup(OutboundGroupState state)
        {
            return new CoreOutboundGroup
            {
                Tag = state.Tag,
                Type = state.Type,
                Selected = state.Selected,
                Selectable = state.Selectable,
                Items = state.Items.Select(item => new CoreOutboundGroupItem
                {
                    Tag = item.Tag,
                    Type = item.Type,
                    UrlTestDelay = item.UrlTestDelay
                }).ToList()
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
            Directory.CreateDirectory(layout.WalletRoot);
            Directory.CreateDirectory(layout.RuleSetsRoot);

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

    private sealed class OutboundGroupState
    {
        public string Tag { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string Selected { get; set; } = string.Empty;
        public bool Selectable { get; set; }
        public List<OutboundGroupItemState> Items { get; set; } = [];
    }

    private sealed class OutboundGroupItemState
    {
        public string Tag { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public int UrlTestDelay { get; set; }
    }

    private sealed class ConnectionState
    {
        public int Id { get; set; }
        public string ProcessName { get; set; } = string.Empty;
        public string Destination { get; set; } = string.Empty;
        public string Protocol { get; set; } = string.Empty;
        public string Outbound { get; set; } = string.Empty;
        public long UploadBytes { get; set; }
        public long DownloadBytes { get; set; }
        public DateTimeOffset LastSeenUtc { get; set; }
        public string State { get; set; } = string.Empty;
    }

    private sealed class WalletState
    {
        public static readonly WalletState Empty = new()
        {
            Exists = false,
            Unlocked = false,
            Address = string.Empty,
            Network = "base-mainnet",
            TokenSymbol = "USDC",
            Balance = 0m
        };

        public bool Exists { get; set; }
        public bool Unlocked { get; set; }
        public string Address { get; set; } = string.Empty;
        public string Network { get; set; } = "base-mainnet";
        public string TokenSymbol { get; set; } = "USDC";
        public decimal Balance { get; set; }
        public DateTimeOffset? LastUnlockedAtUtc { get; set; }

        public static WalletState FromKeystore(WalletKeystore keystore)
        {
            return new WalletState
            {
                Exists = true,
                Unlocked = false,
                Address = keystore.Address,
                Network = string.IsNullOrWhiteSpace(keystore.Network) ? "base-mainnet" : keystore.Network,
                TokenSymbol = string.IsNullOrWhiteSpace(keystore.TokenSymbol) ? "USDC" : keystore.TokenSymbol,
                Balance = keystore.Balance
            };
        }
    }

    private sealed class WalletKeystore
    {
        public string Address { get; set; } = string.Empty;
        public string Network { get; set; } = "base-mainnet";
        public string TokenSymbol { get; set; } = "USDC";
        public string SaltBase64 { get; set; } = string.Empty;
        public string IvBase64 { get; set; } = string.Empty;
        public string CipherBase64 { get; set; } = string.Empty;
        public decimal Balance { get; set; }
    }

    private sealed class CoreRuntimeLayout
    {
        public static readonly CoreRuntimeLayout Empty = new()
        {
            RuntimeRoot = string.Empty,
            ProfilesRoot = string.Empty,
            EffectiveRoot = string.Empty,
            WalletRoot = string.Empty,
            DefaultProfilePath = string.Empty,
            RoutingRulesPath = string.Empty,
            EffectiveConfigPath = string.Empty,
            WalletKeystorePath = string.Empty,
            AppHeartbeatPath = string.Empty
        };

        public string RuntimeRoot { get; init; } = string.Empty;
        public string ProfilesRoot { get; init; } = string.Empty;
        public string EffectiveRoot { get; init; } = string.Empty;
        public string WalletRoot { get; init; } = string.Empty;
        public string DefaultProfilePath { get; init; } = string.Empty;
        public string RoutingRulesPath { get; init; } = string.Empty;
        public string EffectiveConfigPath { get; init; } = string.Empty;
        public string WalletKeystorePath { get; init; } = string.Empty;
        public string AppHeartbeatPath { get; init; } = string.Empty;
        public string RuleSetsRoot { get; init; } = string.Empty;

        public static CoreRuntimeLayout Initialize()
        {
            var runtimeRoot = Path.Combine(AppContext.BaseDirectory, "runtime");
            var profilesRoot = Path.Combine(runtimeRoot, "profiles");
            var effectiveRoot = Path.Combine(runtimeRoot, "effective");
            var walletRoot = Path.Combine(runtimeRoot, "wallet");
            var ruleSetsRoot = Path.Combine(runtimeRoot, "rulesets");
            var heartbeatPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "OpenMeshWin",
                "app_heartbeat");

            return new CoreRuntimeLayout
            {
                RuntimeRoot = runtimeRoot,
                ProfilesRoot = profilesRoot,
                EffectiveRoot = effectiveRoot,
                WalletRoot = walletRoot,
                RuleSetsRoot = ruleSetsRoot,
                DefaultProfilePath = Path.Combine(profilesRoot, "default_profile.json"),
                RoutingRulesPath = Path.Combine(runtimeRoot, "routing_rules.json"),
                EffectiveConfigPath = Path.Combine(effectiveRoot, "effective_config.json"),
                WalletKeystorePath = Path.Combine(walletRoot, "wallet_keystore.json"),
                AppHeartbeatPath = heartbeatPath
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



    private sealed class CoreRequest
    {
        public string Action { get; set; } = string.Empty;
        public string ProfilePath { get; set; } = string.Empty;
        public string Group { get; set; } = string.Empty;
        public string Outbound { get; set; } = string.Empty;
        public string Search { get; set; } = string.Empty;
        public string SortBy { get; set; } = string.Empty;
        public bool Descending { get; set; }
        public int ConnectionId { get; set; }
        public string Password { get; set; } = string.Empty;
        public string Mnemonic { get; set; } = string.Empty;
        public string Network { get; set; } = string.Empty;
        public string TokenSymbol { get; set; } = string.Empty;
        public string Amount { get; set; } = string.Empty;
        public string To { get; set; } = string.Empty;
        public string Resource { get; set; } = string.Empty;
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
        public string Group { get; set; } = string.Empty;
        public Dictionary<string, int> Delays { get; set; } = [];
        public List<CoreOutboundGroup> OutboundGroups { get; set; } = [];
        public CoreRuntimeStats Runtime { get; set; } = new();
        public List<CoreConnection> Connections { get; set; } = [];
        public bool WalletExists { get; set; }
        public bool WalletUnlocked { get; set; }
        public string WalletAddress { get; set; } = string.Empty;
        public string WalletNetwork { get; set; } = string.Empty;
        public string WalletToken { get; set; } = string.Empty;
        public decimal WalletBalance { get; set; }
        public string GeneratedMnemonic { get; set; } = string.Empty;
        public string PaymentId { get; set; } = string.Empty;
    }

    private sealed class CoreOutboundGroup
    {
        public string Tag { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string Selected { get; set; } = string.Empty;
        public bool Selectable { get; set; }
        public List<CoreOutboundGroupItem> Items { get; set; } = [];
    }

    private sealed class CoreOutboundGroupItem
    {
        public string Tag { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public int UrlTestDelay { get; set; }
    }

    private sealed class CoreRuntimeStats
    {
        public long TotalUploadBytes { get; set; }
        public long TotalDownloadBytes { get; set; }
        public long UploadRateBytesPerSec { get; set; }
        public long DownloadRateBytesPerSec { get; set; }
        public double MemoryMb { get; set; }
        public int ThreadCount { get; set; }
        public long UptimeSeconds { get; set; }
        public int ConnectionCount { get; set; }
    }

    private sealed class CoreConnection
    {
        public int Id { get; set; }
        public string ProcessName { get; set; } = string.Empty;
        public string Destination { get; set; } = string.Empty;
        public string Protocol { get; set; } = string.Empty;
        public string Outbound { get; set; } = string.Empty;
        public long UploadBytes { get; set; }
        public long DownloadBytes { get; set; }
        public string LastSeenUtc { get; set; } = string.Empty;
        public string State { get; set; } = string.Empty;
    }
}
