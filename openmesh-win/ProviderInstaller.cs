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

    public async Task<bool> InstallFromContextAsync(ImportInstallContext context, IProgress<InstallProgress> progress)
    {
        var providerId = !string.IsNullOrWhiteSpace(context.ProviderId) 
            ? context.ProviderId 
            : $"imported-{Guid.NewGuid().ToString().ToLower()}";
        
        var providerName = !string.IsNullOrWhiteSpace(context.ProviderName) 
            ? context.ProviderName 
            : "导入供应商";

        progress.Report(new InstallProgress { Step = "init", Message = $"开始安装供应商: {providerName} ({providerId})" });

        // 1. Prepare Staging Directory
        var stagingDir = Path.Combine(_providersRoot, ".staging", $"{providerId}-{Guid.NewGuid()}");
        var providerDir = Path.Combine(_providersRoot, providerId);
        Directory.CreateDirectory(stagingDir);

        try
        {
            // 2. Validate Config
            progress.Report(new InstallProgress { Step = "validate", Message = "解析并校验配置文件..." });
            JsonNode? configRoot;
            try
            {
                configRoot = JsonNode.Parse(context.ConfigContent);
                if (configRoot == null) throw new Exception("配置内容为空");
            }
            catch (Exception ex)
            {
                throw new Exception($"JSON 解析失败: {ex.Message}");
            }

            // TODO: Validate Tun Stack Compatibility (optional for now)

            // 3. Write Routing Rules (if any)
            if (!string.IsNullOrWhiteSpace(context.RoutingRulesContent))
            {
                progress.Report(new InstallProgress { Step = "write_rules", Message = "写入 routing_rules.json" });
                await File.WriteAllTextAsync(Path.Combine(stagingDir, "routing_rules.json"), context.RoutingRulesContent);
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
            var fullConfigNode = JsonNode.Parse(context.ConfigContent); // Re-parse to be safe
            PatchConfigRuleSetsToLocalPaths(fullConfigNode, finalRuleSetDir, downloadedTags);
            
            var fullConfigJson = fullConfigNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config_full.json"), fullConfigJson);

            // 6. Generate Bootstrap Config (if pending tags exist)
            string activeConfigJson;
            if (pendingTags.Count == 0)
            {
                activeConfigJson = fullConfigJson;
            }
            else
            {
                progress.Report(new InstallProgress { Step = "bootstrap_config", Message = "生成 Bootstrap 配置 (跳过未下载规则)..." });
                // We must use fullConfigJson as base, but removing pending tags. 
                // Note: macOS uses 'removingRemoteRuleSets: true' which means ALL remote rule-sets are removed.
                // However, we patched downloaded ones to 'local'. So only 'remote' ones (failed downloads) remain.
                // So removing all 'remote' rule-sets is correct.
                
                var bootstrapNode = JsonNode.Parse(fullConfigJson);
                MakeBootstrapConfig(bootstrapNode, pendingTags);
                var bootstrapJson = bootstrapNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
                await File.WriteAllTextAsync(Path.Combine(stagingDir, "config_bootstrap.json"), bootstrapJson);
                activeConfigJson = bootstrapJson;
            }

            // 7. Write Active Config
            await File.WriteAllTextAsync(Path.Combine(stagingDir, "config.json"), activeConfigJson);

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

    private void PatchConfigRuleSetsToLocalPaths(JsonNode? root, string finalRuleSetDir, HashSet<string> downloadedTags)
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
                    var newNode = new JsonObject
                    {
                        ["type"] = "local",
                        ["tag"] = tag,
                        ["format"] = "binary",
                        ["path"] = Path.Combine(finalRuleSetDir, $"{tag}.srs")
                    };
                    ruleSets[i] = newNode;
                }
            }
        }
    }

    private void MakeBootstrapConfig(JsonNode? root, HashSet<string> removedTags)
    {
        var route = root?["config"]?["route"] as JsonObject ?? root?["route"] as JsonObject;
        
        if (route != null)
        {
            // 1. Remove failed remote rule-sets
            if (route["rule_set"] is JsonArray ruleSets)
            {
                for (int i = ruleSets.Count - 1; i >= 0; i--)
                {
                    var node = ruleSets[i];
                    if (node?["type"]?.ToString() == "remote" &&
                        node?["tag"]?.ToString() is string tag &&
                        removedTags.Contains(tag))
                    {
                        ruleSets.RemoveAt(i);
                    }
                }
            }

            // 2. Remove references in rules
            if (route["rules"] is JsonArray rules)
            {
                RemoveRuleSetReferences(rules, removedTags);
            }

            // 3. Ensure final = proxy
            route["final"] = "proxy";
        }
        
        // Check DNS rules in config.dns.rules OR dns.rules
        var dnsRules = root?["config"]?["dns"]?["rules"] as JsonArray ?? root?["dns"]?["rules"] as JsonArray;

        if (dnsRules != null)
        {
            RemoveRuleSetReferences(dnsRules, removedTags);
        }
        
        // 4. Clean up inbounds (route_exclude_address_set)
        var inbounds = root?["config"]?["inbounds"] as JsonArray ?? root?["inbounds"] as JsonArray;
        
        if (inbounds != null)
        {
            foreach (var inbound in inbounds)
            {
                if (inbound?["route_exclude_address_set"] is JsonArray exclude)
                {
                    for (int i = exclude.Count - 1; i >= 0; i--)
                    {
                        if (exclude[i]?.ToString() is string tag && removedTags.Contains(tag))
                        {
                            exclude.RemoveAt(i);
                        }
                    }
                }
            }
        }
    }

    private void RemoveRuleSetReferences(JsonArray rules, HashSet<string> removedTags)
    {
        for (int i = rules.Count - 1; i >= 0; i--)
        {
            var rule = rules[i];
            var refTag = rule?["rule_set"];
            
            if (refTag is JsonValue val && val.TryGetValue<string>(out var s) && removedTags.Contains(s))
            {
                rules.RemoveAt(i);
                continue;
            }
            
            if (refTag is JsonArray arr)
            {
                // If any tag in array is removed, do we remove the rule? 
                // macOS logic: if arr.contains(where: { removedTags.contains($0) }) { continue } -> removes rule
                bool hasRemoved = false;
                foreach (var item in arr)
                {
                    if (item?.ToString() is string t && removedTags.Contains(t))
                    {
                        hasRemoved = true;
                        break;
                    }
                }
                if (hasRemoved)
                {
                    rules.RemoveAt(i);
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
