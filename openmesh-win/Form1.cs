using System.Drawing;

namespace OpenMeshWin;

public partial class Form1 : Form
{
    private bool _exitRequested;
    private readonly CoreClient _coreClient = new();
    private readonly CoreProcessManager _coreProcessManager = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 3000 };
    private bool _lastCoreOnline;
    private string _lastConfigHash = string.Empty;
    private int _lastInjectedRuleCount = -1;

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

    private async Task InitialLoadAsync()
    {
        AppendLog("UI started. Entering Phase 2.");
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
    }

    private void MarkCoreOffline()
    {
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
