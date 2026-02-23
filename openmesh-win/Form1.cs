using System.Drawing;

namespace OpenMeshWin;

public partial class Form1 : Form
{
    private bool _exitRequested;
    private readonly CoreClient _coreClient = new();
    private readonly CoreProcessManager _coreProcessManager = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 3000 };
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

        InitializePhase3Controls();

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

        logsTitleLabel.Top = 308;
        logsTextBox.Top = 328;
        logsTextBox.Height = 170;
    }

    private async Task InitialLoadAsync()
    {
        AppendLog("UI started. Entering Phase 3.");
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

    private async Task RefreshStatusAsync()
    {
        try
        {
            var status = await _coreClient.GetStatusAsync();
            UpdateStatusUi(status);
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
            return;
        }

        if (!string.IsNullOrWhiteSpace(group.Selected) && group.Items.Any(i => i.Tag == group.Selected))
        {
            _outboundComboBox.SelectedItem = group.Selected;
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
