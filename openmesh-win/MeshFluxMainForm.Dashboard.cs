using System.Drawing;
using System.Text;
using System.Threading;

namespace OpenMeshWin;

public partial class MeshFluxMainForm
{
    private void UpdateRuntimeUi(CoreRuntimeStats runtime)
    {
        _trafficValueLabel.Text = $"Up {FormatRate(runtime.UploadRateBytesPerSec)} | Down {FormatRate(runtime.DownloadRateBytesPerSec)}";
        _runtimeValueLabel.Text = $"Mem {runtime.MemoryMb:F1} MB | Thr {runtime.ThreadCount} | Up {runtime.UptimeSeconds}s | C {runtime.ConnectionCount}";
        _dashboardUpBadgeLabel.Text = $"UP  {FormatBytes(runtime.TotalUploadBytes)}";
        _dashboardDownBadgeLabel.Text = $"DOWN  {FormatBytes(runtime.TotalDownloadBytes)}";
        _dashboardNodeRateLabel.Text =
            $"UPLINK {FormatRate(runtime.UploadRateBytesPerSec)}  |  DOWNLINK {FormatRate(runtime.DownloadRateBytesPerSec)}";
        PushTrafficSample(_dashboardUploadHistory, runtime.UploadRateBytesPerSec);
        PushTrafficSample(_dashboardDownloadHistory, runtime.DownloadRateBytesPerSec);
        _dashboardTrafficChartPanel.SetSamples(_dashboardUploadHistory, _dashboardDownloadHistory);
        _activeTrafficDetailsForm?.UpdateData(runtime, _dashboardUploadHistory, _dashboardDownloadHistory);
    }

    private static void PushTrafficSample(Queue<float> queue, long value)
    {
        queue.Enqueue(Math.Max(0, value));
        while (queue.Count > 120)
        {
            queue.Dequeue();
        }
    }

    private void UpdateRealTunnelUi(CoreResponse status)
    {
        var mode = string.IsNullOrWhiteSpace(status.P3EngineMode) ? AppSettings.CoreModeEmbedded : status.P3EngineMode.Trim().ToLowerInvariant();
        var embeddedMode = string.Equals(mode, AppSettings.CoreModeEmbedded, StringComparison.OrdinalIgnoreCase);
        var ready = status.VpnRunning
                    && embeddedMode
                    && status.P3WintunFound
                    && status.P3NetworkPrepared
                    && status.P3EngineRunning
                    && status.P3EngineHealthy;

        var summary = ready
            ? "ready"
            : status.VpnRunning
                ? "partial"
                : "stopped";

        if (ready)
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Ready";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.ForestGreen;
        }
        else if (!status.VpnRunning)
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Stopped";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.DarkGoldenrod;
        }
        else if (!embeddedMode)
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Mode Mismatch";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.Firebrick;
        }
        else
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Partial";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.Firebrick;
        }

        var detail = $"mode={mode}, wintun={(status.P3WintunFound ? "ok" : "missing")}, network={(status.P3NetworkPrepared ? "ok" : "no")}, engine={(status.P3EngineRunning && status.P3EngineHealthy ? "ok" : "no")}";
        // _dashboardRealTunnelDetailLabel.Text = detail;


        if (!string.Equals(_lastRealTunnelSummary, summary, StringComparison.Ordinal))
        {
            _lastRealTunnelSummary = summary;
            AppendLog($"real tunnel state -> {summary}: {detail}");
            if (!string.IsNullOrWhiteSpace(status.P3EngineLastError))
            {
                AppendLog($"real tunnel engine error: {status.P3EngineLastError}");
            }
        }
    }

    private List<string> _dashboardProviderIds = new();
    private bool _dashboardProviderPopulating;
    private readonly SemaphoreSlim _dashboardProviderRefreshLock = new(1, 1);

    private void OnDashboardProviderSelectionChanged()
    {
        var index = _dashboardProviderComboBox.SelectedIndex;
        if (index >= 0 && index < _dashboardProviderIds.Count)
        {
            _marketSelectedProviderId = _dashboardProviderIds[index];
            if (_dashboardProviderPopulating)
            {
                return;
            }

            _ = RunActionAsync(() => ApplyDashboardProfileSelectionAsync(_marketSelectedProviderId, applyToCore: _coreOnline));
        }
    }

    private async Task RefreshDashboardProviderOptionsAsync(bool applyToCoreAfterRefresh)
    {
        await _dashboardProviderRefreshLock.WaitAsync();
        try
        {
            _dashboardProviderPopulating = true;
            _dashboardProviderComboBox.BeginUpdate();
            _dashboardProviderComboBox.Items.Clear();
            _dashboardProviderIds.Clear();

            var displayItems = new List<(string Id, string Name)>();

            try
            {
                var profiles = await ProfileManager.Instance.ListAsync();
                foreach (var profile in profiles)
                {
                    var providerId = InstalledProviderManager.Instance.GetProviderIdForProfile(profile.Id);
                    // Use profile ID if provider ID is missing (pure local)
                    // Or construct a composite ID.
                    string pid = !string.IsNullOrEmpty(providerId) ? providerId : $"profile:{profile.Id}";
                    displayItems.Add((pid, profile.Name));
                }
            }
            catch (Exception ex)
            {
                 AppendLog($"[Dashboard] Failed to list profiles: {ex.Message}");
            }

            // Add to ComboBox and track IDs
            foreach (var item in displayItems)
            {
                _dashboardProviderComboBox.Items.Add(item.Name);
                _dashboardProviderIds.Add(item.Id);
            }

            _dashboardProviderComboBox.EndUpdate();

            if (displayItems.Count > 0)
            {
                _dashboardProviderComboBox.Enabled = true;

                // Try to select current
                int index = -1;
                if (!string.IsNullOrEmpty(_marketSelectedProviderId))
                {
                    index = _dashboardProviderIds.FindIndex(id => id == _marketSelectedProviderId);
                }

                if (index >= 0)
                {
                    _dashboardProviderComboBox.SelectedIndex = index;
                }
                else
                {
                    _dashboardProviderComboBox.SelectedIndex = 0;
                    // If we have items, select first
                    if (_dashboardProviderIds.Count > 0)
                        _marketSelectedProviderId = _dashboardProviderIds[0];
                }
            }
            else
            {
                _dashboardProviderComboBox.Items.Add("请先安装/导入配置");
                if (_dashboardProviderComboBox.Items.Count > 0)
                    _dashboardProviderComboBox.SelectedIndex = 0;
                _dashboardProviderComboBox.Enabled = false;
                _marketSelectedProviderId = string.Empty;
            }

            _dashboardProviderPopulating = false;
        }
        finally
        {
            _dashboardProviderRefreshLock.Release();
        }

        await ApplyDashboardProfileSelectionAsync(_marketSelectedProviderId, applyToCore: applyToCoreAfterRefresh);
    }
}
