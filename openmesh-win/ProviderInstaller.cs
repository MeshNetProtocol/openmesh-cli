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
            rootNode = JsonNode.Parse(context.ConfigContent);
            if (rootNode == null) throw new Exception("配置内容为空");

            // Wrapper Detection Logic aligned with macOS
            // Check for keys: config, data.config, result.config
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
                // Not a wrapper, treat as raw config
                configRoot = rootNode;
            }

            // Extract Metadata
            // If wrapper, look at wrapper level first.
            if (isWrapper)
            {
                var meta = ParseMetaFromContent(rootNode);
                if (!string.IsNullOrWhiteSpace(meta.Id)) providerId = meta.Id;
                if (!string.IsNullOrWhiteSpace(meta.Name)) providerName = meta.Name;

                // Also check inside "data" if top level missed
                if (string.IsNullOrWhiteSpace(providerId) && rootNode["data"] is JsonNode dataNode)
                {
                    var dataMeta = ParseMetaFromContent(dataNode);
                    if (!string.IsNullOrWhiteSpace(dataMeta.Id)) providerId = dataMeta.Id;
                    if (!string.IsNullOrWhiteSpace(dataMeta.Name)) providerName = dataMeta.Name;
                }

                // Extract Routing Rules from Wrapper
                // Keys: routing_rules, routing_rules_json, routingRules
                var rrNode = rootNode["routing_rules"] ?? rootNode["routing_rules_json"] ?? rootNode["routingRules"];
                if (rrNode != null)
                {
                    // CRITICAL FIX: macOS logic aligns here.
                    // If rrNode is a JSON Object/Array, we want its raw JSON string representation (e.g. {"version":0...}).
                    // If rrNode is a JSON String (which contains escaped JSON), we want the *inner* string (unescaped).
                    
                    if (rrNode.GetValueKind() == JsonValueKind.String)
                    {
                        // Case 1: The value is a string (e.g. "{\"version\":0...}")
                        // We extract the inner string.
                        var innerContent = rrNode.GetValue<string>();
                        try 
                        {
                            // Try to parse and re-serialize to ensure consistent formatting
                            var innerNode = JsonNode.Parse(innerContent);
                            wrapperRoutingRules = innerNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
                        }
                        catch 
                        {
                            // Fallback if parsing fails, use raw string content
                            wrapperRoutingRules = innerContent;
                        }
                    }
                    else
                    {
                        // Case 2: The value is an object/array (e.g. {"version":0...})
                        // Write it as is (preserving wrapper if present), matching macOS logic.
                        wrapperRoutingRules = rrNode.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
                    }
                }
            }
            else
            {
                // Raw config, try to find metadata inside config
                var meta = ParseMetaFromContent(configRoot!);
                if (!string.IsNullOrWhiteSpace(meta.Id)) providerId = meta.Id;
                if (!string.IsNullOrWhiteSpace(meta.Name)) providerName = meta.Name;
            }
        }
        catch (Exception ex)
        {
             progress.Report(new InstallProgress { Step = "failed", Message = $"JSON 解析失败: {ex.Message}" });
             return false;
        }

        // Fallback: if providerId is still empty, use context
        if (string.IsNullOrWhiteSpace(providerId)) providerId = context.ProviderId;
        
        // Name priority: JSON Metadata > Context (if not generic) > Fallback
        // If context.ProviderName is "导入供应商" (default) or empty, we strictly use JSON name if available.
        // If context.ProviderName is something specific (user typed), we might want to respect it?
        // But for "data" issue, the user didn't type it, it was auto-filled.
        // Since we removed auto-fill in Dialog, context.ProviderName will be empty or user-typed.
        if (string.IsNullOrWhiteSpace(providerName)) providerName = context.ProviderName;
        
        // Final fallbacks
        if (string.IsNullOrWhiteSpace(providerId))
             providerId = $"imported-{Guid.NewGuid().ToString().ToLower()}";
             
        if (string.IsNullOrWhiteSpace(providerName))
             providerName = "导入供应商";

        progress.Report(new InstallProgress { Step = "init", Message = $"开始安装供应商: {providerName} ({providerId})" });

        // 1. Prepare Staging Directory
        var stagingDir = Path.Combine(_providersRoot, ".staging", $"{providerId}-{Guid.NewGuid()}");
        var providerDir = Path.Combine(_providersRoot, providerId);
        Directory.CreateDirectory(stagingDir);

        try
        {
            // 2. Validate Config (using extracted configRoot)
            progress.Report(new InstallProgress { Step = "validate", Message = "校验配置文件..." });
            if (configRoot == null) throw new Exception("无法提取有效配置内容");

            // TODO: Validate Tun Stack Compatibility (optional for now)

            // 3. Write Routing Rules
            // Priority: Wrapper > Context > Config Embedded
            string? finalRoutingRules = wrapperRoutingRules;
            if (string.IsNullOrWhiteSpace(finalRoutingRules)) finalRoutingRules = context.RoutingRulesContent;
            
            if (!string.IsNullOrWhiteSpace(finalRoutingRules))
            {
                progress.Report(new InstallProgress { Step = "write_rules", Message = "写入 routing_rules.json" });
                await File.WriteAllTextAsync(Path.Combine(stagingDir, "routing_rules.json"), finalRoutingRules);
            }
            else
            {
                // Try to extract from config content if embedded (legacy/fallback)
                if (configRoot["routing_rules"] is JsonObject routingRules)
                {
                     progress.Report(new InstallProgress { Step = "write_rules", Message = "提取并写入 routing_rules.json (from config)" });
                     await File.WriteAllTextAsync(Path.Combine(stagingDir, "routing_rules.json"), routingRules.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                }
            }

            // 4. Extract & Download Rule Sets
            var remoteRuleSets = ExtractRemoteRuleSets(configRoot);
            var downloadedTags = new HashSet<string>();
            var pendingTags = new HashSet<string>();
            
            if (remoteRuleSets.Count > 0)
            {
                var ruleSetDir = Path.Combine(stagingDir, "rule-set");
                Directory.CreateDirectory(ruleSetDir);
                
                progress.Report(new InstallProgress { Step = "download_ruleset", Message = $"并行下载 rule-set: {remoteRuleSets.Count} 个" });
                
                // Concurrent Download (Max 2)
                using var semaphore = new SemaphoreSlim(2);
                var tasks = remoteRuleSets.Select(async rs =>
                {
                    await semaphore.WaitAsync();
                    try
                    {
                        var tag = rs.Key;
                        var url = rs.Value;
                        progress.Report(new InstallProgress { Step = "download_ruleset", Message = $"下载 rule-set({tag})..." });
                        
                        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
                        http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
                        
                        var data = await http.GetByteArrayAsync(url);
                        if (data.Length > 0)
                        {
                            var targetPath = Path.Combine(ruleSetDir, $"{tag}.srs");
                            await File.WriteAllBytesAsync(targetPath, data);
                            lock (downloadedTags) downloadedTags.Add(tag);
                        }
                        else
                        {
                            lock (pendingTags) pendingTags.Add(tag);
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"Download failed for {rs.Key}: {ex.Message}");
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
                    progress.Report(new InstallProgress { Step = "download_ruleset", Message = $"部分 rule-set 下载失败，将在连接后重试: {string.Join(", ", pendingTags)}" });
                }
            }

            // 5. Patch Config (Full)
            // Replace remote rule-sets with local paths
            // Note: We need absolute paths for the FINAL location, not staging.
            var finalRuleSetDir = Path.Combine(providerDir, "rule-set");
            
            progress.Report(new InstallProgress { Step = "patch_config", Message = "生成本地配置文件..." });
            
            // We must use the extracted configRoot, not context.ConfigContent (which might be a wrapper)
            // Clone configRoot to avoid modifying the original node if needed (JsonNode is mutable)
            // Reparsing from string is the easiest way to deep clone.
            var fullConfigNode = JsonNode.Parse(configRoot!.ToJsonString());
            
            // macOS Alignment: Ensure rule_set directory structure is used
            // macOS uses: "rule-set/tag.srs" relative path or absolute path. 
            // Sing-box usually resolves relative paths from config directory.
            // Let's use relative paths "./rule-set/tag.srs" to be portable and cleaner.
            PatchConfigRuleSetsToLocalPaths(fullConfigNode, "./rule-set", downloadedTags);
            
            var fullConfigJson = fullConfigNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            
            // 6. Write Active Config
            // We now write the full config directly. The Core (Program.cs) is responsible for:
            // - Detecting missing rule-sets (remote ones that failed to download here)
            // - Running in "Bootstrap Mode" (filtering out rules that use missing rule-sets)
            // - Retrying downloads in the background
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config.json"), fullConfigJson);

            // 8. Commit Files (Move Staging -> ProviderDir)
            if (Directory.Exists(providerDir))
            {
                // Backup existing? Or just delete.
                // For simplicity, delete. macOS does backup/restore dance but deletion is safer for consistent state if we don't need rollback.
                try { Directory.Delete(providerDir, true); } catch {}
            }
            Directory.Move(stagingDir, providerDir);

            // 9. Register Profile
            progress.Report(new InstallProgress { Step = "register", Message = "注册 Profile..." });
            
            var configPath = Path.Combine(providerDir, "config.json");
            
            // Check if profile exists for this provider (via InstalledProviderManager mapping)
            // We need a way to look up profile ID by provider ID.
            // Currently InstalledProviderManager maps ProfileID -> ProviderID.
            // We need reverse lookup or iterate.
            
            var existingProfileId = GetProfileIdByProviderId(providerId);
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

            // 10. Update InstalledProviderManager State
            // Note: We need to persist ruleSet URLs for pending retry logic (aligned with macOS)
            // macOS: installedProviderRuleSetURLByProvider.set(urlByProvider)
            
            InstalledProviderManager.Instance.RegisterInstalledProvider(
                providerId, 
                context.PackageHash, 
                pendingTags.ToList(),
                remoteRuleSets // Pass the full map of tags->URLs
            );
            
            InstalledProviderManager.Instance.MapProfileToProvider(installedProfileId, providerId);
            
            progress.Report(new InstallProgress { Step = "done", Message = "安装完成" });
            return true;
        }
        catch (Exception ex)
        {
            progress.Report(new InstallProgress { Step = "failed", Message = $"安装失败: {ex.Message}" });
            try { Directory.Delete(stagingDir, true); } catch { }
            return false;
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

    private void PatchConfigRuleSetsToLocalPaths(JsonNode? root, string relativeRuleSetDir, HashSet<string> downloadedTags)
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
                    // Replace with local
                    // Use forward slashes for cross-platform compatibility (Sing-box supports it)
                    // Or keep OS specific.
                    // But relative paths are better.
                    var path = Path.Combine(relativeRuleSetDir, $"{tag}.srs").Replace("\\", "/");
                    
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



    private long? GetProfileIdByProviderId(string providerId)
    {
        // This is inefficient but functional for now. 
        // Better to add Reverse Lookup in InstalledProviderManager later.
        // Or we iterate all profiles and check via InstalledProviderManager.
        
        // Wait, InstalledProviderManager has internal dictionary but exposes GetProviderIdForProfile(long).
        // We can't easily reverse lookup without iterating all profiles (which we don't have here).
        // But ProfileManager lists profiles.
        
        // Hack: Since we are in the Service, we can't easily access ProfileManager instance methods if they are async and we want sync lookup?
        // No, we are async.
        
        // Let's rely on ProfileManager list.
        var profiles = Task.Run(() => ProfileManager.Instance.ListAsync()).Result;
        foreach (var p in profiles)
        {
            if (InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == providerId)
            {
                return p.Id;
            }
        }
        return null;
    }
}
