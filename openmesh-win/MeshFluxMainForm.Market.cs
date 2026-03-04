using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text.Json;

namespace OpenMeshWin;

public partial class MeshFluxMainForm
{
    private List<CoreProviderOffer> _marketOffers = new();
    private string _marketSelectedProviderId = string.Empty;

    private async Task OpenMarketWindow()
    {
        // Switch to market tab
        _mainTabControl.SelectedTab = _marketTab;
        
        // Attach resize handler if not already (we can just remove and add to be safe)
        _marketCardsPanel.Resize -= OnMarketCardsPanelResize;
        _marketCardsPanel.Resize += OnMarketCardsPanelResize;
        
        await RefreshMarketAsync();
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
                RunActionAsync(async () => 
                {
                    // Refresh market list first (if needed for metadata, though not critical for local)
                    // await RefreshMarketAsync(); 
                    
                    // Refresh local profiles
                    await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
                    
                    // If we have a new profile (which we should from installer), select it.
                    // The installer doesn't return the ID, but we can find it by name or last updated.
                    var profiles = await ProfileManager.Instance.ListAsync();
                    var latest = profiles.OrderByDescending(p => p.LastUpdated).FirstOrDefault();
                    if (latest != null)
                    {
                        var providerId = InstalledProviderManager.Instance.GetProviderIdForProfile(latest.Id);
                        var pid = !string.IsNullOrEmpty(providerId) ? providerId : $"profile:{latest.Id}";
                        _marketSelectedProviderId = pid;
                        
                        // Force refresh combo box selection
                        await RefreshDashboardProviderOptionsAsync(applyToCoreAfterRefresh: _coreOnline);
                    }
                }).GetAwaiter();
            }
        }
    }

    private async Task RefreshMarketAsync(bool appendLog = true)
    {
        // Simple mock market refresh or real API call
        // In real app, this calls Core or API
        
        var response = new CoreResponse { Ok = true };
        
        // Try to fetch from core first if available?
        // Actually, we use direct API call in C# usually for better control, or delegate to Core.
        // Legacy code used _coreClient.FetchMarket...
        
        // Let's replicate logic from original file (will be removed from main)
        try
        {
            if (appendLog) AppendLog("Refreshing market...");
            
            // 1. Try Core Fetch (if supported)
            // response = await _coreClient.FetchMarketAsync();
            // If core doesn't support it or fails, we fallback to direct HTTP.
            
            // For alignment with macOS, we might want direct HTTP.
            // But let's assume we use a direct HTTP client here for now as in the original code.
            
            using var handler = new HttpClientHandler();
            // handler.ServerCertificateCustomValidationCallback = ... (from original)
            
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

            var url = $"{baseUrl}/api/v1/market/recommended";
            var json = await http.GetStringAsync(url);
            
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("data", out var dataElement) && dataElement.ValueKind == JsonValueKind.Array)
            {
                var fetchedOffers = new List<CoreProviderOffer>();
                foreach (var item in dataElement.EnumerateArray())
                {
                    var offer = new CoreProviderOffer();
                    if (item.TryGetProperty("id", out var p)) offer.Id = p.GetString() ?? "";
                    if (item.TryGetProperty("name", out var p2)) offer.Name = p2.GetString() ?? "";
                    if (item.TryGetProperty("description", out var p3)) offer.Description = p3.GetString() ?? "";
                    if (item.TryGetProperty("package_hash", out var p5)) offer.PackageHash = p5.GetString() ?? "";
                    if (item.TryGetProperty("config_url", out var p6)) offer.ConfigUrl = p6.GetString() ?? "";
                    if (item.TryGetProperty("detail_url", out var p7)) offer.DetailUrl = p7.GetString() ?? "";
                    if (item.TryGetProperty("tags", out var pTags) && pTags.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var tag in pTags.EnumerateArray())
                        {
                            var s = tag.GetString();
                            if (!string.IsNullOrEmpty(s)) offer.Tags.Add(s);
                        }
                    }
                    // ... other fields
                    fetchedOffers.Add(offer);
                }
                
                _marketOffers = fetchedOffers;
                
                // Sync with local installed state (Alignment with macOS)
                _installedProviderIds = new HashSet<string>(InstalledProviderManager.Instance.GetAllInstalledProviderIds(), StringComparer.OrdinalIgnoreCase);
                
                foreach (var offer in _marketOffers)
                {
                    if (_installedProviderIds.Contains(offer.Id))
                    {
                        var localHash = InstalledProviderManager.Instance.GetLocalPackageHash(offer.Id);
                        offer.InstalledPackageHash = localHash;
                        
                        // Check for updates
                        if (!string.IsNullOrEmpty(offer.PackageHash) && !string.IsNullOrEmpty(localHash))
                        {
                            offer.UpgradeAvailable = !string.Equals(offer.PackageHash, localHash, StringComparison.OrdinalIgnoreCase);
                        }

                        // Check for pending rule sets (Initialization)
                        offer.PendingRuleSets = InstalledProviderManager.Instance.GetPendingRuleSets(offer.Id);
                    }
                }

                RefreshMarketPreview(); // Update UI
                if (appendLog) AppendLog($"Market refreshed: {_marketOffers.Count} offers.");
            }
        }
        catch (Exception ex)
        {
            if (appendLog) AppendLog($"Market refresh failed: {ex.Message}");
        }
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
