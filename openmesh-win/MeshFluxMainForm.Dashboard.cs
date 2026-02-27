using System.Drawing;
using System.Text;

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
    }

    private static void PushTrafficSample(Queue<float> queue, long value)
    {
        queue.Enqueue(Math.Max(0, value));
        while (queue.Count > 36)
        {
            queue.Dequeue();
        }
    }

    private void UpdateRealTunnelUi(CoreResponse status)
    {
        var mode = string.IsNullOrWhiteSpace(status.P3EngineMode) ? "mock" : status.P3EngineMode.Trim().ToLowerInvariant();
        var realMode = mode is "singbox" or "sing-box" or "embedded";
        var ready = status.VpnRunning
                    && realMode
                    && status.P3WintunFound
                    && status.P3SingboxFound
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
        else if (!realMode)
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Mock Mode";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.DarkGoldenrod;
        }
        else
        {
            _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Partial";
            _dashboardRealTunnelStatusLabel.ForeColor = Color.Firebrick;
        }

        var detail = $"mode={mode}, wintun={(status.P3WintunFound ? "ok" : "missing")}, singbox={(status.P3SingboxFound ? "ok" : "missing")}, network={(status.P3NetworkPrepared ? "ok" : "no")}, engine={(status.P3EngineRunning && status.P3EngineHealthy ? "ok" : "no")}";
        _dashboardRealTunnelDetailLabel.Text = detail;

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

    private void OnDashboardProviderSelectionChanged()
    {
        var index = _dashboardProviderComboBox.SelectedIndex;
        if (index >= 0 && index < _dashboardProviderIds.Count)
        {
            _marketSelectedProviderId = _dashboardProviderIds[index];
        }
    }

    private async void RefreshDashboardProviderOptions()
    {
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
    }
}
