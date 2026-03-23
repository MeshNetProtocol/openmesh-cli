using System.Text.Json;
using System.Text.Json.Nodes;

namespace OpenMeshWin;

public class ImportInstallContext
{
    public string ProviderId { get; set; } = string.Empty;
    public string ProviderName { get; set; } = string.Empty;
    public string PackageHash { get; set; } = string.Empty;
    public string ConfigContent { get; set; } = string.Empty;
    public bool SelectAfterInstall { get; set; } = true;
    public string? RoutingRulesContent { get; set; }
}

public class InstallProgress
{
    public string Step { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Service responsible for installing providers, aligning logic with macOS MarketService.
/// Handles:
/// 1. Parsing and validating config
/// 2. Preserving remote rule-sets for native sing-box management
/// 3. Injecting native update_interval defaults for remote rule-sets
/// 4. Persisting rule-set URL metadata for diagnostics
/// 5. Writing files atomically
/// 6. Registering profile
/// </summary>
public class ProviderInstaller
{
    private static readonly Lazy<ProviderInstaller> _instance = new(() => new ProviderInstaller());
    public static ProviderInstaller Instance => _instance.Value;

    private readonly string _providersRoot;
    private readonly string _profilesRoot;
    
    public ProviderInstaller()
    {
        _providersRoot = Path.Combine(MeshFluxPaths.LocalAppDataRoot, "providers");
        _profilesRoot = MeshFluxPaths.LocalAppDataRoot;
        
        Directory.CreateDirectory(_providersRoot);
    }

    private (string Id, string Name) ParseMetaFromContent(JsonNode node)
    {
        try 
        {
            string id = node["provider_id"]?.ToString() ?? node["id"]?.ToString() ?? string.Empty;
            string name = node["provider_name"]?.ToString() ?? node["name"]?.ToString() ?? string.Empty;
            return (id, name);
        }
        catch
        {
            return (string.Empty, string.Empty);
        }
    }

    private static void Report(IProgress<InstallProgress> progress, string step, string message)
    {
        try
        {
            AppLogger.Log($"install: {step}: {message}");
        }
        catch
        {
        }

        progress.Report(new InstallProgress { Step = step, Message = message });
    }

    internal async Task<bool> InstallFromMarketOfferAsync(CoreProviderOffer offer, bool selectAfterInstall, IProgress<InstallProgress> progress)
    {
        Report(progress, "fetch_detail", "获取供应商详情...");

        string configContent = string.Empty;
        string? routingRulesContent = null;
        
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");

        try
        {
            string fetchUrl = !string.IsNullOrEmpty(offer.DetailUrl) ? offer.DetailUrl : offer.ConfigUrl;
            
            if (string.IsNullOrEmpty(fetchUrl))
            {
                 throw new Exception("供应商未提供有效的配置 URL");
            }

            Report(progress, "download_config", "下载配置文件...");
            var response = await DownloadStringWithRetryAsync(http, fetchUrl);
            
            JsonNode? rootNode = null;
            try { rootNode = JsonNode.Parse(response); } catch { }

            if (rootNode != null)
            {
                if (rootNode["ok"] != null && rootNode["ok"]!.GetValueKind() == JsonValueKind.False)
                {
                    var err = rootNode["error"]?.ToString();
                    var code = rootNode["error_code"]?.ToString();
                    throw new Exception(string.IsNullOrWhiteSpace(code) ? (err ?? "供应商详情返回错误") : $"{code}: {err}");
                }

                var packageFiles =
                    rootNode["package_files"] as JsonArray
                    ?? rootNode["package"]?["files"] as JsonArray
                    ?? rootNode["data"]?["package"]?["files"] as JsonArray
                    ?? rootNode["result"]?["package"]?["files"] as JsonArray;
                if (packageFiles != null)
                {
                    string realConfigUrl = string.Empty;
                    string? rulesUrl = null;

                    foreach (var file in packageFiles)
                    {
                        var type = file?["type"]?.ToString();
                        var url = file?["url"]?.ToString();
                        
                        if (type == "config") realConfigUrl = url ?? "";
                        else if (type == "force_proxy") rulesUrl = url;
                    }

                    if (!string.IsNullOrEmpty(realConfigUrl))
                    {
                        Report(progress, "download_config", "下载实际配置...");
                        configContent = await DownloadStringWithRetryAsync(http, realConfigUrl);
                    }
                    else
                    {
                        if (!string.IsNullOrEmpty(offer.ConfigUrl) && offer.ConfigUrl != fetchUrl)
                        {
                            configContent = await DownloadStringWithRetryAsync(http, offer.ConfigUrl);
                        }
                    }

                    if (!string.IsNullOrEmpty(rulesUrl))
                    {
                        Report(progress, "download_routing_rules", "下载 routing_rules.json（可选）...");
                        routingRulesContent = await DownloadStringWithRetryAsync(http, rulesUrl);
                        Report(progress, "write_routing_rules", "写入 routing_rules.json（可选）...");
                    }
                    else
                    {
                        Report(progress, "download_routing_rules", "跳过：该供应商未提供 routing_rules.json");
                        Report(progress, "write_routing_rules", "跳过：该供应商未提供 routing_rules.json");
                    }
                }
                else
                {
                    configContent = response;
                    Report(progress, "download_routing_rules", "跳过：非详情模式");
                    Report(progress, "write_routing_rules", "跳过：非详情模式");
                }
            }
            else
            {
                configContent = response;
            }

            if (string.IsNullOrWhiteSpace(configContent))
            {
                throw new Exception("无法获取有效的配置内容");
            }

            try
            {
                var probe = JsonNode.Parse(configContent);
                if (probe is JsonObject obj)
                {
                    var looksLikeDetail = obj.ContainsKey("provider") || obj.ContainsKey("package") || obj.ContainsKey("package_files");
                    var looksLikeConfig = obj.ContainsKey("outbounds") || obj.ContainsKey("inbounds") || obj.ContainsKey("route") || obj.ContainsKey("dns") || obj.ContainsKey("log");
                    if (looksLikeDetail && !looksLikeConfig)
                    {
                        throw new Exception("下载到的不是 sing-box 配置（看起来是 provider detail 响应），请检查 URL 选择逻辑");
                    }
                }
            }
            catch (JsonException ex)
            {
                throw new Exception($"配置不是合法 JSON: {ex.Message}");
            }

            var context = new ImportInstallContext
            {
                ProviderId = offer.Id,
                ProviderName = offer.Name,
                PackageHash = offer.PackageHash,
                ConfigContent = configContent,
                RoutingRulesContent = routingRulesContent,
                SelectAfterInstall = selectAfterInstall
            };
            
            return await InstallFromContextAsync(context, progress).ConfigureAwait(false);
        }
        catch
        {
            throw;
        }
    }

    public async Task<bool> InstallFromContextAsync(ImportInstallContext context, IProgress<InstallProgress> progress)
    {
        // Use ID from config if available, otherwise fallback to context or random
        string providerId = string.Empty;
        string providerName = string.Empty;
        
        JsonNode? rootNode = null;
        JsonNode? configRoot = null;
        bool isWrapper = false;
        string? wrapperRoutingRules = null;

        try
        {
            Report(progress, "validate_config", "解析配置文件...");
            rootNode = JsonNode.Parse(context.ConfigContent);
            if (rootNode == null) throw new Exception("配置内容为空");

            if (rootNode["config"] != null)
            {
                configRoot = rootNode["config"];
                isWrapper = true;
            }
            else if (rootNode["data"]?["config"] != null)
            {
                configRoot = rootNode["data"]?["config"];
                isWrapper = true;
                // Move metadata lookup to data level if needed, but usually top level or data level
                // Let's assume metadata is at top level or inside data. 
                // We will search both.
            }
            else if (rootNode["result"]?["config"] != null)
            {
                configRoot = rootNode["result"]?["config"];
                isWrapper = true;
            }
            else
            {
                configRoot = rootNode;
            }

            if (isWrapper)
            {
                var meta = ParseMetaFromContent(rootNode);
                if (!string.IsNullOrWhiteSpace(meta.Id)) providerId = meta.Id;
                if (!string.IsNullOrWhiteSpace(meta.Name)) providerName = meta.Name;

                if (string.IsNullOrWhiteSpace(providerId) && rootNode["data"] is JsonNode dataNode)
                {
                    var dataMeta = ParseMetaFromContent(dataNode);
                    if (!string.IsNullOrWhiteSpace(dataMeta.Id)) providerId = dataMeta.Id;
                    if (!string.IsNullOrWhiteSpace(dataMeta.Name)) providerName = dataMeta.Name;
                }

                var rrNode = rootNode["routing_rules"] ?? rootNode["routing_rules_json"] ?? rootNode["routingRules"];
                if (rrNode != null)
                {
                    if (rrNode.GetValueKind() == JsonValueKind.String)
                    {
                        var innerContent = rrNode.GetValue<string>();
                        try 
                        {
                            var innerNode = JsonNode.Parse(innerContent);
                            wrapperRoutingRules = innerNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
                        }
                        catch 
                        {
                            wrapperRoutingRules = innerContent;
                        }
                    }
                    else
                    {
                        wrapperRoutingRules = rrNode.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
                    }
                }
            }
            else
            {
                var meta = ParseMetaFromContent(configRoot!);
                if (!string.IsNullOrWhiteSpace(meta.Id)) providerId = meta.Id;
                if (!string.IsNullOrWhiteSpace(meta.Name)) providerName = meta.Name;
            }
        }
        catch (Exception ex)
        {
            Report(progress, "validate_config", $"解析失败：{ex.Message}");
            throw;
        }

        if (string.IsNullOrWhiteSpace(providerId)) providerId = context.ProviderId;
        
        if (string.IsNullOrWhiteSpace(providerName)) providerName = context.ProviderName;
        
        if (string.IsNullOrWhiteSpace(providerId))
             providerId = $"imported-{Guid.NewGuid().ToString().ToLower()}";
             
        if (string.IsNullOrWhiteSpace(providerName))
             providerName = "导入供应商";

        Report(progress, "fetch_detail", $"开始安装：{providerName} ({providerId})");

        AppLogger.Log($"install: provider={providerId} name={providerName} begin");

        // 1. Prepare Staging Directory
        var stagingDir = Path.Combine(_providersRoot, ".staging", $"{providerId}-{Guid.NewGuid()}");
        var providerDir = Path.Combine(_providersRoot, providerId);
        Directory.CreateDirectory(stagingDir);

        try
        {
            if (configRoot == null) throw new Exception("无法提取有效配置内容");

            string? finalRoutingRules = wrapperRoutingRules;
            if (string.IsNullOrWhiteSpace(finalRoutingRules)) finalRoutingRules = context.RoutingRulesContent;
            
            if (!string.IsNullOrWhiteSpace(finalRoutingRules))
            {
                Report(progress, "write_routing_rules", "写入 routing_rules.json（可选）...");
                await File.WriteAllTextAsync(Path.Combine(stagingDir, "routing_rules.json"), finalRoutingRules);
            }
            else
            {
                if (configRoot["routing_rules"] is JsonObject routingRules)
                {
                     Report(progress, "write_routing_rules", "提取并写入 routing_rules.json（可选）...");
                     await File.WriteAllTextAsync(Path.Combine(stagingDir, "routing_rules.json"), routingRules.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                }
                else
                {
                     Report(progress, "write_routing_rules", "跳过：配置中无 routing_rules");
                }
            }

            var remoteRuleSets = ExtractRemoteRuleSets(configRoot);
            if (remoteRuleSets.Count > 0)
            {
                Report(progress, "download_rule_set", $"跳过预下载：已启用 sing-box 原生远程更新机制 ({remoteRuleSets.Count} 个规则)");
                Report(progress, "write_rule_set", "跳过：不写入本地 .srs，由 sing-box 自身管理");
            }
            else
            {
                Report(progress, "download_rule_set", "跳过：配置未包含 remote rule-set");
                Report(progress, "write_rule_set", "跳过：无 rule-set 需要写入");
            }
            AppLogger.Log($"install: provider={providerId} rule_set_remote_count={remoteRuleSets.Count}");
            
            Report(progress, "write_config", "写入 config.json...");
            
            var fullConfigNode = JsonNode.Parse(configRoot!.ToJsonString());

            if (fullConfigNode is JsonObject configObj)
            {
                var keysToRemove = new[]
                {
                    "ok", "status", "message", "msg",
                    "error", "error_code", "details",
                    "provider_id", "provider_name", "package_hash", "package_files",
                    "provider", "package",
                    "detail_url", "config_url", "routing_rules", "routing_rules_json", "routingRules"
                };

                foreach (var key in keysToRemove)
                {
                    configObj.Remove(key);
                }
            }

            var optimizedCount = OptimizeRemoteRuleSetsForNative(fullConfigNode);
            AppLogger.Log($"install: provider={providerId} rule_set_native_optimize_count={optimizedCount}");
            
            var fullConfigJson = fullConfigNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config.json"), fullConfigJson);
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config_full.json"), fullConfigJson);

            var backupRoot = Path.Combine(_providersRoot, ".backup");
            Directory.CreateDirectory(backupRoot);
            var backupDir = Path.Combine(backupRoot, $"{providerId}-{Guid.NewGuid()}");

            try
            {
                if (Directory.Exists(providerDir))
                {
                    Directory.Move(providerDir, backupDir);
                }

                Directory.Move(stagingDir, providerDir);

                if (Directory.Exists(backupDir))
                {
                    try { Directory.Delete(backupDir, true); } catch { }
                }
            }
            catch
            {
                if (Directory.Exists(providerDir))
                {
                    try { Directory.Delete(providerDir, true); } catch { }
                }

                if (Directory.Exists(backupDir))
                {
                    Directory.Move(backupDir, providerDir);
                }

                throw;
            }

            Report(progress, "register_profile", "注册到供应商列表...");
            
            var configPath = Path.Combine(providerDir, "config.json");
            
            // Check if profile exists for this provider (via InstalledProviderManager mapping)
            // We need a way to look up profile ID by provider ID.
            // Currently InstalledProviderManager maps ProfileID -> ProviderID.
            // We need reverse lookup or iterate.
            
            var existingProfileId = await GetProfileIdByProviderIdAsync(providerId).ConfigureAwait(false);
            long installedProfileId;

            if (existingProfileId.HasValue)
            {
                var existing = await ProfileManager.Instance.GetAsync(existingProfileId.Value);
                if (existing != null)
                {
                    existing.Name = providerName;
                    existing.Path = configPath;
                    existing.LastUpdated = DateTime.Now;
                    await ProfileManager.Instance.UpdateAsync(existing);
                    installedProfileId = existing.Id;
                }
                else
                {
                    // Stale mapping? Create new.
                    var p = new Profile { Name = providerName, Type = ProfileType.Local, Path = configPath, LastUpdated = DateTime.Now };
                    var newP = await ProfileManager.Instance.CreateAsync(p);
                    installedProfileId = newP.Id;
                }
            }
            else
            {
                var p = new Profile { Name = providerName, Type = ProfileType.Local, Path = configPath, LastUpdated = DateTime.Now };
                var newP = await ProfileManager.Instance.CreateAsync(p);
                installedProfileId = newP.Id;
            }

            InstalledProviderManager.Instance.RegisterInstalledProvider(
                providerId, 
                context.PackageHash, 
                new List<string>(),
                remoteRuleSets // Pass the full map of tags->URLs
            );
            
            InstalledProviderManager.Instance.MapProfileToProvider(installedProfileId, providerId);
            AppLogger.Log($"install: provider={providerId} profile_id={installedProfileId} register_done");
            AppLogger.Log($"install: provider={providerId} completed");
            
            Report(progress, "finalize", "完成");
            return true;
        }
        catch (Exception ex)
        {
            AppLogger.Log($"install failed: {ex.Message}");
            try { Directory.Delete(stagingDir, true); } catch { }
            throw;
        }
    }

    private Dictionary<string, string> ExtractRemoteRuleSets(JsonNode? root)
    {
        var result = new Dictionary<string, string>();
        
        // Check "route" -> "rule_set"
        if (root?["config"]?["route"]?["rule_set"] is JsonArray ruleSetsConfig)
        {
            ExtractFromRuleSetsArray(ruleSetsConfig, result);
        }
        else if (root?["route"]?["rule_set"] is JsonArray ruleSetsRoot)
        {
            ExtractFromRuleSetsArray(ruleSetsRoot, result);
        }

        return result;
    }
    
    private void ExtractFromRuleSetsArray(JsonArray ruleSets, Dictionary<string, string> result)
    {
        foreach (var node in ruleSets)
        {
            if (node?["type"]?.ToString() == "remote" &&
                node?["tag"]?.ToString() is string tag &&
                node?["url"]?.ToString() is string url)
            {
                result[tag] = url;
            }
        }
    }

    private static int OptimizeRemoteRuleSetsForNative(JsonNode? root)
    {
        var ruleSets = root?["config"]?["route"]?["rule_set"] as JsonArray
                       ?? root?["route"]?["rule_set"] as JsonArray;
        if (ruleSets == null)
        {
            return 0;
        }

        var updatedCount = 0;
        for (int i = 0; i < ruleSets.Count; i++)
        {
            if (ruleSets[i] is not JsonObject node)
            {
                continue;
            }

            if (!string.Equals(node["type"]?.ToString(), "remote", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (node["update_interval"] == null || string.IsNullOrWhiteSpace(node["update_interval"]!.ToString()))
            {
                node["update_interval"] = "24h";
                updatedCount++;
            }

            if (node["download_interval"] != null)
            {
                node.Remove("download_interval");
                updatedCount++;
            }
        }

        return updatedCount;
    }

    private async Task<long?> GetProfileIdByProviderIdAsync(string providerId)
    {
        var profiles = await ProfileManager.Instance.ListAsync().ConfigureAwait(false);
        foreach (var p in profiles)
        {
            if (InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == providerId)
            {
                return p.Id;
            }
        }
        return null;
    }

    private static async Task<string> DownloadStringWithRetryAsync(HttpClient http, string url)
    {
        Exception? last = null;
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                return await http.GetStringAsync(url).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                last = ex;
                await Task.Delay(TimeSpan.FromMilliseconds(350 * attempt)).ConfigureAwait(false);
            }
        }

        throw last ?? new Exception("下载失败");
    }
}
