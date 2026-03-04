using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text.Json;

namespace OpenMeshWin;

public partial class MeshFluxMainForm
{
    private List<CoreProviderOffer> _marketOffers = new();
    private string _marketSelectedProviderId = string.Empty;
    private ProviderMarketForm? _providerMarketForm;

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

                    var profiles = await ProfileManager.Instance.ListAsync();
                    var latest = profiles.OrderByDescending(p => p.LastUpdated).FirstOrDefault();
                    if (latest != null)
                    {
                        var providerId = InstalledProviderManager.Instance.GetProviderIdForProfile(latest.Id);
                        var pid = !string.IsNullOrEmpty(providerId) ? providerId : $"profile:{latest.Id}";
                        _marketSelectedProviderId = pid;

                        await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
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

            offer.PendingRuleSets = InstalledProviderManager.Instance.GetPendingRuleSets(offer.Id);
        }
    }

    private List<CoreProviderOffer> BuildOffersForMarketManager()
    {
        var merged = _marketOffers.Select(CloneOffer).ToList();

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
                UpgradeAvailable = false,
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

        var confirm = MessageBox.Show(
            this,
            $"确定要卸载供应商 {providerId} 吗？",
            "卸载确认",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);

        if (confirm != DialogResult.Yes)
        {
            return;
        }

        var response = await _coreClient.UninstallProviderAsync(providerId);
        AppendLog($"provider_uninstall({providerId}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");

        if (!response.Ok)
        {
            MessageBox.Show(this, $"卸载失败: {response.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        InstalledProviderManager.Instance.RemoveProvider(providerId);

        if (string.Equals(_marketSelectedProviderId, providerId, StringComparison.OrdinalIgnoreCase))
        {
            _marketSelectedProviderId = string.Empty;
        }

        await RefreshMarketAsync(appendLog: false);
        await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
        UpdateProviderMarketFormData();
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
            if (installForm.SelectAfterInstall)
            {
                _marketSelectedProviderId = offer.Id;
            }
            await RefreshMarketAsync();
            await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
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
