using System.Drawing;

namespace OpenMeshWin;

public partial class Form1 : Form
{
    private bool _exitRequested;
    private readonly CoreClient _coreClient = new();
    private readonly CoreProcessManager _coreProcessManager = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 3000 };

    public Form1()
    {
        InitializeComponent();

        trayIcon.Icon = SystemIcons.Application;
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();

        trayOpenMenuItem.Click += (_, _) => ShowMainWindow();
        trayStartVpnMenuItem.Click += async (_, _) => await RunActionAsync(StartVpnAsync);
        trayStopVpnMenuItem.Click += async (_, _) => await RunActionAsync(StopVpnAsync);
        trayRefreshMenuItem.Click += async (_, _) => await RunActionAsync(RefreshStatusAsync);
        trayExitMenuItem.Click += (_, _) => ExitApplication();

        startCoreButton.Click += async (_, _) => await RunActionAsync(StartCoreAsync);
        startVpnButton.Click += async (_, _) => await RunActionAsync(StartVpnAsync);
        stopVpnButton.Click += async (_, _) => await RunActionAsync(StopVpnAsync);
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
        AppendLog("UI started. Ready for Phase 1 core integration.");
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

        var response = await _coreClient.StartVpnAsync();
        AppendLog($"start_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
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

        trayStartVpnMenuItem.Enabled = startVpnButton.Enabled;
        trayStopVpnMenuItem.Enabled = stopVpnButton.Enabled;

        trayIcon.Text = status.VpnRunning ? "OpenMesh (VPN Running)" : "OpenMesh (VPN Stopped)";
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

        trayStartVpnMenuItem.Enabled = false;
        trayStopVpnMenuItem.Enabled = false;

        trayIcon.Text = "OpenMesh (Core Offline)";
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
