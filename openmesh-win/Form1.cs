using System.Drawing;

namespace OpenMeshWin;

public partial class Form1 : Form
{
    private bool _exitRequested;
    private readonly CoreClient _coreClient = new();
    private readonly CoreProcessManager _coreProcessManager = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 1200 };
    private bool _lastCoreOnline;
    private bool _coreOnline;
    private string _lastConfigHash = string.Empty;
    private int _lastInjectedRuleCount = -1;
    private readonly ComboBox _groupComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _outboundComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Button _urlTestButton = new() { Text = "URLTest", Width = 90, Height = 30 };
    private readonly Button _selectOutboundButton = new() { Text = "Select Outbound", Width = 130, Height = 30 };
    private readonly ListBox _urlTestResultListBox = new();
    private readonly Label _groupLabel = new() { Text = "Group:" };
    private readonly Label _outboundLabel = new() { Text = "Outbound:" };
    private readonly Dictionary<string, CoreOutboundGroup> _groupByTag = new(StringComparer.OrdinalIgnoreCase);
    private readonly Label _trafficTitleLabel = new() { Text = "Traffic:" };
    private readonly Label _trafficValueLabel = new() { Text = "Up 0 B/s | Down 0 B/s" };
    private readonly Label _runtimeTitleLabel = new() { Text = "Core Runtime:" };
    private readonly Label _runtimeValueLabel = new() { Text = "Memory 0 MB | Threads 0 | Uptime 0s | Conns 0" };
    private readonly Label _connectionTitleLabel = new() { Text = "Connections:" };
    private readonly TextBox _connectionSearchTextBox = new();
    private readonly ComboBox _connectionSortComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox _connectionDescCheckBox = new() { Text = "Desc", Checked = true };
    private readonly Button _refreshConnectionsButton = new() { Text = "Refresh Conn", Width = 102, Height = 28 };
    private readonly Button _closeConnectionButton = new() { Text = "Close Selected", Width = 102, Height = 28 };
    private readonly ListView _connectionListView = new()
    {
        View = View.Details,
        FullRowSelect = true,
        GridLines = true,
        HideSelection = false
    };

    public Form1()
    {
        InitializeComponent();

        trayIcon.Icon = SystemIcons.Application;
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();

        trayOpenMenuItem.Click += (_, _) => ShowMainWindow();
        trayStartVpnMenuItem.Click += async (_, _) => await RunActionAsync(StartVpnAsync);
        trayStopVpnMenuItem.Click += async (_, _) => await RunActionAsync(StopVpnAsync);
        trayReloadMenuItem.Click += async (_, _) => await RunActionAsync(ReloadConfigAsync);
        trayRefreshMenuItem.Click += async (_, _) => await RunActionAsync(RefreshStatusAsync);
        trayExitMenuItem.Click += (_, _) => ExitApplication();

        startCoreButton.Click += async (_, _) => await RunActionAsync(StartCoreAsync);
        startVpnButton.Click += async (_, _) => await RunActionAsync(StartVpnAsync);
        stopVpnButton.Click += async (_, _) => await RunActionAsync(StopVpnAsync);
        reloadConfigButton.Click += async (_, _) => await RunActionAsync(ReloadConfigAsync);
        refreshStatusButton.Click += async (_, _) => await RunActionAsync(RefreshStatusAsync);
        _urlTestButton.Click += async (_, _) => await RunActionAsync(UrlTestAsync);
        _selectOutboundButton.Click += async (_, _) => await RunActionAsync(SelectOutboundAsync);
        _groupComboBox.SelectedIndexChanged += (_, _) => RefreshOutboundSelectionUi();
        _refreshConnectionsButton.Click += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(appendLog: true));
        _closeConnectionButton.Click += async (_, _) => await RunActionAsync(CloseSelectedConnectionAsync);
        _connectionSortComboBox.SelectedIndexChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync());
        _connectionDescCheckBox.CheckedChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync());
        _connectionListView.SelectedIndexChanged += (_, _) =>
        {
            _closeConnectionButton.Enabled = _coreOnline && _connectionListView.SelectedItems.Count > 0;
        };
        _connectionSearchTextBox.KeyDown += async (_, e) =>
        {
            if (e.KeyCode != Keys.Enter)
            {
                return;
            }

            e.Handled = true;
            e.SuppressKeyPress = true;
            await RunActionAsync(() => RefreshConnectionsAsync(appendLog: true));
        };

        InitializePhase3Controls();
        InitializePhase4Controls();

        Load += async (_, _) => await RunActionAsync(InitialLoadAsync);

        _statusTimer.Tick += async (_, _) => await RunActionAsync(RefreshStatusAsync);

        Resize += (_, _) =>
        {
            if (WindowState == FormWindowState.Minimized)
            {
                HideMainWindow();
            }
        };

        FormClosing += (_, e) =>
        {
            if (!_exitRequested)
            {
                e.Cancel = true;
                HideMainWindow();
                return;
            }

            _statusTimer.Stop();
            trayIcon.Visible = false;
        };
    }

    private void InitializePhase3Controls()
    {
        _groupLabel.SetBounds(24, 198, 46, 20);
        _groupComboBox.SetBounds(74, 194, 140, 24);

        _outboundLabel.SetBounds(226, 198, 62, 20);
        _outboundComboBox.SetBounds(292, 194, 170, 24);

        _urlTestButton.SetBounds(474, 191, 90, 30);
        _selectOutboundButton.SetBounds(568, 191, 102, 30);

        _urlTestResultListBox.SetBounds(24, 228, 646, 72);
        _urlTestResultListBox.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;

        Controls.Add(_groupLabel);
        Controls.Add(_groupComboBox);
        Controls.Add(_outboundLabel);
        Controls.Add(_outboundComboBox);
        Controls.Add(_urlTestButton);
        Controls.Add(_selectOutboundButton);
        Controls.Add(_urlTestResultListBox);
    }

    private void InitializePhase4Controls()
    {
        ClientSize = new Size(700, 760);
        Text = "OpenMesh Win - Phase 4";

        _trafficTitleLabel.SetBounds(24, 308, 50, 20);
        _trafficValueLabel.SetBounds(78, 308, 592, 20);

        _runtimeTitleLabel.SetBounds(24, 332, 82, 20);
        _runtimeValueLabel.SetBounds(108, 332, 562, 20);

        _connectionTitleLabel.SetBounds(24, 356, 84, 20);

        _connectionSearchTextBox.SetBounds(110, 354, 240, 24);
        _connectionSearchTextBox.PlaceholderText = "filter process/destination/outbound";

        _connectionSortComboBox.SetBounds(360, 354, 110, 24);
        _connectionSortComboBox.Items.AddRange(["last_seen", "download", "upload", "process", "destination", "outbound"]);
        _connectionSortComboBox.SelectedItem = "last_seen";

        _connectionDescCheckBox.SetBounds(478, 356, 58, 20);
        _refreshConnectionsButton.SetBounds(542, 351, 128, 30);

        _connectionListView.SetBounds(24, 386, 646, 160);
        _connectionListView.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
        _connectionListView.Columns.Add("ID", 45);
        _connectionListView.Columns.Add("Process", 115);
        _connectionListView.Columns.Add("Destination", 175);
        _connectionListView.Columns.Add("Proto", 55);
        _connectionListView.Columns.Add("Outbound", 90);
        _connectionListView.Columns.Add("Upload", 75);
        _connectionListView.Columns.Add("Download", 85);
        _connectionListView.Columns.Add("State", 55);

        _closeConnectionButton.SetBounds(542, 552, 128, 30);
        _closeConnectionButton.Enabled = false;

        Controls.Add(_trafficTitleLabel);
        Controls.Add(_trafficValueLabel);
        Controls.Add(_runtimeTitleLabel);
        Controls.Add(_runtimeValueLabel);
        Controls.Add(_connectionTitleLabel);
        Controls.Add(_connectionSearchTextBox);
        Controls.Add(_connectionSortComboBox);
        Controls.Add(_connectionDescCheckBox);
        Controls.Add(_refreshConnectionsButton);
        Controls.Add(_connectionListView);
        Controls.Add(_closeConnectionButton);

        logsTitleLabel.Top = 590;
        logsTextBox.Top = 610;
        logsTextBox.Height = 130;
    }

    private async Task InitialLoadAsync()
    {
        AppendLog("UI started. Entering Phase 4.");
        await RefreshStatusAsync();
        _statusTimer.Start();
    }

    private async Task RunActionAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            AppendLog($"Error: {ex.Message}");
        }
    }

    private async Task StartCoreAsync()
    {
        var result = await _coreProcessManager.EnsureStartedAsync(_coreClient);
        AppendLog(result.Message);
        await RefreshStatusAsync();
    }

    private async Task StartVpnAsync()
    {
        var startCoreResult = await _coreProcessManager.EnsureStartedAsync(_coreClient);
        if (startCoreResult.Started || !startCoreResult.AlreadyRunning)
        {
            AppendLog(startCoreResult.Message);
        }

        if (!startCoreResult.Started && !startCoreResult.AlreadyRunning)
        {
            return;
        }

        var reload = await _coreClient.ReloadAsync();
        AppendLog($"reload -> {(reload.Ok ? "ok" : "failed")}: {reload.Message}");
        if (!reload.Ok)
        {
            await RefreshStatusAsync();
            return;
        }

        var response = await _coreClient.StartVpnAsync();
        AppendLog($"start_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        await RefreshStatusAsync();
    }

    private async Task ReloadConfigAsync()
    {
        var startCoreResult = await _coreProcessManager.EnsureStartedAsync(_coreClient);
        if (startCoreResult.Started || !startCoreResult.AlreadyRunning)
        {
            AppendLog(startCoreResult.Message);
        }

        if (!startCoreResult.Started && !startCoreResult.AlreadyRunning)
        {
            return;
        }

        var response = await _coreClient.ReloadAsync();
        AppendLog($"reload -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        await RefreshStatusAsync();
    }

    private async Task StopVpnAsync()
    {
        var response = await _coreClient.StopVpnAsync();
        AppendLog($"stop_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        await RefreshStatusAsync();
    }

    private async Task UrlTestAsync()
    {
        var group = _groupComboBox.SelectedItem as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(group))
        {
            AppendLog("urltest skipped: no group selected.");
            return;
        }

        var response = await _coreClient.UrlTestAsync(group);
        AppendLog($"urltest -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (response.Ok)
        {
            RenderUrlTestResult(response.Group, response.Delays);
            UpdateStatusUi(response);
        }
    }

    private async Task SelectOutboundAsync()
    {
        var group = _groupComboBox.SelectedItem as string ?? string.Empty;
        var outbound = _outboundComboBox.SelectedItem as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(group) || string.IsNullOrWhiteSpace(outbound))
        {
            AppendLog("select_outbound skipped: group/outbound missing.");
            return;
        }

        var response = await _coreClient.SelectOutboundAsync(group, outbound);
        AppendLog($"select_outbound -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (response.Ok)
        {
            UpdateStatusUi(response);
        }
    }

    private async Task RefreshConnectionsAsync(bool appendLog = false)
    {
        if (!_coreOnline)
        {
            return;
        }

        var search = _connectionSearchTextBox.Text.Trim();
        var sortBy = _connectionSortComboBox.SelectedItem as string ?? "last_seen";
        var descending = _connectionDescCheckBox.Checked;

        var response = await _coreClient.GetConnectionsAsync(search, sortBy, descending);
        if (appendLog)
        {
            AppendLog($"connections -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        }

        if (!response.Ok)
        {
            return;
        }

        UpdateRuntimeUi(response.Runtime);
        RenderConnections(response.Connections);
    }

    private async Task CloseSelectedConnectionAsync()
    {
        if (_connectionListView.SelectedItems.Count == 0)
        {
            AppendLog("close_connection skipped: no selected row.");
            return;
        }

        if (_connectionListView.SelectedItems[0].Tag is not int connectionId || connectionId <= 0)
        {
            AppendLog("close_connection skipped: invalid row.");
            return;
        }

        var response = await _coreClient.CloseConnectionAsync(connectionId);
        AppendLog($"close_connection -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (response.Ok)
        {
            UpdateStatusUi(response);
            await RefreshConnectionsAsync();
        }
    }

    private async Task RefreshStatusAsync()
    {
        try
        {
            var status = await _coreClient.GetStatusAsync();
            UpdateStatusUi(status);
            if (status.CoreRunning)
            {
                await RefreshConnectionsAsync();
            }
        }
        catch (Exception ex)
        {
            MarkCoreOffline();
            AppendLog($"Core offline: {ex.Message}");
        }
    }

    private void UpdateStatusUi(CoreResponse status)
    {
        _coreOnline = status.CoreRunning;
        coreStatusValueLabel.Text = status.CoreRunning ? "Online" : "Offline";
        coreStatusValueLabel.ForeColor = status.CoreRunning ? Color.ForestGreen : Color.Firebrick;

        vpnStatusValueLabel.Text = status.VpnRunning ? "Running" : "Stopped";
        vpnStatusValueLabel.ForeColor = status.VpnRunning ? Color.ForestGreen : Color.DarkGoldenrod;

        startCoreButton.Enabled = !status.CoreRunning;
        startVpnButton.Enabled = status.CoreRunning && !status.VpnRunning;
        stopVpnButton.Enabled = status.CoreRunning && status.VpnRunning;
        reloadConfigButton.Enabled = status.CoreRunning;

        trayStartVpnMenuItem.Enabled = startVpnButton.Enabled;
        trayStopVpnMenuItem.Enabled = stopVpnButton.Enabled;
        trayReloadMenuItem.Enabled = status.CoreRunning;

        trayIcon.Text = status.VpnRunning ? "OpenMesh (VPN Running)" : "OpenMesh (VPN Stopped)";

        profilePathValueLabel.Text = string.IsNullOrWhiteSpace(status.ProfilePath) ? "N/A" : status.ProfilePath;
        injectedRulesValueLabel.Text = status.InjectedRuleCount.ToString();
        configHashValueLabel.Text = string.IsNullOrWhiteSpace(status.LastConfigHash) ? "N/A" : status.LastConfigHash[..Math.Min(24, status.LastConfigHash.Length)];
        UpdateRuntimeUi(status.Runtime);

        if (!status.CoreRunning)
        {
            _lastCoreOnline = false;
            return;
        }

        if (!_lastCoreOnline)
        {
            AppendLog("Core is online.");
        }
        _lastCoreOnline = true;

        if (!string.Equals(_lastConfigHash, status.LastConfigHash, StringComparison.OrdinalIgnoreCase))
        {
            if (!string.IsNullOrWhiteSpace(status.LastConfigHash))
            {
                AppendLog($"config hash updated: {status.LastConfigHash[..Math.Min(12, status.LastConfigHash.Length)]}...");
            }
            _lastConfigHash = status.LastConfigHash;
        }

        if (_lastInjectedRuleCount != status.InjectedRuleCount)
        {
            AppendLog($"injected rules: {status.InjectedRuleCount}");
            _lastInjectedRuleCount = status.InjectedRuleCount;
        }

        if (!string.IsNullOrWhiteSpace(status.LastReloadError))
        {
            AppendLog($"last reload error: {status.LastReloadError}");
        }

        var groups = status.OutboundGroups ?? [];
        BindOutboundGroups(groups);
        var hasGroups = groups.Count > 0;
        _groupComboBox.Enabled = status.CoreRunning && hasGroups;
        _outboundComboBox.Enabled = status.CoreRunning && hasGroups;
        _urlTestButton.Enabled = status.CoreRunning && hasGroups;
        _selectOutboundButton.Enabled = status.CoreRunning && hasGroups && CurrentGroupSelectable();
        _connectionSearchTextBox.Enabled = status.CoreRunning;
        _connectionSortComboBox.Enabled = status.CoreRunning;
        _connectionDescCheckBox.Enabled = status.CoreRunning;
        _refreshConnectionsButton.Enabled = status.CoreRunning;
        _closeConnectionButton.Enabled = status.CoreRunning && _connectionListView.SelectedItems.Count > 0;
    }

    private void MarkCoreOffline()
    {
        _coreOnline = false;
        coreStatusValueLabel.Text = "Offline";
        coreStatusValueLabel.ForeColor = Color.Firebrick;

        vpnStatusValueLabel.Text = "Unknown";
        vpnStatusValueLabel.ForeColor = Color.DarkGray;

        startCoreButton.Enabled = true;
        startVpnButton.Enabled = false;
        stopVpnButton.Enabled = false;
        reloadConfigButton.Enabled = false;

        trayStartVpnMenuItem.Enabled = false;
        trayStopVpnMenuItem.Enabled = false;
        trayReloadMenuItem.Enabled = false;

        trayIcon.Text = "OpenMesh (Core Offline)";

        profilePathValueLabel.Text = "N/A";
        injectedRulesValueLabel.Text = "0";
        configHashValueLabel.Text = "N/A";
        _trafficValueLabel.Text = "Up 0 B/s | Down 0 B/s";
        _runtimeValueLabel.Text = "Memory 0 MB | Threads 0 | Uptime 0s | Conns 0";
        if (_lastCoreOnline)
        {
            AppendLog("Core went offline.");
        }
        _lastCoreOnline = false;
        BindOutboundGroups([]);
        _urlTestResultListBox.Items.Clear();
        _groupComboBox.Enabled = false;
        _outboundComboBox.Enabled = false;
        _urlTestButton.Enabled = false;
        _selectOutboundButton.Enabled = false;
        _connectionSearchTextBox.Enabled = false;
        _connectionSortComboBox.Enabled = false;
        _connectionDescCheckBox.Enabled = false;
        _refreshConnectionsButton.Enabled = false;
        _closeConnectionButton.Enabled = false;
        _connectionListView.Items.Clear();
    }

    private void BindOutboundGroups(List<CoreOutboundGroup> groups)
    {
        _groupByTag.Clear();
        foreach (var group in groups)
        {
            _groupByTag[group.Tag] = group;
        }

        var currentGroup = _groupComboBox.SelectedItem as string ?? string.Empty;
        _groupComboBox.BeginUpdate();
        _groupComboBox.Items.Clear();
        foreach (var tag in groups.Select(g => g.Tag))
        {
            _groupComboBox.Items.Add(tag);
        }
        _groupComboBox.EndUpdate();

        if (!string.IsNullOrWhiteSpace(currentGroup) && _groupByTag.ContainsKey(currentGroup))
        {
            _groupComboBox.SelectedItem = currentGroup;
        }
        else if (_groupComboBox.Items.Count > 0)
        {
            _groupComboBox.SelectedIndex = 0;
        }
        else
        {
            _outboundComboBox.Items.Clear();
        }

        RefreshOutboundSelectionUi();
    }

    private void RefreshOutboundSelectionUi()
    {
        var selectedGroupTag = _groupComboBox.SelectedItem as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(selectedGroupTag) || !_groupByTag.TryGetValue(selectedGroupTag, out var group))
        {
            _outboundComboBox.Items.Clear();
            _selectOutboundButton.Enabled = false;
            return;
        }

        var selectedOutbound = _outboundComboBox.SelectedItem as string ?? string.Empty;
        _outboundComboBox.BeginUpdate();
        _outboundComboBox.Items.Clear();
        foreach (var item in group.Items)
        {
            _outboundComboBox.Items.Add(item.Tag);
        }
        _outboundComboBox.EndUpdate();

        if (!string.IsNullOrWhiteSpace(selectedOutbound) && group.Items.Any(i => i.Tag == selectedOutbound))
        {
            _outboundComboBox.SelectedItem = selectedOutbound;
            _selectOutboundButton.Enabled = _coreOnline && group.Selectable && _outboundComboBox.Items.Count > 0;
            return;
        }

        if (!string.IsNullOrWhiteSpace(group.Selected) && group.Items.Any(i => i.Tag == group.Selected))
        {
            _outboundComboBox.SelectedItem = group.Selected;
            _selectOutboundButton.Enabled = _coreOnline && group.Selectable && _outboundComboBox.Items.Count > 0;
            return;
        }

        if (_outboundComboBox.Items.Count > 0)
        {
            _outboundComboBox.SelectedIndex = 0;
        }

        _selectOutboundButton.Enabled = _coreOnline && group.Selectable && _outboundComboBox.Items.Count > 0;
    }

    private bool CurrentGroupSelectable()
    {
        var selectedGroupTag = _groupComboBox.SelectedItem as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(selectedGroupTag))
        {
            return false;
        }

        return _groupByTag.TryGetValue(selectedGroupTag, out var group) && group.Selectable;
    }

    private void RenderUrlTestResult(string group, Dictionary<string, int> delays)
    {
        _urlTestResultListBox.Items.Clear();
        _urlTestResultListBox.Items.Add($"Group: {group}");
        foreach (var kv in delays.OrderBy(x => x.Value).ThenBy(x => x.Key, StringComparer.OrdinalIgnoreCase))
        {
            _urlTestResultListBox.Items.Add($"{kv.Key,-24} {kv.Value,4} ms");
        }
    }

    private void UpdateRuntimeUi(CoreRuntimeStats runtime)
    {
        _trafficValueLabel.Text = $"Up {FormatRate(runtime.UploadRateBytesPerSec)} | Down {FormatRate(runtime.DownloadRateBytesPerSec)}";
        _runtimeValueLabel.Text = $"Memory {runtime.MemoryMb:F2} MB | Threads {runtime.ThreadCount} | Uptime {runtime.UptimeSeconds}s | Conns {runtime.ConnectionCount}";
    }

    private void RenderConnections(List<CoreConnection> connections)
    {
        var selectedId = _connectionListView.SelectedItems.Count > 0 && _connectionListView.SelectedItems[0].Tag is int id
            ? id
            : -1;

        _connectionListView.BeginUpdate();
        _connectionListView.Items.Clear();
        foreach (var connection in connections)
        {
            var row = new ListViewItem(connection.Id.ToString())
            {
                Tag = connection.Id
            };
            row.SubItems.Add(connection.ProcessName);
            row.SubItems.Add(connection.Destination);
            row.SubItems.Add(connection.Protocol);
            row.SubItems.Add(connection.Outbound);
            row.SubItems.Add(FormatBytes(connection.UploadBytes));
            row.SubItems.Add(FormatBytes(connection.DownloadBytes));
            row.SubItems.Add(connection.State);
            _connectionListView.Items.Add(row);

            if (connection.Id == selectedId)
            {
                row.Selected = true;
            }
        }
        _connectionListView.EndUpdate();

        _closeConnectionButton.Enabled = _coreOnline && _connectionListView.SelectedItems.Count > 0;
    }

    private static string FormatRate(long bytesPerSecond)
    {
        return $"{FormatBytes(bytesPerSecond)}/s";
    }

    private static string FormatBytes(long bytes)
    {
        var value = Math.Max(0, bytes);
        var units = new[] { "B", "KB", "MB", "GB", "TB" };
        var unitIndex = 0;
        var scaled = (double)value;

        while (scaled >= 1024 && unitIndex < units.Length - 1)
        {
            scaled /= 1024;
            unitIndex++;
        }

        return unitIndex == 0 ? $"{value} {units[unitIndex]}" : $"{scaled:F1} {units[unitIndex]}";
    }

    private void ShowMainWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void HideMainWindow()
    {
        Hide();
    }

    private void ExitApplication()
    {
        _exitRequested = true;
        Close();
    }

    private void AppendLog(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        if (logsTextBox.TextLength == 0)
        {
            logsTextBox.Text = line;
        }
        else
        {
            logsTextBox.AppendText(Environment.NewLine + line);
        }

        if (logsTextBox.Lines.Length > 300)
        {
            logsTextBox.Lines = logsTextBox.Lines.Skip(Math.Max(0, logsTextBox.Lines.Length - 300)).ToArray();
        }

        logsTextBox.SelectionStart = logsTextBox.TextLength;
        logsTextBox.ScrollToCaret();
    }
}
