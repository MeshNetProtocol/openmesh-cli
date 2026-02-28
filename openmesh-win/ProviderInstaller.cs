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
/// 2. Downloading remote rule-sets concurrently
/// 3. Patching config to use local rule-set paths
/// 4. Generating bootstrap config if needed
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
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _providersRoot = Path.Combine(localAppData, "OpenMeshWin", "providers");
        _profilesRoot = Path.Combine(localAppData, "OpenMeshWin");
        
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
            var downloadedTags = new HashSet<string>();
            var pendingTags = new HashSet<string>();
            
            if (remoteRuleSets.Count > 0)
            {
                var ruleSetDir = Path.Combine(stagingDir, "rule-set");
                Directory.CreateDirectory(ruleSetDir);
                
                Report(progress, "download_rule_set", $"下载 rule-set（可选）：{remoteRuleSets.Count} 个");
                
                using var semaphore = new SemaphoreSlim(2);
                var tasks = remoteRuleSets.Select(async rs =>
                {
                    await semaphore.WaitAsync();
                    try
                    {
                        var tag = rs.Key;
                        var url = rs.Value;
                        Report(progress, "download_rule_set", $"下载 rule-set：{tag}");
                        
                        using var httpRule = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
                        httpRule.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
                        
                        var data = await httpRule.GetByteArrayAsync(url);
                        if (data.Length > 0)
                        {
                            var targetPath = Path.Combine(ruleSetDir, $"{tag}.srs");
                            await File.WriteAllBytesAsync(targetPath, data);
                            Report(progress, "write_rule_set", $"写入 rule-set：{tag}");
                            lock (downloadedTags) downloadedTags.Add(tag);
                        }
                        else
                        {
                            lock (pendingTags) pendingTags.Add(tag);
                        }
                    }
                    catch (Exception ex)
                    {
                        AppLogger.Log($"install: rule-set {rs.Key} failed: {ex.Message}");
                        lock (pendingTags) pendingTags.Add(rs.Key);
                    }
                    finally
                    {
                        semaphore.Release();
                    }
                });
                
                await Task.WhenAll(tasks);
                
                if (pendingTags.Count > 0)
                {
                    var pendingJoined = string.Join(", ", pendingTags);
                    Report(progress, "download_rule_set", $"部分 rule-set 需要连接后初始化：{pendingJoined}");
                    Report(progress, "write_rule_set", $"部分 rule-set 需要连接后初始化：{pendingJoined}");
                }
            }
            else
            {
                Report(progress, "download_rule_set", "跳过：该供应商未声明 rule-set");
                Report(progress, "write_rule_set", "跳过：该供应商未声明 rule-set");
            }

            var finalRuleSetDir = Path.Combine(providerDir, "rule-set");
            
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

            PatchConfigRuleSetsToLocalPaths(fullConfigNode, finalRuleSetDir, downloadedTags);
            
            var fullConfigJson = fullConfigNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config.json"), fullConfigJson);

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
                pendingTags.ToList(),
                remoteRuleSets // Pass the full map of tags->URLs
            );
            
            InstalledProviderManager.Instance.MapProfileToProvider(installedProfileId, providerId);
            
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

    private void PatchConfigRuleSetsToLocalPaths(JsonNode? root, string absoluteRuleSetDir, HashSet<string> downloadedTags)
    {
        var ruleSets = root?["config"]?["route"]?["rule_set"] as JsonArray 
                       ?? root?["route"]?["rule_set"] as JsonArray;
                       
        if (ruleSets != null)
        {
            for (int i = 0; i < ruleSets.Count; i++)
            {
                var node = ruleSets[i];
                if (node?["type"]?.ToString() == "remote" &&
                    node?["tag"]?.ToString() is string tag &&
                    downloadedTags.Contains(tag))
                {
                    // Replace with absolute path to ensure engine can find it regardless of CWD
                    var path = Path.Combine(absoluteRuleSetDir, $"{tag}.srs").Replace("\\", "/");
                    
                    var newNode = new JsonObject
                    {
                        ["type"] = "local",
                        ["tag"] = tag,
                        ["format"] = "binary",
                        ["path"] = path
                    };
                    ruleSets[i] = newNode;
                }
            }
        }
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
