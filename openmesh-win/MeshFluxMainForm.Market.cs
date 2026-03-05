using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text.Json;

namespace OpenMeshWin;

public partial class MeshFluxMainForm
{
    private static readonly TimeSpan ProviderUpdateSentinelMinInterval = TimeSpan.FromHours(1);
    private List<CoreProviderOffer> _marketOffers = new();
    private string _marketSelectedProviderId = string.Empty;
    private ProviderMarketForm? _providerMarketForm;
    private bool _providerUpdateSentinelRunning;

    private async Task OpenMarketWindow()
    {
        if (_providerMarketForm is null || _providerMarketForm.IsDisposed)
        {
            _providerMarketForm = new ProviderMarketForm(
                offers: BuildOffersForMarketManager(),
                installedIds: new HashSet<string>(_installedProviderIds, StringComparer.OrdinalIgnoreCase),
                onInstallOrUpdate: InstallProviderFromMarketManagerAsync,
                onUninstall: UninstallProviderFromMarketManagerAsync,
                onRefresh: async () => await RefreshMarketAsync());

            _providerMarketForm.FormClosed += (_, _) => _providerMarketForm = null;
            _providerMarketForm.Show(this);
        }
        else
        {
            UpdateProviderMarketFormData();
            _providerMarketForm.Show();
            _providerMarketForm.BringToFront();
            _providerMarketForm.Activate();
        }

        // Align with macOS behavior: show window immediately, then refresh data in background.
        _ = RefreshMarketAsync(appendLog: false);
        _ = CheckInstalledProvidersUpdateSentinelAsync(force: true, appendLog: true);
    }

    private void UpdateProviderMarketFormData()
    {
        if (_providerMarketForm is null || _providerMarketForm.IsDisposed)
        {
            return;
        }

        _providerMarketForm.UpdateData(
            BuildOffersForMarketManager(),
            new HashSet<string>(_installedProviderIds, StringComparer.OrdinalIgnoreCase));
    }

    private void OnMarketCardsPanelResize(object? sender, EventArgs e)
    {
        if (_marketCardsPanel.Controls.Count == 0) return;
        ResizeMarketCardsToContainer();
    }

    private void OpenOfflineImportWindow()
    {
        using var importDialog = new OfflineImportInstallDialog();
        if (importDialog.ShowDialog(this) == DialogResult.OK)
        {
            var result = importDialog.Result;
            if (result is null || string.IsNullOrWhiteSpace(result.ImportContent))
            {
                return;
            }

            // Use the new ProviderInstaller flow (pass null for installAction to trigger new logic)
            var wizard = new ProviderInstallWizardDialog(result.ImportContent, null, result.ProviderName);

            if (wizard.ShowDialog(this) == DialogResult.OK)
            {
                // Refresh list
                _ = RunActionAsync(async () =>
                {
                    await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);

                    if (wizard.SelectAfterInstall)
                    {
                        var profiles = await ProfileManager.Instance.ListAsync();
                        var latest = profiles.OrderByDescending(p => p.LastUpdated).FirstOrDefault();
                        if (latest != null)
                        {
                            var providerId = InstalledProviderManager.Instance.GetProviderIdForProfile(latest.Id);
                            var pid = !string.IsNullOrEmpty(providerId) ? providerId : $"profile:{latest.Id}";
                            _marketSelectedProviderId = pid;

                            await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
                        }
                    }
                });
            }
        }
    }

    private async Task RefreshMarketAsync(bool appendLog = true)
    {
        try
        {
            if (appendLog) AppendLog("Refreshing market...");

            using var handler = new HttpClientHandler();
            using var http = new HttpClient(handler);
            http.Timeout = TimeSpan.FromSeconds(15);
            http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");

            var baseUrl = "https://openmesh-api.ribencong.workers.dev";
            try
            {
                await MarketManifestCache.Instance.RefreshAsync(http, baseUrl);
            }
            catch
            {
            }

            _marketOffers = await FetchMarketOffersAsync(http, baseUrl);
            await SyncInstalledStateForOffersAsync();
            await UpdateInstalledOffersWithDetailHashAsync(http, baseUrl);
            await CheckInstalledProvidersUpdateSentinelAsync(force: false, appendLog: true);

            RefreshMarketPreview();
            UpdateProviderMarketFormData();

            if (appendLog) AppendLog($"Market refreshed: {_marketOffers.Count} offers.");
        }
        catch (Exception ex)
        {
            if (appendLog) AppendLog($"Market refresh failed: {ex.Message}");
            await SyncInstalledStateForOffersAsync();
            RefreshMarketPreview();
            UpdateProviderMarketFormData();
        }
    }

    private async Task UpdateInstalledOffersWithDetailHashAsync(HttpClient http, string baseUrl)
    {
        var installedOffers = _marketOffers
            .Where(o => _installedProviderIds.Contains(o.Id) && !o.IsLocalOnly)
            .ToList();

        var tasks = installedOffers.Select(async offer =>
        {
            try
            {
                var url = $"{baseUrl}/api/v1/providers/{Uri.EscapeDataString(offer.Id)}";
                var json = await http.GetStringAsync(url);
                using var doc = JsonDocument.Parse(json);

                string remoteHash = string.Empty;
                if (doc.RootElement.TryGetProperty("package", out var packageElement) &&
                    packageElement.ValueKind == JsonValueKind.Object &&
                    packageElement.TryGetProperty("package_hash", out var packageHash) &&
                    packageHash.ValueKind == JsonValueKind.String)
                {
                    remoteHash = packageHash.GetString() ?? string.Empty;
                }
                else if (doc.RootElement.TryGetProperty("provider", out var providerElement) &&
                         providerElement.ValueKind == JsonValueKind.Object &&
                         providerElement.TryGetProperty("package_hash", out var providerHash) &&
                         providerHash.ValueKind == JsonValueKind.String)
                {
                    remoteHash = providerHash.GetString() ?? string.Empty;
                }

                if (!string.IsNullOrWhiteSpace(remoteHash))
                {
                    offer.PackageHash = remoteHash;
                    offer.UpgradeAvailable = !string.Equals(
                        remoteHash,
                        offer.InstalledPackageHash,
                        StringComparison.OrdinalIgnoreCase);
                }
            }
            catch
            {
                // Keep existing fallback state from manifest/list on detail fetch failure.
            }
        });

        await Task.WhenAll(tasks);
    }

    private async Task<List<CoreProviderOffer>> FetchMarketOffersAsync(HttpClient http, string baseUrl)
    {
        try
        {
            var paged = await FetchFromPagedMarketProvidersAsync(http, baseUrl);
            if (paged.Count > 0)
            {
                return paged;
            }
        }
        catch
        {
        }

        return await FetchFromManifestOrProvidersAsync(http, baseUrl);
    }

    private async Task<List<CoreProviderOffer>> FetchFromPagedMarketProvidersAsync(HttpClient http, string baseUrl)
    {
        const int pageSize = 24;
        const int maxPages = 5;
        var providers = new List<CoreProviderOffer>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var page = 1; page <= maxPages; page++)
        {
            var url = $"{baseUrl}/api/v1/market/providers?page={page}&page_size={pageSize}&sort=time&order=desc";
            var json = await http.GetStringAsync(url);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var data = ParseOfferList(root);

            if (data.Count == 0)
            {
                break;
            }

            foreach (var offer in data)
            {
                if (string.IsNullOrWhiteSpace(offer.Id))
                {
                    continue;
                }

                if (seen.Add(offer.Id))
                {
                    providers.Add(offer);
                }
            }

            if (data.Count < pageSize)
            {
                break;
            }

            if (root.TryGetProperty("total", out var totalProp) &&
                totalProp.ValueKind == JsonValueKind.Number &&
                totalProp.TryGetInt32(out var total) &&
                providers.Count >= total)
            {
                break;
            }
        }

        return providers;
    }

    private async Task<List<CoreProviderOffer>> FetchFromManifestOrProvidersAsync(HttpClient http, string baseUrl)
    {
        try
        {
            var manifestJson = await http.GetStringAsync($"{baseUrl}/api/v1/market/manifest");
            using var manifestDoc = JsonDocument.Parse(manifestJson);
            var offers = ParseOfferList(manifestDoc.RootElement);
            if (offers.Count > 0)
            {
                return offers;
            }
        }
        catch
        {
        }

        var providersJson = await http.GetStringAsync($"{baseUrl}/api/v1/providers");
        using var providersDoc = JsonDocument.Parse(providersJson);
        return ParseOfferList(providersDoc.RootElement);
    }

    private static List<CoreProviderOffer> ParseOfferList(JsonElement root)
    {
        JsonElement array = default;

        if (root.TryGetProperty("data", out var dataElement) && dataElement.ValueKind == JsonValueKind.Array)
        {
            array = dataElement;
        }
        else if (root.TryGetProperty("providers", out var providersElement) && providersElement.ValueKind == JsonValueKind.Array)
        {
            array = providersElement;
        }
        else if (root.TryGetProperty("data", out dataElement) &&
                 dataElement.ValueKind == JsonValueKind.Object &&
                 dataElement.TryGetProperty("providers", out providersElement) &&
                 providersElement.ValueKind == JsonValueKind.Array)
        {
            array = providersElement;
        }
        else
        {
            return [];
        }

        var offers = new List<CoreProviderOffer>();
        foreach (var item in array.EnumerateArray())
        {
            offers.Add(ParseOffer(item));
        }
        return offers;
    }

    private static CoreProviderOffer ParseOffer(JsonElement item)
    {
        var offer = new CoreProviderOffer();
        if (item.TryGetProperty("id", out var idProp)) offer.Id = idProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("name", out var nameProp)) offer.Name = nameProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("author", out var authorProp)) offer.Author = authorProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("description", out var descProp)) offer.Description = descProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("package_hash", out var packageHashProp)) offer.PackageHash = packageHashProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("config_url", out var configUrlProp)) offer.ConfigUrl = configUrlProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("detail_url", out var detailUrlProp)) offer.DetailUrl = detailUrlProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("updated_at", out var updatedProp)) offer.UpdatedAt = updatedProp.GetString() ?? string.Empty;
        if (item.TryGetProperty("region", out var regionProp)) offer.Region = regionProp.GetString() ?? string.Empty;

        if (item.TryGetProperty("price_per_gb_usd", out var priceProp))
        {
            if (priceProp.ValueKind == JsonValueKind.Number && priceProp.TryGetDecimal(out var priceDec))
            {
                offer.PricePerGb = priceDec;
            }
            else if (priceProp.ValueKind == JsonValueKind.String && decimal.TryParse(priceProp.GetString(), out var parsed))
            {
                offer.PricePerGb = parsed;
            }
        }

        if (item.TryGetProperty("tags", out var tagsProp) && tagsProp.ValueKind == JsonValueKind.Array)
        {
            foreach (var tag in tagsProp.EnumerateArray())
            {
                var tagValue = tag.GetString();
                if (!string.IsNullOrWhiteSpace(tagValue))
                {
                    offer.Tags.Add(tagValue);
                }
            }
        }

        return offer;
    }

    private async Task SyncInstalledStateForOffersAsync()
    {
        var installedIds = new HashSet<string>(
            InstalledProviderManager.Instance.GetAllInstalledProviderIds(),
            StringComparer.OrdinalIgnoreCase);
        var profiles = await ProfileManager.Instance.ListAsync();
        foreach (var p in profiles)
        {
            var mappedProviderId = InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id);
            if (!string.IsNullOrWhiteSpace(mappedProviderId))
            {
                installedIds.Add(mappedProviderId);
            }
        }

        _installedProviderIds = installedIds;
        var persistedUpdates = InstalledProviderManager.Instance.GetProviderUpdatesAvailable();

        foreach (var offer in _marketOffers)
        {
            offer.UpgradeAvailable = false;
            offer.PendingRuleSets = [];
            offer.InstalledPackageHash = string.Empty;

            if (!_installedProviderIds.Contains(offer.Id))
            {
                continue;
            }

            var localHash = InstalledProviderManager.Instance.GetLocalPackageHash(offer.Id);
            offer.InstalledPackageHash = localHash;

            // Align with macOS: installed + remoteHash exists + localHash != remoteHash => update available.
            if (!string.IsNullOrEmpty(offer.PackageHash))
            {
                offer.UpgradeAvailable = !string.Equals(offer.PackageHash, localHash, StringComparison.OrdinalIgnoreCase);
            }
            else if (persistedUpdates.TryGetValue(offer.Id, out var hasUpdate))
            {
                offer.UpgradeAvailable = hasUpdate;
            }

            offer.PendingRuleSets = InstalledProviderManager.Instance.GetPendingRuleSets(offer.Id);
        }
    }

    private List<CoreProviderOffer> BuildOffersForMarketManager()
    {
        var merged = _marketOffers.Select(CloneOffer).ToList();
        var persistedUpdates = InstalledProviderManager.Instance.GetProviderUpdatesAvailable();

        foreach (var providerId in _installedProviderIds)
        {
            if (merged.Any(x => string.Equals(x.Id, providerId, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            merged.Add(new CoreProviderOffer
            {
                Id = providerId,
                Name = providerId,
                Author = "OpenMesh Team",
                Description = "本地已安装供应商（市场数据离线或未收录）",
                UpdatedAt = "-",
                PricePerGb = 0,
                InstalledPackageHash = InstalledProviderManager.Instance.GetLocalPackageHash(providerId),
                PackageHash = string.Empty,
                UpgradeAvailable = persistedUpdates.TryGetValue(providerId, out var hasUpdate) && hasUpdate,
                PendingRuleSets = InstalledProviderManager.Instance.GetPendingRuleSets(providerId),
                IsLocalOnly = true
            });
        }

        return merged;
    }

    private static CoreProviderOffer CloneOffer(CoreProviderOffer src)
    {
        return new CoreProviderOffer
        {
            Id = src.Id,
            Name = src.Name,
            Author = src.Author,
            Region = src.Region,
            UpdatedAt = src.UpdatedAt,
            PricePerGb = src.PricePerGb,
            PackageHash = src.PackageHash,
            Description = src.Description,
            InstalledPackageHash = src.InstalledPackageHash,
            UpgradeAvailable = src.UpgradeAvailable,
            Tags = src.Tags.ToList(),
            PendingRuleSets = src.PendingRuleSets.ToList(),
            ConfigUrl = src.ConfigUrl,
            DetailUrl = src.DetailUrl,
            IsLocalOnly = src.IsLocalOnly
        };
    }

    private void RefreshMarketPreview()
    {
        _marketCardsPanel.SuspendLayout();
        _marketCardsPanel.Controls.Clear();

        foreach (var offer in _marketOffers)
        {
            var isInstalled = _installedProviderIds.Contains(offer.Id);
            var card = new ProviderCardControl(offer, isInstalled);
            card.Width = GetMarketCardTargetWidth();
            card.InstallClicked += async () =>
            {
                await RunActionAsync(() => InstallProviderFromCard(offer));
            };
            _marketCardsPanel.Controls.Add(card);
        }

        ResizeMarketCardsToContainer();
        _marketCardsPanel.ResumeLayout();
    }

    private void ResizeMarketCardsToContainer()
    {
        var width = GetMarketCardTargetWidth();
        _marketCardsPanel.SuspendLayout();
        foreach (Control c in _marketCardsPanel.Controls)
        {
            c.Width = width;
        }
        _marketCardsPanel.ResumeLayout();
    }

    private int GetMarketCardTargetWidth()
    {
        var available = _marketCardsPanel.DisplayRectangle.Width - 6;
        return Math.Max(220, available);
    }

    private async Task InstallProviderFromMarketManagerAsync(string providerId)
    {
        var offer = _marketOffers.FirstOrDefault(x => string.Equals(x.Id, providerId, StringComparison.OrdinalIgnoreCase));
        if (offer is null)
        {
            MessageBox.Show(this, "未找到对应供应商数据，请先刷新。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        await InstallProviderFromCard(offer);
        UpdateProviderMarketFormData();
    }

    private async Task UninstallProviderFromMarketManagerAsync(string providerId)
    {
        if (string.IsNullOrWhiteSpace(providerId))
        {
            return;
        }

        var displayName = _marketOffers
            .FirstOrDefault(x => string.Equals(x.Id, providerId, StringComparison.OrdinalIgnoreCase))?.Name
            ?? providerId;

        using var uninstallForm = new ProviderUninstallForm(
            providerId,
            displayName,
            async progress => await PerformProviderUninstallAsync(providerId, progress));

        if (uninstallForm.ShowDialog(this) != DialogResult.OK || !uninstallForm.UninstallSuccess)
        {
            return;
        }

        await RefreshMarketAsync(appendLog: false);
        await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
        UpdateProviderMarketFormData();
    }

    private async Task PerformProviderUninstallAsync(
        string providerId,
        IProgress<(string Step, string Message)> progress)
    {
        progress.Report(("validate", "检查当前连接状态"));
        if (_dashboardVpnRunning && string.Equals(_marketSelectedProviderId, providerId, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("当前 VPN 正在使用该供应商，请先断开 VPN 再卸载。");
        }

        progress.Report(("remove_profile", "删除本地 Profile 记录"));
        var profiles = await ProfileManager.Instance.ListAsync();
        var profileIds = profiles
            .Where(p => string.Equals(InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id), providerId, StringComparison.OrdinalIgnoreCase))
            .Select(p => p.Id)
            .ToList();

        foreach (var pid in profileIds)
        {
            SelectedOutboundStore.Instance.Remove(pid);
            await ProfileManager.Instance.DeleteAsync(pid);
        }

        progress.Report(("remove_preferences", "清理本地映射与缓存状态"));
        InstalledProviderManager.Instance.RemoveProvider(providerId);
        if (string.Equals(_marketSelectedProviderId, providerId, StringComparison.OrdinalIgnoreCase))
        {
            _marketSelectedProviderId = string.Empty;
            SelectedProfileStore.Instance.Set(string.Empty);
        }

        progress.Report(("remove_files", "删除 provider 目录与临时目录"));
        RemoveProviderFiles(providerId);

        if (_coreOnline)
        {
            var response = await _coreClient.UninstallProviderAsync(providerId);
            AppendLog($"provider_uninstall({providerId}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        }

        progress.Report(("finalize", "完成"));
    }

    private static void RemoveProviderFiles(string providerId)
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenMeshWin",
            "providers");
        var providerDir = Path.Combine(root, providerId);
        if (Directory.Exists(providerDir))
        {
            Directory.Delete(providerDir, recursive: true);
        }

        foreach (var special in new[] { ".staging", ".backup" })
        {
            var specialDir = Path.Combine(root, special);
            if (!Directory.Exists(specialDir))
            {
                continue;
            }

            foreach (var dir in Directory.GetDirectories(specialDir))
            {
                var name = Path.GetFileName(dir);
                if (string.Equals(name, providerId, StringComparison.OrdinalIgnoreCase) ||
                    name.StartsWith(providerId + "-", StringComparison.OrdinalIgnoreCase))
                {
                    try { Directory.Delete(dir, recursive: true); } catch { }
                }
            }
        }
    }

    private async Task InstallProviderFromCard(CoreProviderOffer offer)
    {
        if (!_coreOnline)
        {
            MessageBox.Show("核心服务未连接，无法安装。", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var installForm = new ProviderInstallForm(offer, async (selectAfterInstall, progress) =>
        {
            return await ProviderInstaller.Instance.InstallFromMarketOfferAsync(offer, selectAfterInstall, progress);
        });

        installForm.ShowDialog(this);

        if (installForm.InstallSuccess)
        {
            var updateFlags = InstalledProviderManager.Instance.GetProviderUpdatesAvailable();
            if (updateFlags.Remove(offer.Id))
            {
                InstalledProviderManager.Instance.SetProviderUpdatesAvailable(updateFlags);
            }

            if (installForm.SelectAfterInstall)
            {
                _marketSelectedProviderId = offer.Id;
            }
            await RefreshMarketAsync();
            await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
        }
    }

    private async Task CheckInstalledProvidersUpdateSentinelAsync(bool force, bool appendLog)
    {
        if (_providerUpdateSentinelRunning)
        {
            LogProviderSentinel("skip: previous run still in progress", appendLog);
            return;
        }

        var installedHashes = InstalledProviderManager.Instance
            .GetAllInstalledProviderIds()
            .Select(id => new
            {
                ProviderId = id,
                LocalHash = InstalledProviderManager.Instance.GetLocalPackageHash(id)
            })
            .Where(x => !string.IsNullOrWhiteSpace(x.ProviderId) &&
                        !string.IsNullOrWhiteSpace(x.LocalHash) &&
                        !x.ProviderId.StartsWith("imported-", StringComparison.OrdinalIgnoreCase))
            .ToList();

        if (installedHashes.Count == 0)
        {
            LogProviderSentinel("skip: no installed providers with local hash", appendLog);
            return;
        }

        var nowUnix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var lastCheckedUnix = InstalledProviderManager.Instance.GetProviderUpdatesLastCheckedAtUnix();
        if (!force && nowUnix - lastCheckedUnix < ProviderUpdateSentinelMinInterval.TotalSeconds)
        {
            var elapsed = nowUnix - lastCheckedUnix;
            LogProviderSentinel($"skip: rate-limited (elapsed={elapsed}s, min={(int)ProviderUpdateSentinelMinInterval.TotalSeconds}s)", appendLog);
            return;
        }

        _providerUpdateSentinelRunning = true;
        try
        {
            InstalledProviderManager.Instance.SetProviderUpdatesLastCheckedAtUnix(nowUnix);
            LogProviderSentinel($"start: checking {installedHashes.Count} installed providers (force={force})", appendLog);

            using var handler = new HttpClientHandler();
            using var http = new HttpClient(handler);
            http.Timeout = TimeSpan.FromSeconds(15);
            http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
            const string baseUrl = "https://openmesh-api.ribencong.workers.dev";

            var results = await Task.WhenAll(installedHashes.Select(async item =>
            {
                var remoteHash = await TryFetchLatestPackageHashAsync(http, baseUrl, item.ProviderId);
                var hasUpdate = !string.IsNullOrWhiteSpace(remoteHash) &&
                                !string.Equals(remoteHash, item.LocalHash, StringComparison.OrdinalIgnoreCase);
                if (hasUpdate)
                {
                    LogProviderSentinel(
                        $"update found: provider={item.ProviderId}, local={item.LocalHash}, remote={remoteHash}",
                        appendLog);
                }
                return (item.ProviderId, hasUpdate, remoteHash);
            }));

            var existingFlags = InstalledProviderManager.Instance.GetProviderUpdatesAvailable();
            var changed = false;
            foreach (var (providerId, hasUpdate, _) in results)
            {
                if (!hasUpdate)
                {
                    continue;
                }

                if (!existingFlags.TryGetValue(providerId, out var old) || !old)
                {
                    existingFlags[providerId] = true;
                    changed = true;
                }
            }

            if (changed)
            {
                InstalledProviderManager.Instance.SetProviderUpdatesAvailable(existingFlags);
                LogProviderSentinel("state updated: provider update flags persisted", appendLog);

                foreach (var offer in _marketOffers)
                {
                    if (existingFlags.TryGetValue(offer.Id, out var hasUpdate))
                    {
                        offer.UpgradeAvailable = hasUpdate || offer.UpgradeAvailable;
                    }
                }

                RefreshMarketPreview();
                UpdateProviderMarketFormData();
            }
            else
            {
                LogProviderSentinel("done: all installed providers are up-to-date", appendLog);
            }
        }
        catch (Exception ex)
        {
            LogProviderSentinel($"failed: {ex.Message}", appendLog);
        }
        finally
        {
            _providerUpdateSentinelRunning = false;
            LogProviderSentinel("finished", appendLog);
        }
    }

    private void LogProviderSentinel(string message, bool appendLog)
    {
        var line = $"provider update sentinel: {message}";
        if (appendLog)
        {
            AppendLog(line);
            return;
        }

        AppLogger.Log(line);
    }

    private static async Task<string> TryFetchLatestPackageHashAsync(HttpClient http, string baseUrl, string providerId)
    {
        try
        {
            var url = $"{baseUrl}/api/v1/providers/{Uri.EscapeDataString(providerId)}";
            var json = await http.GetStringAsync(url);
            using var doc = JsonDocument.Parse(json);

            if (doc.RootElement.TryGetProperty("package", out var packageElement) &&
                packageElement.ValueKind == JsonValueKind.Object &&
                packageElement.TryGetProperty("package_hash", out var packageHash) &&
                packageHash.ValueKind == JsonValueKind.String)
            {
                return packageHash.GetString() ?? string.Empty;
            }

            if (doc.RootElement.TryGetProperty("provider", out var providerElement) &&
                providerElement.ValueKind == JsonValueKind.Object &&
                providerElement.TryGetProperty("package_hash", out var providerHash) &&
                providerHash.ValueKind == JsonValueKind.String)
            {
                return providerHash.GetString() ?? string.Empty;
            }

            return string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }
}

internal sealed class ProviderCardControl : Panel
{
    private readonly CoreProviderOffer _offer;
    private readonly bool _isInstalled;
    private readonly Button _actionButton = new();

    public event Action? InstallClicked;

    public ProviderCardControl(CoreProviderOffer offer, bool isInstalled)
    {
        _offer = offer;
        _isInstalled = isInstalled;
        Height = 126;
        BackColor = Color.FromArgb(248, 251, 255);
        Padding = new Padding(12, 10, 12, 10);

        var title = new Label
        {
            Text = offer.Name,
            Font = new Font("Segoe UI", 11F, FontStyle.Bold),
            ForeColor = Color.FromArgb(34, 52, 70),
            AutoSize = true,
            Location = new Point(12, 10)
        };

        var author = new Label
        {
            Text = string.IsNullOrWhiteSpace(offer.Author) ? "OpenMesh Team" : offer.Author,
            Font = new Font("Segoe UI", 8.8F, FontStyle.Regular),
            ForeColor = Color.FromArgb(102, 119, 138),
            AutoSize = true,
            Location = new Point(12, 34)
        };

        var description = new Label
        {
            Text = string.IsNullOrWhiteSpace(offer.Description) ? "暂无描述" : offer.Description,
            Font = new Font("Segoe UI", 9F, FontStyle.Regular),
            ForeColor = Color.FromArgb(40, 56, 72),
            Location = new Point(12, 54),
            Size = new Size(560, 34),
            AutoEllipsis = true
        };

        var tag = new Label
        {
            Text = string.Join("  ", offer.Tags.Take(4)),
            Font = new Font("Segoe UI", 8F, FontStyle.Bold),
            ForeColor = Color.FromArgb(102, 119, 138),
            AutoSize = true,
            Location = new Point(12, 92)
        };

        ConfigureActionButton();

        Controls.Add(title);
        Controls.Add(author);
        Controls.Add(description);
        Controls.Add(tag);
        Controls.Add(_actionButton);

        Resize += (_, _) =>
        {
            _actionButton.Left = Width - _actionButton.Width - 12;
            description.Width = Math.Max(220, Width - 220);
        };

        Paint += (_, e) =>
        {
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var pen = new Pen(Color.FromArgb(205, 222, 238), 1);
            using var path = CreateRoundedPath(rect, 10);
            Region = new Region(path);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.DrawPath(pen, path);
        };
    }

    private void ConfigureActionButton()
    {
        var actionText = _isInstalled ? (_offer.UpgradeAvailable ? "Update" : "Reinstall") : "Install";
        var buttonColor = _offer.UpgradeAvailable
            ? Color.FromArgb(233, 179, 73)
            : (_isInstalled ? Color.FromArgb(89, 230, 245) : Color.FromArgb(71, 167, 230));

        _actionButton.Text = actionText;
        _actionButton.Size = new Size(84, 30);
        _actionButton.FlatStyle = FlatStyle.Flat;
        _actionButton.FlatAppearance.BorderSize = 0;
        _actionButton.BackColor = buttonColor;
        _actionButton.ForeColor = Color.White;
        _actionButton.Font = new Font("Segoe UI", 8.8F, FontStyle.Bold);
        _actionButton.Cursor = Cursors.Hand;
        _actionButton.Location = new Point(Width - _actionButton.Width - 12, 12);
        _actionButton.Click += (_, _) => InstallClicked?.Invoke();
        _actionButton.Paint += (_, _) =>
        {
            using var path = CreateRoundedPath(new Rectangle(0, 0, _actionButton.Width, _actionButton.Height), 11);
            _actionButton.Region = new Region(path);
        };
    }

    private static GraphicsPath CreateRoundedPath(Rectangle rect, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
