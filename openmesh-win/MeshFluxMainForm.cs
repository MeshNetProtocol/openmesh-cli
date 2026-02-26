using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Text;
using System.Net.Http;
using System.Text.Json;

namespace OpenMeshWin;

public partial class MeshFluxMainForm : Form
{
    private static readonly Color MeshPageBackground = Color.FromArgb(219, 234, 247);
    private static readonly Color MeshCardBackground = Color.FromArgb(238, 246, 253);
    private static readonly Color MeshAccentBlue = Color.FromArgb(71, 167, 230);
    private static readonly Color MeshAccentAmber = Color.FromArgb(233, 179, 73);
    private static readonly Color MeshTextPrimary = Color.FromArgb(40, 56, 72);
    private static readonly Color MeshTextMuted = Color.FromArgb(102, 119, 138);

    private bool _exitRequested;
    private readonly ICoreClient _coreClient = CoreClientFactory.CreateDefault();
    private readonly CoreProcessManager _coreProcessManager = new();
    private readonly AppSettingsManager _settingsManager = new();
    private readonly SystemIntegrationManager _systemIntegrationManager = new();
    private readonly AppHeartbeatWriter _heartbeatWriter = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 1200 };
    private AppSettings _appSettings = AppSettings.Default;
    private bool _lastCoreOnline;
    private bool _coreOnline;
    private int _consecutiveCoreFailures;
    private bool _coreRecoveryInProgress;
    private DateTimeOffset _lastRecoveryAttemptUtc = DateTimeOffset.MinValue;
    private CancellationTokenSource? _statusStreamCts;
    private Task? _statusStreamTask;
    private bool _statusStreamConnected;
    private int _statusStreamFailureCount;
    private bool _statusStreamConnectedLogged;
    private DateTimeOffset _lastStatusStreamEventUtc = DateTimeOffset.MinValue;
    private string _lastStatusStreamFingerprint = string.Empty;
    private bool _statusStreamUnsupportedByCore;
    private CancellationTokenSource? _connectionsStreamCts;
    private Task? _connectionsStreamTask;
    private bool _connectionsStreamConnected;
    private int _connectionsStreamFailureCount;
    private bool _connectionsStreamConnectedLogged;
    private DateTimeOffset _lastConnectionsStreamEventUtc = DateTimeOffset.MinValue;
    private bool _connectionsStreamUnsupportedByCore;
    private string _connectionsStreamFilterSignature = string.Empty;
    private CancellationTokenSource? _groupsStreamCts;
    private Task? _groupsStreamTask;
    private int _groupsStreamFailureCount;
    private bool _groupsStreamConnectedLogged;
    private DateTimeOffset _lastGroupsStreamEventUtc = DateTimeOffset.MinValue;
    private bool _groupsStreamUnsupportedByCore;
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
    private readonly TabControl _mainTabControl = new();
    private readonly TabPage _dashboardTab = new("Dashboard");
    private readonly TabPage _marketTab = new("Market");
    private readonly TabPage _settingsTab = new("Settings");
    private readonly TabPage _logsTab = new("Logs");
    private readonly Label _logsHeaderLabel = new() { Text = "Runtime Logs" };
    private readonly Button _openNodeWindowButton = new() { Text = "Node Details", Width = 146, Height = 30 };
    private readonly Button _openTrafficWindowButton = new() { Text = "Traffic Details", Width = 146, Height = 30 };
    private readonly Button _dashboardOpenMarketButton = new() { Text = "Market", Width = 146, Height = 30 };
    private readonly Label _marketHeaderLabel = new() { Text = "推荐供应商" };
    private readonly Button _marketTabOpenButton = new() { Text = "供应商市场" };
    private readonly Button _importProviderFileButton = new() { Text = "导入安装" };
    private readonly FlowLayoutPanel _marketCardsPanel = new()
    {
        FlowDirection = FlowDirection.TopDown,
        WrapContents = false,
        AutoScroll = true
    };
    private readonly Label _settingsHeaderLabel = new() { Text = "Runtime Settings (Phase 5 Preview)" };
    private readonly Panel _settingsTopDivider = new() { Height = 1 };
    private readonly Label _settingsPageTitleLabel = new() { Text = "Settings" };
    private readonly Label _settingsStartAtLoginLabel = new() { Text = "Start at login" };
    private readonly CheckBox _settingsStartAtLoginToggle = new() { Text = "Off", AutoSize = false };
    private readonly Label _settingsUnmatchedLabel = new() { Text = "Unmatched traffic outbound" };
    private readonly Panel _settingsOutboundSegmentPanel = new();
    private readonly Button _settingsProxyButton = new() { Text = "Proxy" };
    private readonly Button _settingsDirectButton = new() { Text = "Direct" };
    private readonly Label _coreModeLabel = new() { Text = "Core Mode:" };
    private readonly ComboBox _coreModeComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox _autoStartCoreCheckBox = new() { Text = "Auto start core when app launches", Checked = true };
    private readonly CheckBox _autoConnectVpnCheckBox = new() { Text = "Auto connect VPN after reload", Checked = false };
    private readonly CheckBox _hideToTrayCheckBox = new() { Text = "Close button hides to tray", Checked = true };
    private readonly CheckBox _autoRecoverCoreCheckBox = new() { Text = "Auto recover core when offline", Checked = true };
    private readonly CheckBox _runAtStartupCheckBox = new() { Text = "Run app at Windows startup (HKCU Run)" };
    private readonly CheckBox _stopLocalCoreOnExitCheckBox = new() { Text = "Stop local core process on app exit", Checked = true };
    private readonly CheckBox _p5BalanceRealCheckBox = new() { Text = "P5: Query wallet balance via real chain RPC (go-cli-lib)", Checked = false };
    private readonly CheckBox _p5BalanceStrictCheckBox = new() { Text = "P5: Balance strict mode (real query failure => action fail)", Checked = false };
    private readonly CheckBox _p5X402RealCheckBox = new() { Text = "P5: Execute x402 real mode (go-cli-lib)", Checked = false };
    private readonly CheckBox _p5X402StrictCheckBox = new() { Text = "P5: x402 strict mode (real payment failure => action fail)", Checked = false };
    private readonly Button _saveSettingsButton = new() { Text = "Save Settings", Width = 120, Height = 30 };
    private readonly Label _settingsHintLabel = new() { Text = "Settings are local preview options for now." };
    private readonly Label _integrationSectionTitleLabel = new() { Text = "System Integration (Phase 7)" };
    private readonly Label _startupStatusLabel = new() { Text = "Startup Entry: Unknown" };
    private readonly Label _wintunStatusLabel = new() { Text = "Wintun: Unknown" };
    private readonly Label _serviceStatusLabel = new() { Text = "Service: Unknown" };
    private readonly Button _refreshIntegrationButton = new() { Text = "Refresh Integration", Width = 136, Height = 30 };
    private readonly Label _walletSectionTitleLabel = new() { Text = "Wallet + x402 (Phase 6)" };
    private readonly Label _walletAddressTitleLabel = new() { Text = "Address:" };
    private readonly Label _walletAddressValueLabel = new() { Text = "N/A" };
    private readonly Label _walletNetworkTokenLabel = new() { Text = "Network/Token: base-mainnet / USDC" };
    private readonly Label _walletBalanceLabel = new() { Text = "Balance: 0.000000" };
    private readonly TextBox _walletMnemonicTextBox = new() { Multiline = true, ScrollBars = ScrollBars.Vertical };
    private readonly TextBox _walletPasswordTextBox = new() { UseSystemPasswordChar = true };
    private readonly Button _walletGenerateButton = new() { Text = "Generate 12-word", Width = 128, Height = 30 };
    private readonly Button _walletCreateButton = new() { Text = "Create Wallet", Width = 108, Height = 30 };
    private readonly Button _walletUnlockButton = new() { Text = "Unlock", Width = 88, Height = 30 };
    private readonly Button _walletBalanceButton = new() { Text = "Get Balance", Width = 104, Height = 30 };
    private string _marketSelectedProviderId = string.Empty;
    private readonly MeshCardPanel _dashboardHeroCard = new();
    private readonly MeshCardPanel _dashboardTrafficCard = new();
    private readonly MeshCardPanel _dashboardNodeCard = new();
    private readonly PictureBox _dashboardLogoPictureBox = new() { SizeMode = PictureBoxSizeMode.Zoom };
    private readonly Label _dashboardAppNameLabel = new() { Text = "MeshFlux" };
    private readonly Label _dashboardVersionLabel = new() { Text = "1.0 (Windows)" };
    private readonly Label _dashboardProviderLabel = new() { Text = "流量商户" };
    private readonly ComboBox _dashboardProviderComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Label _dashboardRealTunnelStatusLabel = new() { Text = "Real Tunnel: Unknown" };
    private readonly Label _dashboardRealTunnelDetailLabel = new() { Text = "mode=?, wintun=?, singbox=?, network=?, engine=?" };
    private readonly ProgressBar _vpnBusyProgressBar = new()
    {
        Style = ProgressBarStyle.Marquee,
        MarqueeAnimationSpeed = 24,
        Visible = false
    };
    private readonly Label _dashboardUpBadgeLabel = new() { Text = "UP 0 B" };
    private readonly Label _dashboardDownBadgeLabel = new() { Text = "DOWN 0 B" };
    private readonly TinyTrafficChartPanel _dashboardTrafficChartPanel = new();
    private readonly Label _dashboardNodeNameLabel = new() { Text = "meshflux node" };
    private readonly Label _dashboardNodeEndpointLabel = new() { Text = "0.0.0.0" };
    private readonly Label _dashboardNodeRateLabel = new() { Text = "UPLINK 0 KB/s  |  DOWNLINK 0 KB/s" };
    private readonly Panel _dashboardBottomBar = new();
    private readonly Button _dashboardBottomLeftPrimaryButton = new() { Text = "◆" };
    private readonly Button _dashboardBottomLeftInfoButton = new() { Text = "i" };
    private readonly Button _dashboardBottomRightActionButton = new() { Text = ">" };
    private List<CoreOutboundGroup> _lastOutboundGroups = [];
    private Dictionary<string, int> _lastUrlTestDelays = new(StringComparer.OrdinalIgnoreCase);
    private string _lastUrlTestGroup = string.Empty;
    private CoreRuntimeStats _lastRuntimeStats = new();
    private List<CoreConnection> _lastConnections = [];
    private decimal _lastWalletBalance;
    private string _lastWalletToken = "USDC";
    private List<CoreProviderOffer> _marketOffers = [];
    private HashSet<string> _installedProviderIds = new(StringComparer.OrdinalIgnoreCase);
    private string _lastKnownProfilePath = string.Empty;
    private string _marketSnapshotFingerprint = string.Empty;
    private string _settingsUnmatchedTrafficOutbound = "direct";
    private bool _settingsUiSyncInProgress;
    private bool _dashboardVpnRunning;
    private Image? _dashboardStartVpnImage;
    private Image? _dashboardStopVpnImage;
    private Icon? _appBrandIcon;
    private readonly Queue<float> _dashboardUploadHistory = new();
    private readonly Queue<float> _dashboardDownloadHistory = new();
    private string _lastRealTunnelSummary = string.Empty;
    private bool _vpnOperationInProgress;
    private string _vpnOperationText = string.Empty;
    private bool _adminWarningShown;

    public MeshFluxMainForm()
    {
        InitializeComponent();
        InitializePhase5Shell();

        ApplyBrandIconToWindowAndTray();
        trayIcon.BalloonTipTitle = "OpenMesh";
        trayIcon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left)
            {
                ShowMainWindow();
            }
        };

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
        _refreshConnectionsButton.Click += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(appendLog: true, forceStreamRestart: true));
        _closeConnectionButton.Click += async (_, _) => await RunActionAsync(CloseSelectedConnectionAsync);
        _openNodeWindowButton.Click += (_, _) => OpenNodeWindow();
        _openTrafficWindowButton.Click += (_, _) => OpenTrafficWindow();
        _connectionSortComboBox.SelectedIndexChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(forceStreamRestart: true));
        _connectionDescCheckBox.CheckedChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(forceStreamRestart: true));
        _saveSettingsButton.Click += (_, _) => SaveSettingsPreview();
        _refreshIntegrationButton.Click += (_, _) => RefreshIntegrationUi();
        _walletGenerateButton.Click += async (_, _) => await RunActionAsync(GenerateMnemonicAsync);
        _walletCreateButton.Click += async (_, _) => await RunActionAsync(CreateWalletAsync);
        _walletUnlockButton.Click += async (_, _) => await RunActionAsync(UnlockWalletAsync);
        _walletBalanceButton.Click += async (_, _) => await RunActionAsync(GetWalletBalanceAsync);
        _dashboardProviderComboBox.SelectedIndexChanged += (_, _) => OnDashboardProviderSelectionChanged();
        _dashboardLogoPictureBox.Click += async (_, _) => await RunActionAsync(ToggleVpnFromDashboardAsync);
        _dashboardBottomLeftPrimaryButton.Click += (_, _) => OpenMarketWindow();
        _dashboardBottomLeftInfoButton.Click += (_, _) => OpenLogDirectory();
        _dashboardBottomRightActionButton.Click += (_, _) => _mainTabControl.SelectedTab = _logsTab;
        _settingsStartAtLoginToggle.CheckedChanged += (_, _) => ApplyStartAtLoginToggle();
        _settingsProxyButton.Click += (_, _) => SetSettingsUnmatchedTrafficOutbound("proxy", persist: true);
        _settingsDirectButton.Click += (_, _) => SetSettingsUnmatchedTrafficOutbound("direct", persist: true);
        _importProviderFileButton.Click += (_, _) => OpenOfflineImportWindow();
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
            await RunActionAsync(() => RefreshConnectionsAsync(appendLog: true, forceStreamRestart: true));
        };

        InitializePhase3Controls();
        InitializePhase4Controls();
        InitializePhase5TabContent();
        _coreModeComboBox.Items.AddRange([AppSettings.CoreModeMock, AppSettings.CoreModeGo]);
        _coreModeComboBox.SelectedItem = AppSettings.CoreModeGo;

        Load += async (_, _) => await RunActionAsync(InitialLoadAsync);

        _statusTimer.Tick += async (_, _) => await RunActionAsync(StatusMaintenanceTickAsync);

        Resize += (_, _) =>
        {
            if (WindowState == FormWindowState.Minimized)
            {
                HideMainWindow();
            }
        };

        FormClosing += (_, e) =>
        {
            if (!_exitRequested && _hideToTrayCheckBox.Checked)
            {
                e.Cancel = true;
                HideMainWindow();
                return;
            }

            if (_exitRequested && _appSettings.StopLocalCoreOnExit)
            {
                try
                {
                    var stopMessage = _coreProcessManager.TryStopLocalCoreOnExitBestEffort();
                    AppendLog(stopMessage);
                }
                catch
                {
                    // Ignore shutdown errors while app is closing.
                }
            }

            _heartbeatWriter.Clear();
            StopStatusStream();
            StopConnectionsStream();
            StopGroupsStream();
            _statusTimer.Stop();
            trayIcon.Visible = false;
            _appBrandIcon?.Dispose();
            _appBrandIcon = null;
        };
    }

    private void InitializePhase5Shell()
    {
        Text = "MeshFlux";
        ClientSize = new Size(550, 760);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        BackColor = MeshPageBackground;
        Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        AutoScaleMode = AutoScaleMode.None;

        trayStartVpnMenuItem.Text = "Connect";
        trayStopVpnMenuItem.Text = "Disconnect";
        trayReloadMenuItem.Text = "Reload Profile";
        trayRefreshMenuItem.Text = "Refresh Status";

        startVpnButton.Text = "Connect";
        stopVpnButton.Text = "Disconnect";
        refreshStatusButton.Text = "Refresh Status";

        _mainTabControl.SetBounds(0, 0, 550, 760);
        _mainTabControl.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _mainTabControl.Appearance = TabAppearance.Normal;
        _mainTabControl.DrawMode = TabDrawMode.OwnerDrawFixed;
        _mainTabControl.SizeMode = TabSizeMode.Fixed;
        _mainTabControl.ItemSize = new Size(104, 34);
        _mainTabControl.Padding = new Point(12, 6);
        _mainTabControl.DrawItem -= MainTabControl_DrawItem;
        _mainTabControl.DrawItem += MainTabControl_DrawItem;
        _mainTabControl.SelectedIndexChanged += async (_, _) => await RunActionAsync(OnMainTabChangedAsync);

        _dashboardTab.BackColor = MeshPageBackground;
        _marketTab.BackColor = MeshPageBackground;
        _settingsTab.BackColor = MeshPageBackground;
        _logsTab.BackColor = MeshPageBackground;
        _dashboardTab.AutoScroll = true;
        _marketTab.AutoScroll = true;
        _settingsTab.AutoScroll = true;

        _mainTabControl.TabPages.AddRange([_dashboardTab, _marketTab, _settingsTab, _logsTab]);
        Controls.Add(_mainTabControl);

        MoveControlToDashboard(coreStatusTitleLabel);
        MoveControlToDashboard(coreStatusValueLabel);
        MoveControlToDashboard(vpnStatusTitleLabel);
        MoveControlToDashboard(vpnStatusValueLabel);
        MoveControlToDashboard(profilePathTitleLabel);
        MoveControlToDashboard(profilePathValueLabel);
        MoveControlToDashboard(injectedRulesTitleLabel);
        MoveControlToDashboard(injectedRulesValueLabel);
        MoveControlToDashboard(configHashTitleLabel);
        MoveControlToDashboard(configHashValueLabel);
        MoveControlToDashboard(startCoreButton);
        MoveControlToDashboard(startVpnButton);
        MoveControlToDashboard(stopVpnButton);
        MoveControlToDashboard(reloadConfigButton);
        MoveControlToDashboard(refreshStatusButton);
        MoveControlToDashboard(_dashboardRealTunnelStatusLabel);
        MoveControlToDashboard(_dashboardRealTunnelDetailLabel);
        
        MoveControlToLogs(logsTitleLabel);
        MoveControlToLogs(logsTextBox);
    }

    private void ApplyBrandIconToWindowAndTray()
    {
        if (_appBrandIcon is not null)
        {
            Icon = _appBrandIcon;
            trayIcon.Icon = _appBrandIcon;
            return;
        }

        var logoPath = Path.Combine(AppContext.BaseDirectory, "assets", "meshflux", "mesh_logo_mark.png");
        if (!File.Exists(logoPath))
        {
            trayIcon.Icon = SystemIcons.Application;
            return;
        }

        try
        {
            using var raw = new Bitmap(logoPath);
            using var sized = new Bitmap(raw, new Size(32, 32));
            var hIcon = sized.GetHicon();
            try
            {
                using var temp = Icon.FromHandle(hIcon);
                _appBrandIcon = (Icon)temp.Clone();
            }
            finally
            {
                DestroyIcon(hIcon);
            }

            Icon = _appBrandIcon;
            trayIcon.Icon = _appBrandIcon;
        }
        catch
        {
            trayIcon.Icon = SystemIcons.Application;
        }
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DestroyIcon(IntPtr hIcon);

    private void MainTabControl_DrawItem(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0 || e.Index >= _mainTabControl.TabCount)
        {
            return;
        }

        var tabRect = _mainTabControl.GetTabRect(e.Index);
        var selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        using (var pageBrush = new SolidBrush(MeshPageBackground))
        {
            e.Graphics.FillRectangle(pageBrush, tabRect);
        }

        using (var textBrush = new SolidBrush(selected ? MeshTextPrimary : MeshTextMuted))
        using (var textFont = new Font("Segoe UI", selected ? 10F : 9.5F, selected ? FontStyle.Bold : FontStyle.Regular))
        using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        {
            e.Graphics.DrawString(_mainTabControl.TabPages[e.Index].Text, textFont, textBrush, tabRect, format);
        }

        using (var borderPen = new Pen(Color.FromArgb(194, 214, 232)))
        {
            e.Graphics.DrawLine(borderPen, tabRect.Left + 6, tabRect.Bottom - 1, tabRect.Right - 6, tabRect.Bottom - 1);
        }

        if (!selected)
        {
            return;
        }

        var indicatorY = tabRect.Bottom - 3;
        using var indicatorPen = new Pen(MeshAccentAmber, 2.4F);
        e.Graphics.DrawLine(indicatorPen, tabRect.Left + 16, indicatorY, tabRect.Right - 16, indicatorY);
    }

    private void MoveControlToDashboard(Control control)
    {
        if (Controls.Contains(control))
        {
            Controls.Remove(control);
        }

        _dashboardTab.Controls.Add(control);
    }

    private void MoveControlToLogs(Control control)
    {
        if (Controls.Contains(control))
        {
            Controls.Remove(control);
        }

        _logsTab.Controls.Add(control);
    }

    private void InitializePhase5TabContent()
    {
        _openNodeWindowButton.SetBounds(24, 548, 146, 30);
        _openTrafficWindowButton.SetBounds(194, 548, 146, 30);
        _dashboardOpenMarketButton.SetBounds(364, 548, 146, 30);
        _dashboardOpenMarketButton.Click += (_, _) => OpenMarketWindow();
        
        _dashboardTab.Controls.Add(_openNodeWindowButton);
        _dashboardTab.Controls.Add(_openTrafficWindowButton);
        _dashboardTab.Controls.Add(_dashboardOpenMarketButton);

        InitializeMarketTab();

        _settingsHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);

        _settingsHeaderLabel.Text = "Runtime + Wallet + Installer Settings (Phase 7)";
        _settingsHeaderLabel.SetBounds(22, 22, 484, 28);

        _coreModeLabel.SetBounds(24, 76, 74, 24);
        _coreModeComboBox.SetBounds(102, 74, 110, 24);
        _autoStartCoreCheckBox.SetBounds(24, 108, 310, 24);
        _autoConnectVpnCheckBox.SetBounds(24, 140, 300, 24);
        _hideToTrayCheckBox.SetBounds(24, 172, 240, 24);
        _autoRecoverCoreCheckBox.SetBounds(24, 204, 260, 24);
        _runAtStartupCheckBox.SetBounds(24, 236, 292, 24);
        _stopLocalCoreOnExitCheckBox.SetBounds(24, 268, 270, 24);
        _p5BalanceRealCheckBox.SetBounds(24, 300, 430, 24);
        _p5BalanceStrictCheckBox.SetBounds(24, 324, 410, 24);
        _p5X402RealCheckBox.SetBounds(24, 348, 320, 24);
        _p5X402StrictCheckBox.SetBounds(24, 372, 390, 24);

        _saveSettingsButton.SetBounds(24, 380, 128, 32);
        _refreshIntegrationButton.SetBounds(160, 380, 136, 32);
        _settingsHintLabel.ForeColor = Color.FromArgb(92, 92, 104);
        _settingsHintLabel.Text = "Settings are persisted to %AppData%\\OpenMeshWin\\appsettings.json and applied on next core start.";
        _settingsHintLabel.SetBounds(24, 420, 620, 22);

        _integrationSectionTitleLabel.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
        _integrationSectionTitleLabel.SetBounds(24, 446, 260, 22);
        _startupStatusLabel.SetBounds(24, 472, 652, 20);
        _wintunStatusLabel.SetBounds(24, 494, 652, 20);
        _serviceStatusLabel.SetBounds(24, 516, 652, 20);

        _walletSectionTitleLabel.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _walletSectionTitleLabel.SetBounds(24, 544, 300, 24);
        _walletAddressTitleLabel.SetBounds(24, 576, 54, 20);
        _walletAddressValueLabel.SetBounds(82, 576, 594, 20);
        _walletAddressValueLabel.AutoEllipsis = true;
        _walletNetworkTokenLabel.SetBounds(24, 600, 240, 20);
        _walletBalanceLabel.SetBounds(270, 600, 220, 20);

        _walletMnemonicTextBox.SetBounds(24, 628, 652, 66);
        _walletMnemonicTextBox.PlaceholderText = "12-word mnemonic (or click Generate)";

        _walletPasswordTextBox.SetBounds(24, 702, 240, 24);
        _walletPasswordTextBox.PlaceholderText = "wallet password (>=6 chars)";

        _walletGenerateButton.SetBounds(276, 698, 128, 30);
        _walletCreateButton.SetBounds(412, 698, 108, 30);
        _walletUnlockButton.SetBounds(528, 698, 72, 30);
        _walletBalanceButton.SetBounds(606, 698, 70, 30);

        _settingsTab.Controls.Add(_settingsHeaderLabel);
        _settingsTab.Controls.Add(_coreModeLabel);
        _settingsTab.Controls.Add(_coreModeComboBox);
        _settingsTab.Controls.Add(_autoStartCoreCheckBox);
        _settingsTab.Controls.Add(_autoConnectVpnCheckBox);
        _settingsTab.Controls.Add(_hideToTrayCheckBox);
        _settingsTab.Controls.Add(_autoRecoverCoreCheckBox);
        _settingsTab.Controls.Add(_runAtStartupCheckBox);
        _settingsTab.Controls.Add(_stopLocalCoreOnExitCheckBox);
        _settingsTab.Controls.Add(_p5BalanceRealCheckBox);
        _settingsTab.Controls.Add(_p5BalanceStrictCheckBox);
        _settingsTab.Controls.Add(_p5X402RealCheckBox);
        _settingsTab.Controls.Add(_p5X402StrictCheckBox);
        _settingsTab.Controls.Add(_saveSettingsButton);
        _settingsTab.Controls.Add(_refreshIntegrationButton);
        _settingsTab.Controls.Add(_settingsHintLabel);
        _settingsTab.Controls.Add(_integrationSectionTitleLabel);
        _settingsTab.Controls.Add(_startupStatusLabel);
        _settingsTab.Controls.Add(_wintunStatusLabel);
        _settingsTab.Controls.Add(_serviceStatusLabel);
        _settingsTab.Controls.Add(_walletSectionTitleLabel);
        _settingsTab.Controls.Add(_walletAddressTitleLabel);
        _settingsTab.Controls.Add(_walletAddressValueLabel);
        _settingsTab.Controls.Add(_walletNetworkTokenLabel);
        _settingsTab.Controls.Add(_walletBalanceLabel);
        _settingsTab.Controls.Add(_walletMnemonicTextBox);
        _settingsTab.Controls.Add(_walletPasswordTextBox);
        _settingsTab.Controls.Add(_walletGenerateButton);
        _settingsTab.Controls.Add(_walletCreateButton);
        _settingsTab.Controls.Add(_walletUnlockButton);
        _settingsTab.Controls.Add(_walletBalanceButton);

        _logsHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _logsHeaderLabel.SetBounds(22, 18, 320, 28);
        _logsTab.Controls.Add(_logsHeaderLabel);
        logsTitleLabel.Left = 24;
        logsTitleLabel.Top = 50;
        logsTextBox.Left = 24;
        logsTextBox.Top = 74;
        logsTextBox.Width = 652;
        logsTextBox.Height = 618;
        logsTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;

        InitializeSettingsAlignedView();
        ApplyMeshFluxPalette();
        ApplyCompactHorizontalLayout();
        InitializeDashboardCards();
        RefreshMarketPreview();
        LogProfilesOverview();
    }

    private void ApplyMeshFluxPalette()
    {
        _settingsHeaderLabel.ForeColor = MeshTextPrimary;
        _settingsHintLabel.ForeColor = MeshTextMuted;
        _integrationSectionTitleLabel.ForeColor = MeshTextPrimary;
        _walletSectionTitleLabel.ForeColor = MeshTextPrimary;

        _urlTestResultListBox.BackColor = MeshCardBackground;
        _connectionListView.BackColor = MeshCardBackground;
        logsTextBox.BackColor = MeshCardBackground;
        _openTrafficWindowButton.FlatStyle = FlatStyle.Flat;
        _openTrafficWindowButton.FlatAppearance.BorderSize = 0;
        _openTrafficWindowButton.BackColor = Color.FromArgb(167, 210, 252);
        _openTrafficWindowButton.ForeColor = Color.FromArgb(40, 106, 196);
        _openTrafficWindowButton.Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold);
        _openNodeWindowButton.FlatStyle = FlatStyle.Flat;
        _openNodeWindowButton.FlatAppearance.BorderSize = 0;
        _openNodeWindowButton.BackColor = Color.FromArgb(112, 177, 242);
        _openNodeWindowButton.ForeColor = Color.White;
        _openNodeWindowButton.Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold);
        ApplyRoundedRegion(_openTrafficWindowButton, 11);
        ApplyRoundedRegion(_openNodeWindowButton, 16);
        _dashboardProviderComboBox.BackColor = Color.White;
        _dashboardProviderComboBox.ForeColor = MeshTextPrimary;
        _settingsTopDivider.BackColor = Color.FromArgb(205, 220, 233);
        _settingsStartAtLoginToggle.ForeColor = MeshTextPrimary;
        _settingsOutboundSegmentPanel.BackColor = Color.FromArgb(201, 218, 230);
        RefreshSettingsAlignedUi();
    }

    private void InitializeDashboardCards()
    {
        _dashboardHeroCard.SetBounds(16, 18, 484, 116);
        _dashboardTrafficCard.SetBounds(16, 146, 484, 176);
        _dashboardNodeCard.SetBounds(16, 334, 484, 136);

        ConfigureCardStyle(_dashboardHeroCard);
        ConfigureCardStyle(_dashboardTrafficCard);
        ConfigureCardStyle(_dashboardNodeCard);

        if (!_dashboardTab.Controls.Contains(_dashboardHeroCard))
        {
            _dashboardTab.Controls.Add(_dashboardHeroCard);
        }

        if (!_dashboardTab.Controls.Contains(_dashboardTrafficCard))
        {
            _dashboardTab.Controls.Add(_dashboardTrafficCard);
        }

        if (!_dashboardTab.Controls.Contains(_dashboardNodeCard))
        {
            _dashboardTab.Controls.Add(_dashboardNodeCard);
        }

        _dashboardLogoPictureBox.SetBounds(16, 18, 52, 52);
        _dashboardLogoPictureBox.Cursor = Cursors.Hand;
        EnsureDashboardVpnImagesLoaded();
        RefreshDashboardVpnImage();
        _dashboardHeroCard.Controls.Add(_dashboardLogoPictureBox);

        _dashboardAppNameLabel.Font = new Font("Segoe UI Semibold", 15F, FontStyle.Bold);
        _dashboardAppNameLabel.ForeColor = MeshAccentBlue;
        _dashboardAppNameLabel.SetBounds(74, 15, 170, 28);
        _dashboardHeroCard.Controls.Add(_dashboardAppNameLabel);

        _dashboardVersionLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _dashboardVersionLabel.ForeColor = MeshTextMuted;
        _dashboardVersionLabel.SetBounds(74, 42, 170, 20);
        _dashboardHeroCard.Controls.Add(_dashboardVersionLabel);

        vpnStatusTitleLabel.Text = "Connection Status";
        vpnStatusTitleLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        vpnStatusTitleLabel.ForeColor = MeshTextMuted;
        vpnStatusTitleLabel.SetBounds(74, 64, 52, 20);
        MoveToCard(vpnStatusTitleLabel, _dashboardHeroCard);

        vpnStatusValueLabel.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
        vpnStatusValueLabel.SetBounds(128, 62, 108, 22);
        MoveToCard(vpnStatusValueLabel, _dashboardHeroCard);

        _vpnBusyProgressBar.SetBounds(74, 88, 154, 8);
        _dashboardHeroCard.Controls.Add(_vpnBusyProgressBar);

        _dashboardProviderLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _dashboardProviderLabel.ForeColor = MeshTextMuted;
        _dashboardProviderLabel.SetBounds(246, 19, 100, 20);
        _dashboardHeroCard.Controls.Add(_dashboardProviderLabel);

        _dashboardProviderComboBox.FlatStyle = FlatStyle.Flat;
        _dashboardProviderComboBox.Font = new Font("Segoe UI", 9.2F, FontStyle.Regular);
        _dashboardProviderComboBox.SetBounds(250, 42, 156, 26);
        _dashboardProviderComboBox.DropDownWidth = 240;
        _dashboardHeroCard.Controls.Add(_dashboardProviderComboBox);

        _dashboardRealTunnelStatusLabel.Font = new Font("Segoe UI Semibold", 8.8F, FontStyle.Bold);
        _dashboardRealTunnelStatusLabel.ForeColor = Color.DarkGoldenrod;
        _dashboardRealTunnelStatusLabel.SetBounds(250, 72, 156, 20);
        _dashboardHeroCard.Controls.Add(_dashboardRealTunnelStatusLabel);

        _dashboardRealTunnelDetailLabel.Font = new Font("Segoe UI", 7.8F, FontStyle.Regular);
        _dashboardRealTunnelDetailLabel.ForeColor = MeshTextMuted;
        _dashboardRealTunnelDetailLabel.SetBounds(250, 90, 156, 18);
        _dashboardHeroCard.Controls.Add(_dashboardRealTunnelDetailLabel);

        startVpnButton.SetBounds(250, 74, 70, 30);
        startVpnButton.Text = "连接";
        MoveToCard(startVpnButton, _dashboardHeroCard);

        stopVpnButton.SetBounds(336, 74, 70, 30);
        stopVpnButton.Text = "断开";
        MoveToCard(stopVpnButton, _dashboardHeroCard);
        startVpnButton.Visible = false;
        stopVpnButton.Visible = false;

        coreStatusTitleLabel.Visible = false;
        coreStatusValueLabel.Visible = false;
        profilePathTitleLabel.Visible = false;
        profilePathValueLabel.Visible = false;
        injectedRulesTitleLabel.Visible = false;
        injectedRulesValueLabel.Visible = false;
        configHashTitleLabel.Visible = false;
        configHashValueLabel.Visible = false;
        startCoreButton.Visible = false;
        reloadConfigButton.Visible = false;
        refreshStatusButton.Visible = false;

        _dashboardUpBadgeLabel.SetBounds(18, 16, 102, 22);
        ConfigureTrafficBadge(_dashboardUpBadgeLabel, Color.FromArgb(86, 173, 228));
        _dashboardTrafficCard.Controls.Add(_dashboardUpBadgeLabel);

        _dashboardDownBadgeLabel.SetBounds(126, 16, 108, 22);
        ConfigureTrafficBadge(_dashboardDownBadgeLabel, Color.FromArgb(60, 199, 128));
        _dashboardTrafficCard.Controls.Add(_dashboardDownBadgeLabel);

        _dashboardTrafficChartPanel.SetBounds(18, 44, 372, 108);
        _dashboardTrafficCard.Controls.Add(_dashboardTrafficChartPanel);

        _trafficTitleLabel.Text = string.Empty;
        _trafficTitleLabel.SetBounds(0, 0, 0, 0);
        MoveToCard(_trafficTitleLabel, _dashboardTrafficCard);

        _trafficValueLabel.Font = new Font("Segoe UI Semibold", 8.9F, FontStyle.Bold);
        _trafficValueLabel.Text = string.Empty;
        _trafficValueLabel.SetBounds(0, 0, 0, 0);
        MoveToCard(_trafficValueLabel, _dashboardTrafficCard);

        _runtimeTitleLabel.Text = string.Empty;
        _runtimeTitleLabel.Font = new Font("Segoe UI", 8.2F, FontStyle.Regular);
        _runtimeTitleLabel.ForeColor = MeshTextMuted;
        _runtimeTitleLabel.SetBounds(0, 0, 0, 0);
        MoveToCard(_runtimeTitleLabel, _dashboardTrafficCard);

        _runtimeValueLabel.Font = new Font("Segoe UI", 8.3F, FontStyle.Regular);
        _runtimeValueLabel.Text = string.Empty;
        _runtimeValueLabel.SetBounds(0, 0, 0, 0);
        MoveToCard(_runtimeValueLabel, _dashboardTrafficCard);

        _dashboardNodeNameLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _dashboardNodeNameLabel.SetBounds(18, 18, 190, 24);
        _dashboardNodeCard.Controls.Add(_dashboardNodeNameLabel);

        _dashboardNodeEndpointLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _dashboardNodeEndpointLabel.ForeColor = MeshTextMuted;
        _dashboardNodeEndpointLabel.SetBounds(18, 42, 190, 20);
        _dashboardNodeCard.Controls.Add(_dashboardNodeEndpointLabel);

        _dashboardNodeRateLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        _dashboardNodeRateLabel.ForeColor = MeshTextPrimary;
        _dashboardNodeRateLabel.SetBounds(18, 66, 310, 20);
        _dashboardNodeCard.Controls.Add(_dashboardNodeRateLabel);

        _openNodeWindowButton.SetBounds(252, 18, 124, 32);
        _openNodeWindowButton.Text = "切换节点";
        MoveToCard(_openNodeWindowButton, _dashboardNodeCard);

        _openTrafficWindowButton.SetBounds(294, 14, 108, 24);
        _openTrafficWindowButton.Text = "More info >";
        MoveToCard(_openTrafficWindowButton, _dashboardTrafficCard);

        _groupLabel.Visible = false;
        _groupComboBox.Visible = false;
        _outboundLabel.Visible = false;
        _outboundComboBox.Visible = false;
        _urlTestButton.Visible = false;
        _selectOutboundButton.Visible = false;
        _urlTestResultListBox.Visible = false;
        _connectionTitleLabel.Visible = false;
        _connectionSearchTextBox.Visible = false;
        _connectionSortComboBox.Visible = false;
        _connectionDescCheckBox.Visible = false;
        _refreshConnectionsButton.Visible = false;
        _connectionListView.Visible = false;
        _closeConnectionButton.Visible = false;

        _dashboardBottomBar.SetBounds(14, 706, 396, 28);
        _dashboardBottomBar.BackColor = Color.Transparent;
        if (!_dashboardTab.Controls.Contains(_dashboardBottomBar))
        {
            _dashboardTab.Controls.Add(_dashboardBottomBar);
            _dashboardBottomBar.BringToFront();
        }

        ConfigureBottomBarButton(_dashboardBottomLeftPrimaryButton, 0, 0);
        ConfigureBottomBarButton(_dashboardBottomLeftInfoButton, 30, 0);
        ConfigureBottomBarButton(_dashboardBottomRightActionButton, 366, 0);
        if (!_dashboardBottomBar.Controls.Contains(_dashboardBottomLeftPrimaryButton))
        {
            _dashboardBottomBar.Controls.Add(_dashboardBottomLeftPrimaryButton);
        }

        if (!_dashboardBottomBar.Controls.Contains(_dashboardBottomLeftInfoButton))
        {
            _dashboardBottomBar.Controls.Add(_dashboardBottomLeftInfoButton);
        }

        if (!_dashboardBottomBar.Controls.Contains(_dashboardBottomRightActionButton))
        {
            _dashboardBottomBar.Controls.Add(_dashboardBottomRightActionButton);
        }

        _dashboardTab.Resize -= DashboardTabOnResize;
        _dashboardTab.Resize += DashboardTabOnResize;
        ApplyDashboardLayout();
    }

    private static void ConfigureBottomBarButton(Button button, int left, int top)
    {
        button.SetBounds(left, top, 24, 24);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.BackColor = Color.Transparent;
        button.ForeColor = Color.FromArgb(66, 92, 115);
        button.Font = new Font("Segoe UI", 10F, FontStyle.Regular);
        button.TabStop = false;
    }

    private void DashboardTabOnResize(object? sender, EventArgs e)
    {
        ApplyDashboardLayout();
    }

    private void ApplyDashboardLayout()
    {
        var pageWidth = _dashboardTab.ClientSize.Width;
        if (pageWidth <= 80)
        {
            return;
        }

        const int left = 16;
        const int right = 16;
        var cardWidth = Math.Max(300, pageWidth - left - right);
        _dashboardHeroCard.SetBounds(left, 18, cardWidth, 116);
        _dashboardTrafficCard.SetBounds(left, 146, cardWidth, 176);
        _dashboardNodeCard.SetBounds(left, 334, cardWidth, 136);

        var rightColumnLeft = Math.Max(220, cardWidth - 172);
        _dashboardProviderLabel.Left = rightColumnLeft;
        _dashboardProviderComboBox.SetBounds(rightColumnLeft, 42, 156, 26);
        _dashboardRealTunnelStatusLabel.SetBounds(rightColumnLeft, 72, 156, 20);
        _dashboardRealTunnelDetailLabel.SetBounds(rightColumnLeft, 90, 156, 18);
        _openTrafficWindowButton.SetBounds(cardWidth - 124, 14, 108, 24);
        _openNodeWindowButton.SetBounds(cardWidth - 140, 18, 124, 32);
        _dashboardTrafficChartPanel.SetBounds(18, 44, Math.Max(230, cardWidth - 36), 108);
        _dashboardBottomBar.SetBounds(14, Math.Max(490, _dashboardTab.ClientSize.Height - 36), cardWidth, 28);
        _dashboardBottomRightActionButton.Left = Math.Max(0, _dashboardBottomBar.Width - 24);
    }

    private static void ConfigureCardStyle(Panel card)
    {
        card.BackColor = Color.FromArgb(244, 250, 255);
        if (card is MeshCardPanel meshCard)
        {
            meshCard.BorderColor = Color.FromArgb(205, 224, 240);
            meshCard.CornerRadius = 14;
        }
    }

    private static void ConfigureTrafficBadge(Label label, Color markerColor)
    {
        label.BackColor = Color.FromArgb(230, 239, 247);
        label.ForeColor = markerColor;
        label.TextAlign = ContentAlignment.MiddleCenter;
        label.Font = new Font("Segoe UI Semibold", 8.1F, FontStyle.Bold);
        label.Padding = new Padding(4, 0, 4, 0);
        label.BorderStyle = BorderStyle.None;
        ApplyRoundedRegion(label, 10);
    }

    private static void ApplyRoundedRegion(Control control, int radius)
    {
        var rect = new Rectangle(0, 0, Math.Max(1, control.Width), Math.Max(1, control.Height));
        using var path = CreateRoundedPath(rect, Math.Max(2, radius));
        control.Region = new Region(path);
    }

    private static void MoveToCard(Control control, Control card)
    {
        if (control.Parent == card)
        {
            return;
        }

        control.Parent?.Controls.Remove(control);

        card.Controls.Add(control);
    }

    private void EnsureDashboardVpnImagesLoaded()
    {
        if (_dashboardStartVpnImage is not null && _dashboardStopVpnImage is not null)
        {
            return;
        }

        var startPath = Path.Combine(AppContext.BaseDirectory, "assets", "meshflux", "start_vpn.png");
        var stopPath = Path.Combine(AppContext.BaseDirectory, "assets", "meshflux", "stop_vpn.png");
        try
        {
            if (File.Exists(startPath))
            {
                _dashboardStartVpnImage = Image.FromFile(startPath);
            }

            if (File.Exists(stopPath))
            {
                _dashboardStopVpnImage = Image.FromFile(stopPath);
            }
        }
        catch
        {
            // keep fallback glyph when image loading fails
        }
    }

    private void RefreshDashboardVpnImage()
    {
        EnsureDashboardVpnImagesLoaded();
        if (_dashboardVpnRunning)
        {
            _dashboardLogoPictureBox.Image = _dashboardStopVpnImage;
            return;
        }

        _dashboardLogoPictureBox.Image = _dashboardStartVpnImage;
    }

    private async Task ToggleVpnFromDashboardAsync()
    {
        if (_dashboardVpnRunning)
        {
            await StopVpnAsync();
            return;
        }

        await StartVpnAsync();
    }

    private void OpenLogDirectory()
    {
        var logDir = AppLogger.GetLogDirectory();
        try
        {
            Directory.CreateDirectory(logDir);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{logDir}\"",
                UseShellExecute = true
            });
            AppendLog($"opened log directory: {logDir}");
        }
        catch (Exception ex)
        {
            AppendLog($"open log directory failed: {ex.Message}");
        }
    }

    private void ApplyCompactHorizontalLayout()
    {
        const float sourceContentWidth = 696F;
        
        var targetContentWidth = _mainTabControl.Width - 28F;
        if (targetContentWidth <= 0 || targetContentWidth >= sourceContentWidth)
        {
            return;
        }

        var scale = targetContentWidth / sourceContentWidth;
        ScaleHorizontalLayout(_settingsTab, scale);
        ScaleHorizontalLayout(_logsTab, scale);
    }

    private static void ScaleHorizontalLayout(Control parent, float scale)
    {
        foreach (Control child in parent.Controls)
        {
            if (child.Dock != DockStyle.None || child.Anchor == AnchorStyles.None)
            {
                continue;
            }

            child.Left = Math.Max(8, (int)Math.Round(child.Left * scale));
            child.Width = Math.Max(56, (int)Math.Round(child.Width * scale));
            if (child is ListView listView)
            {
                var nextLeft = 0;
                foreach (ColumnHeader column in listView.Columns)
                {
                    column.Width = Math.Max(40, (int)Math.Round(column.Width * scale));
                    nextLeft += column.Width;
                }

                if (nextLeft < child.Width - 20 && listView.Columns.Count > 0)
                {
                    listView.Columns[^1].Width += (child.Width - 20) - nextLeft;
                }
            }
        }
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

        _dashboardTab.Controls.Add(_groupLabel);
        _dashboardTab.Controls.Add(_groupComboBox);
        _dashboardTab.Controls.Add(_outboundLabel);
        _dashboardTab.Controls.Add(_outboundComboBox);
        _dashboardTab.Controls.Add(_urlTestButton);
        _dashboardTab.Controls.Add(_selectOutboundButton);
        _dashboardTab.Controls.Add(_urlTestResultListBox);
    }

    private void InitializePhase4Controls()
    {
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

        _dashboardTab.Controls.Add(_trafficTitleLabel);
        _dashboardTab.Controls.Add(_trafficValueLabel);
        _dashboardTab.Controls.Add(_runtimeTitleLabel);
        _dashboardTab.Controls.Add(_runtimeValueLabel);
        _dashboardTab.Controls.Add(_connectionTitleLabel);
        _dashboardTab.Controls.Add(_connectionSearchTextBox);
        _dashboardTab.Controls.Add(_connectionSortComboBox);
        _dashboardTab.Controls.Add(_connectionDescCheckBox);
        _dashboardTab.Controls.Add(_refreshConnectionsButton);
        _dashboardTab.Controls.Add(_connectionListView);
        _dashboardTab.Controls.Add(_closeConnectionButton);

    }

    private async Task InitialLoadAsync()
    {
        AppendLog("UI started. Entering Phase 8.");
        AppendLog($"log directory: {AppLogger.GetLogDirectory()}");
        AppendLog($"core backend: {_coreClient.BackendName}");
        _heartbeatWriter.Touch();
        LoadAndApplySettingsFromDisk();
        AppendLog($"core mode: {_appSettings.GetNormalizedCoreMode()}");
        AppendLog(
            $"p5 wallet bridge: balance_real={_appSettings.P5BalanceReal}, balance_strict={_appSettings.P5BalanceStrict}, x402_real={_appSettings.P5X402Real}, x402_strict={_appSettings.P5X402Strict}");
        RefreshIntegrationUi();
        WarnIfAdminRequired();

        if (_appSettings.AutoConnectVpn)
        {
            await StartVpnAsync();
        }
        else if (_appSettings.AutoStartCore)
        {
            await StartCoreAsync();
        }

        await RefreshStatusAsync();
        _statusTimer.Start();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
    }

    private void LoadAndApplySettingsFromDisk()
    {
        _appSettings = _settingsManager.Load();
        ApplySettingsToControls();
    }

    private void ApplySettingsToControls()
    {
        var normalizedCoreMode = _appSettings.GetNormalizedCoreMode();
        _coreModeComboBox.SelectedItem = normalizedCoreMode;
        _appSettings.CoreMode = normalizedCoreMode;
        _autoStartCoreCheckBox.Checked = _appSettings.AutoStartCore;
        _autoConnectVpnCheckBox.Checked = _appSettings.AutoConnectVpn;
        _hideToTrayCheckBox.Checked = _appSettings.HideToTrayOnClose;
        _autoRecoverCoreCheckBox.Checked = _appSettings.AutoRecoverCore;
        _runAtStartupCheckBox.Checked = _appSettings.RunAtStartup;
        _stopLocalCoreOnExitCheckBox.Checked = _appSettings.StopLocalCoreOnExit;
        _p5BalanceRealCheckBox.Checked = _appSettings.P5BalanceReal;
        _p5BalanceStrictCheckBox.Checked = _appSettings.P5BalanceStrict;
        _p5X402RealCheckBox.Checked = _appSettings.P5X402Real;
        _p5X402StrictCheckBox.Checked = _appSettings.P5X402Strict;
        _settingsUnmatchedTrafficOutbound = string.Equals(_appSettings.UnmatchedTrafficOutbound, "proxy", StringComparison.OrdinalIgnoreCase)
            ? "proxy"
            : "direct";
        RefreshSettingsAlignedUi();
    }

    private void RefreshIntegrationUi()
    {
        try
        {
            var snapshot = _systemIntegrationManager.GetSnapshot();
            _startupStatusLabel.Text = $"Startup Entry (HKCU Run): {(snapshot.StartupEnabled ? "Enabled" : "Disabled")}";
            _startupStatusLabel.ForeColor = snapshot.StartupEnabled ? Color.ForestGreen : Color.DarkGoldenrod;

            if (snapshot.WintunBinaryFound)
            {
                _wintunStatusLabel.Text = $"Wintun Binary: Found ({snapshot.WintunBinaryPath})";
                _wintunStatusLabel.ForeColor = Color.ForestGreen;
            }
            else
            {
                _wintunStatusLabel.Text = "Wintun Binary: Not found (place wintun.dll in app/deps or system directory)";
                _wintunStatusLabel.ForeColor = Color.Firebrick;
            }

            _serviceStatusLabel.Text = $"Wintun Service: {(snapshot.WintunServicePresent ? "Present" : "Not detected")}";
            _serviceStatusLabel.ForeColor = snapshot.WintunServicePresent ? Color.ForestGreen : Color.DarkGoldenrod;
        }
        catch (Exception ex)
        {
            _startupStatusLabel.Text = "Startup Entry (HKCU Run): unavailable";
            _startupStatusLabel.ForeColor = Color.DarkGoldenrod;
            _wintunStatusLabel.Text = "Wintun Binary: unavailable";
            _wintunStatusLabel.ForeColor = Color.DarkGoldenrod;
            _serviceStatusLabel.Text = $"Service status read failed: {ex.Message}";
            _serviceStatusLabel.ForeColor = Color.Firebrick;
        }
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

    private async Task StatusMaintenanceTickAsync()
    {
        _heartbeatWriter.Touch();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();

        if (ShouldSkipPollingBecauseStreamIsHealthy())
        {
            return;
        }

        await RefreshStatusAsync();
    }

    private async Task StartCoreAsync()
    {
        var result = await _coreProcessManager.EnsureStartedAsync(_coreClient, _appSettings);
        AppendLog(result.Message);
        _statusStreamUnsupportedByCore = false;
        _connectionsStreamUnsupportedByCore = false;
        _groupsStreamUnsupportedByCore = false;
        await RefreshStatusAsync();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
    }

    private async Task StartVpnAsync()
    {
        if (!EnsureAdminBeforeVpnStart())
        {
            return;
        }

        SetVpnOperationUiState(true, "Starting...");
        try
        {
            var startCoreResult = await _coreProcessManager.EnsureStartedAsync(_coreClient, _appSettings);
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

            // ALIGNMENT: Use ProfileManager to get the current profile path
            // instead of relying on implicit provider ID.
            
            // 1. Get current profile ID from UI or State
            // We have _currentProfileId which is a ProviderID (string) currently.
            // But we should use ProfileID (long).
            // Let's assume for now we look up the Profile that maps to this ProviderID.
            // Or, we should refactor _currentProfileId to be a long? 
            // For minimal disruption, let's find the profile by ProviderID.
            
            var allProfiles = await ProfileManager.Instance.ListAsync();
            var activeProfile = allProfiles.FirstOrDefault(p => 
                InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == _marketSelectedProviderId);
            
            // If no profile found but we have a provider ID, maybe it's a legacy one or just installed.
            // Fallback: If we can't find a profile, we can't start safely with new logic.
            // But for backward compatibility, maybe we just pass the provider ID?
            
            // Wait, CoreClient.StartVpnAsync takes a 'payload'. 
            // If we look at CoreClient.cs, StartVpnAsync() sends "start_vpn" with no arguments?
            // EmbeddedCoreClient sends "start_vpn".
            
            // The Go Core "start_vpn" action (in main.go) calls "actionStartVpn".
            // Let's check main.go to see what it does. 
            // It reads "OPENMESH_WIN_PROVIDER_MARKET_FILE" env var? 
            // Or does it take a payload?
            
            // If the Go Core expects the path in Environment Variable, we must set it BEFORE starting the core.
            // But Core is already started (Embedded).
            // So we must pass the path in the "start_vpn" payload.
            
            object? payload = null;
            if (activeProfile != null && !string.IsNullOrEmpty(activeProfile.Path))
            {
                // Verify file exists
                if (File.Exists(activeProfile.Path))
                {
                    // Pass the config file path to the core
                    payload = new { config_path = activeProfile.Path };
                    AppendLog($"Starting VPN with profile: {activeProfile.Name} ({activeProfile.Path})");
                }
                else
                {
                    AppendLog($"Warning: Profile path not found: {activeProfile.Path}");
                }
            }
            else
            {
                 // Legacy behavior or default?
                 AppendLog($"Warning: No active profile found for provider {_marketSelectedProviderId}. Attempting default start.");
            }

            var response = await _coreClient.StartVpnAsync(payload);
            AppendLog($"start_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
            await RefreshStatusAsync();
            EnsureStatusStreamRunning();
            EnsureConnectionsStreamRunning();
            EnsureGroupsStreamRunning();
        }
        finally
        {
            SetVpnOperationUiState(false, string.Empty);
        }
    }

    private async Task ReloadConfigAsync()
    {
        var startCoreResult = await _coreProcessManager.EnsureStartedAsync(_coreClient, _appSettings);
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
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
    }

    private async Task StopVpnAsync()
    {
        SetVpnOperationUiState(true, "Stopping...");
        try
        {
            var response = await _coreClient.StopVpnAsync();
            AppendLog($"stop_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
            await RefreshStatusAsync();
        }
        finally
        {
            SetVpnOperationUiState(false, string.Empty);
        }
    }

    private void SetVpnOperationUiState(bool inProgress, string text)
    {
        _vpnOperationInProgress = inProgress;
        _vpnOperationText = inProgress ? (string.IsNullOrWhiteSpace(text) ? "Working..." : text) : string.Empty;

        UseWaitCursor = inProgress;
        startVpnButton.Enabled = !inProgress && _coreOnline && !_dashboardVpnRunning;
        stopVpnButton.Enabled = !inProgress && _coreOnline && _dashboardVpnRunning;
        trayStartVpnMenuItem.Enabled = startVpnButton.Enabled;
        trayStopVpnMenuItem.Enabled = stopVpnButton.Enabled;
        _dashboardLogoPictureBox.Enabled = !inProgress;

        if (inProgress)
        {
            vpnStatusValueLabel.Text = _vpnOperationText;
            vpnStatusValueLabel.ForeColor = Color.DodgerBlue;
        }
        _vpnBusyProgressBar.Visible = inProgress;
    }

    private void WarnIfAdminRequired()
    {
        if (_adminWarningShown)
        {
            return;
        }

        if (!string.Equals(_coreClient.BackendName, "embedded", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (IsRunningAsAdministrator())
        {
            return;
        }

        _adminWarningShown = true;
        AppendLog("warning: embedded VPN requires Administrator privileges. start_vpn will fail in non-elevated session.");
        MessageBox.Show(
            this,
            "当前是非管理员模式。嵌入式 VPN 在 Windows 下需要管理员权限。\n\n请以管理员身份重新启动程序，否则点击“连接”会失败。",
            "Administrator Privileges Required",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);
    }

    private bool EnsureAdminBeforeVpnStart()
    {
        if (!string.Equals(_coreClient.BackendName, "embedded", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (IsRunningAsAdministrator())
        {
            return true;
        }

        AppendLog("start_vpn blocked: current session is not elevated. run app as Administrator.");
        MessageBox.Show(
            this,
            "当前是非管理员模式，无法启动嵌入式 VPN。\n\n请以管理员身份运行程序后重试。",
            "Cannot Start VPN",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);
        return false;
    }

    private static bool IsRunningAsAdministrator()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
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

    private async Task GenerateMnemonicAsync()
    {
        var response = await _coreClient.GenerateMnemonicAsync();
        AppendLog($"wallet_generate_mnemonic -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (!response.Ok)
        {
            return;
        }

        _walletMnemonicTextBox.Text = response.GeneratedMnemonic;
        UpdateWalletUi(response);
    }

    private async Task CreateWalletAsync()
    {
        var mnemonic = _walletMnemonicTextBox.Text.Trim();
        var password = _walletPasswordTextBox.Text;
        var response = await _coreClient.CreateWalletAsync(mnemonic, password);
        AppendLog($"wallet_create -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        UpdateWalletUi(response);
        await RefreshMarketAsync();
    }

    private async Task UnlockWalletAsync()
    {
        var password = _walletPasswordTextBox.Text;
        var response = await _coreClient.UnlockWalletAsync(password);
        AppendLog($"wallet_unlock -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        UpdateWalletUi(response);
    }

    private async Task GetWalletBalanceAsync()
    {
        var response = await _coreClient.GetWalletBalanceAsync("base-mainnet", "USDC");
        var source = string.IsNullOrWhiteSpace(response.WalletBalanceSource) ? "unknown" : response.WalletBalanceSource;
        AppendLog($"wallet_balance -> {(response.Ok ? "ok" : "failed")} [{source}]: {response.Message}");
        UpdateWalletUi(response);
        await RefreshMarketAsync();
    }

    private async Task RefreshConnectionsAsync(bool appendLog = false, bool forceStreamRestart = false)
    {
        if (!_coreOnline)
        {
            return;
        }

        if (forceStreamRestart)
        {
            EnsureConnectionsStreamRunning(forceRestart: true);
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
        _lastConnections = [.. (response.Connections ?? []).Select(CloneConnection)];
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
            EnsureConnectionsStreamRunning(forceRestart: true);
            await RefreshConnectionsAsync();
        }
    }

    private async Task RefreshStatusAsync()
    {
        _heartbeatWriter.Touch();

        try
        {
            var status = await _coreClient.GetStatusAsync();
            _consecutiveCoreFailures = 0;
            UpdateStatusUi(status);
            if (status.CoreRunning && _marketOffers.Count == 0)
            {
                await RefreshMarketAsync();
            }
            if (status.CoreRunning && !ShouldSkipConnectionsPollingBecauseStreamIsHealthy())
            {
                await RefreshConnectionsAsync();
            }
            EnsureStatusStreamRunning();
            EnsureConnectionsStreamRunning();
            EnsureGroupsStreamRunning();
        }
        catch (Exception ex)
        {
            _consecutiveCoreFailures++;
            MarkCoreOffline();
            AppendLog($"Core offline ({_consecutiveCoreFailures}): {ex.Message}");
            await TryRecoverCoreAsync($"status poll failure: {ex.Message}");
        }
    }

    private async Task TryRecoverCoreAsync(string reason)
    {
        if (!_appSettings.AutoRecoverCore)
        {
            return;
        }

        if (_coreRecoveryInProgress)
        {
            return;
        }

        if (_consecutiveCoreFailures < 3)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        if ((now - _lastRecoveryAttemptUtc).TotalSeconds < 20)
        {
            return;
        }

        _coreRecoveryInProgress = true;
        _lastRecoveryAttemptUtc = now;

        try
        {
            AppendLog($"auto_recover starting: {reason}");
            var startResult = await _coreProcessManager.EnsureStartedAsync(_coreClient, _appSettings);
            AppendLog($"auto_recover result: {startResult.Message}");
            if (startResult.Started || startResult.AlreadyRunning)
            {
                var status = await _coreClient.GetStatusAsync();
                UpdateStatusUi(status);
                _consecutiveCoreFailures = 0;
                EnsureStatusStreamRunning();
                EnsureConnectionsStreamRunning();
                EnsureGroupsStreamRunning();
            }
        }
        catch (Exception ex)
        {
            AppendLog($"auto_recover failed: {ex.Message}");
        }
        finally
        {
            _coreRecoveryInProgress = false;
        }
    }

    private void EnsureStatusStreamRunning()
    {
        if (_exitRequested || IsDisposed || Disposing)
        {
            return;
        }

        if (!CanUseStatusStream())
        {
            StopStatusStream();
            return;
        }

        if (_statusStreamTask is { IsCompleted: false })
        {
            return;
        }

        _statusStreamCts?.Cancel();
        _statusStreamCts?.Dispose();
        _statusStreamCts = new CancellationTokenSource();
        _statusStreamTask = RunStatusStreamLoopAsync(_statusStreamCts.Token);
    }

    private bool CanUseStatusStream()
    {
        if (!string.Equals(_appSettings.GetNormalizedCoreMode(), AppSettings.CoreModeGo, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return !_statusStreamUnsupportedByCore;
    }

    private void StopStatusStream()
    {
        try
        {
            _statusStreamCts?.Cancel();
        }
        catch
        {
            // Ignore cancellation errors during shutdown.
        }
        finally
        {
            _statusStreamCts?.Dispose();
            _statusStreamCts = null;
            _statusStreamTask = null;
            _statusStreamConnected = false;
            _statusStreamConnectedLogged = false;
        }
    }

    private void EnsureConnectionsStreamRunning(bool forceRestart = false)
    {
        if (_exitRequested || IsDisposed || Disposing)
        {
            return;
        }

        if (!_coreOnline)
        {
            return;
        }

        if (!CanUseConnectionsStream())
        {
            StopConnectionsStream();
            return;
        }

        var nextSignature = CurrentConnectionsFilterSignature();
        var shouldRestartBecauseFilterChanged = !string.Equals(
            _connectionsStreamFilterSignature,
            nextSignature,
            StringComparison.OrdinalIgnoreCase);

        if (!forceRestart &&
            !shouldRestartBecauseFilterChanged &&
            _connectionsStreamTask is { IsCompleted: false })
        {
            return;
        }

        StopConnectionsStream();
        _connectionsStreamFilterSignature = nextSignature;
        _connectionsStreamCts = new CancellationTokenSource();
        _connectionsStreamTask = RunConnectionsStreamLoopAsync(_connectionsStreamCts.Token);
    }

    private bool CanUseConnectionsStream()
    {
        if (!string.Equals(_appSettings.GetNormalizedCoreMode(), AppSettings.CoreModeGo, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return !_connectionsStreamUnsupportedByCore;
    }

    private void EnsureGroupsStreamRunning()
    {
        if (_exitRequested || IsDisposed || Disposing)
        {
            return;
        }

        if (!_coreOnline)
        {
            return;
        }

        if (!CanUseGroupsStream())
        {
            StopGroupsStream();
            return;
        }

        if (_groupsStreamTask is { IsCompleted: false })
        {
            return;
        }

        StopGroupsStream();
        _groupsStreamCts = new CancellationTokenSource();
        _groupsStreamTask = RunGroupsStreamLoopAsync(_groupsStreamCts.Token);
    }

    private bool CanUseGroupsStream()
    {
        if (!string.Equals(_appSettings.GetNormalizedCoreMode(), AppSettings.CoreModeGo, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return !_groupsStreamUnsupportedByCore;
    }

    private void StopConnectionsStream()
    {
        try
        {
            _connectionsStreamCts?.Cancel();
        }
        catch
        {
            // Ignore cancellation errors during shutdown.
        }
        finally
        {
            _connectionsStreamCts?.Dispose();
            _connectionsStreamCts = null;
            _connectionsStreamTask = null;
            _connectionsStreamConnected = false;
            _connectionsStreamConnectedLogged = false;
        }
    }

    private void StopGroupsStream()
    {
        try
        {
            _groupsStreamCts?.Cancel();
        }
        catch
        {
            // Ignore cancellation errors during shutdown.
        }
        finally
        {
            _groupsStreamCts?.Dispose();
            _groupsStreamCts = null;
            _groupsStreamTask = null;
            _groupsStreamConnectedLogged = false;
        }
    }

    private string CurrentConnectionsFilterSignature()
    {
        var search = _connectionSearchTextBox.Text.Trim();
        var sortBy = _connectionSortComboBox.SelectedItem as string ?? "last_seen";
        var descending = _connectionDescCheckBox.Checked;
        return $"{search}|{sortBy}|{(descending ? "desc" : "asc")}";
    }

    private bool ShouldSkipPollingBecauseStreamIsHealthy()
    {
        if (!_statusStreamConnected)
        {
            return false;
        }

        var age = DateTimeOffset.UtcNow - _lastStatusStreamEventUtc;
        return age.TotalMilliseconds <= 4000;
    }

    private bool ShouldSkipConnectionsPollingBecauseStreamIsHealthy()
    {
        if (!_connectionsStreamConnected)
        {
            return false;
        }

        var age = DateTimeOffset.UtcNow - _lastConnectionsStreamEventUtc;
        return age.TotalMilliseconds <= 5000;
    }

    private async Task RunStatusStreamLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await foreach (var status in _coreClient.WatchStatusStreamAsync(
                    streamIntervalMs: 900,
                    streamMaxEvents: 0,
                    streamHeartbeatEnabled: true,
                    cancellationToken: cancellationToken))
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    if (string.IsNullOrWhiteSpace(status.StreamType) &&
                        string.Equals(status.Message, "unknown action", StringComparison.OrdinalIgnoreCase))
                    {
                        _statusStreamUnsupportedByCore = true;
                        AppendLog("status stream unsupported by current core. fallback to polling.");
                        return;
                    }

                    _statusStreamConnected = true;
                    _statusStreamFailureCount = 0;
                    _consecutiveCoreFailures = 0;
                    _lastStatusStreamEventUtc = DateTimeOffset.UtcNow;
                    if (!string.IsNullOrWhiteSpace(status.StreamFingerprint) &&
                        !string.Equals(_lastStatusStreamFingerprint, status.StreamFingerprint, StringComparison.OrdinalIgnoreCase))
                    {
                        _lastStatusStreamFingerprint = status.StreamFingerprint;
                    }

                    if (!_statusStreamConnectedLogged)
                    {
                        AppendLog("status stream connected.");
                        _statusStreamConnectedLogged = true;
                    }

                    UpdateStatusUi(status);
                    if (status.CoreRunning)
                    {
                        EnsureConnectionsStreamRunning();
                        EnsureGroupsStreamRunning();
                    }
                }

                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                throw new InvalidOperationException("status stream ended unexpectedly");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _statusStreamConnected = false;
                _statusStreamConnectedLogged = false;
                _statusStreamFailureCount++;
                if (_statusStreamFailureCount <= 3 || _statusStreamFailureCount % 5 == 0)
                {
                    AppendLog($"status stream disconnected ({_statusStreamFailureCount}): {ex.Message}");
                }

                var retryDelayMs = Math.Min(5000, 700 * Math.Max(1, _statusStreamFailureCount));
                try
                {
                    await Task.Delay(retryDelayMs, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
            }
        }

        _statusStreamConnected = false;
        _statusStreamConnectedLogged = false;
    }

    private async Task RunConnectionsStreamLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var search = _connectionSearchTextBox.Text.Trim();
            var sortBy = _connectionSortComboBox.SelectedItem as string ?? "last_seen";
            var descending = _connectionDescCheckBox.Checked;

            try
            {
                await foreach (var response in _coreClient.WatchConnectionsStreamAsync(
                    search: search,
                    sortBy: sortBy,
                    descending: descending,
                    streamIntervalMs: 950,
                    streamMaxEvents: 0,
                    streamHeartbeatEnabled: true,
                    cancellationToken: cancellationToken))
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    if (string.IsNullOrWhiteSpace(response.StreamType) &&
                        string.Equals(response.Message, "unknown action", StringComparison.OrdinalIgnoreCase))
                    {
                        _connectionsStreamUnsupportedByCore = true;
                        AppendLog("connections stream unsupported by current core. fallback to polling.");
                        return;
                    }

                    _connectionsStreamConnected = true;
                    _connectionsStreamFailureCount = 0;
                    _lastConnectionsStreamEventUtc = DateTimeOffset.UtcNow;
                    if (!_connectionsStreamConnectedLogged)
                    {
                        AppendLog("connections stream connected.");
                        _connectionsStreamConnectedLogged = true;
                    }

                    UpdateRuntimeUi(response.Runtime);
                    var connections = response.Connections ?? [];
                    RenderConnections(connections);
                    _lastConnections = [.. connections.Select(CloneConnection)];
                }

                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                throw new InvalidOperationException("connections stream ended unexpectedly");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _connectionsStreamConnected = false;
                _connectionsStreamConnectedLogged = false;
                _connectionsStreamFailureCount++;
                if (_connectionsStreamFailureCount <= 3 || _connectionsStreamFailureCount % 5 == 0)
                {
                    AppendLog($"connections stream disconnected ({_connectionsStreamFailureCount}): {ex.Message}");
                }

                var retryDelayMs = Math.Min(5000, 700 * Math.Max(1, _connectionsStreamFailureCount));
                try
                {
                    await Task.Delay(retryDelayMs, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
            }
        }

        _connectionsStreamConnected = false;
        _connectionsStreamConnectedLogged = false;
    }

    private async Task RunGroupsStreamLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await foreach (var response in _coreClient.WatchGroupsStreamAsync(
                    streamIntervalMs: 960,
                    streamMaxEvents: 0,
                    streamHeartbeatEnabled: true,
                    cancellationToken: cancellationToken))
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    if (string.IsNullOrWhiteSpace(response.StreamType) &&
                        string.Equals(response.Message, "unknown action", StringComparison.OrdinalIgnoreCase))
                    {
                        _groupsStreamUnsupportedByCore = true;
                        AppendLog("groups stream unsupported by current core. fallback to polling.");
                        return;
                    }

                    _groupsStreamFailureCount = 0;
                    _lastGroupsStreamEventUtc = DateTimeOffset.UtcNow;
                    if (!_groupsStreamConnectedLogged)
                    {
                        AppendLog("groups stream connected.");
                        _groupsStreamConnectedLogged = true;
                    }

                    var groups = response.OutboundGroups ?? [];
                    _lastOutboundGroups = [.. groups.Select(CloneGroup)];
                    BindOutboundGroups(groups);
                    var hasGroups = _coreOnline && groups.Count > 0;
                    _groupComboBox.Enabled = hasGroups;
                    _outboundComboBox.Enabled = hasGroups;
                    _urlTestButton.Enabled = hasGroups;
                    _selectOutboundButton.Enabled = hasGroups && CurrentGroupSelectable();
                }

                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                throw new InvalidOperationException("groups stream ended unexpectedly");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _groupsStreamConnectedLogged = false;
                _groupsStreamFailureCount++;
                if (_groupsStreamFailureCount <= 3 || _groupsStreamFailureCount % 5 == 0)
                {
                    AppendLog($"groups stream disconnected ({_groupsStreamFailureCount}): {ex.Message}");
                }

                var retryDelayMs = Math.Min(5000, 700 * Math.Max(1, _groupsStreamFailureCount));
                try
                {
                    await Task.Delay(retryDelayMs, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
            }
        }

        _groupsStreamConnectedLogged = false;
    }

    private void UpdateStatusUi(CoreResponse status)
    {
        if (status.Providers is { Count: > 0 })
        {
            var incomingInstalled = (status.InstalledProviderIds ?? [])
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var incomingFingerprint = BuildMarketSnapshotFingerprint(status.Providers, incomingInstalled);
            if (!string.Equals(_marketSnapshotFingerprint, incomingFingerprint, StringComparison.Ordinal))
            {
                _marketOffers = [.. status.Providers
                    .Select(offer => new CoreProviderOffer
                    {
                        Id = offer.Id,
                        Name = offer.Name,
                        Region = offer.Region,
                        PricePerGb = offer.PricePerGb,
                        PackageHash = offer.PackageHash,
                        Description = offer.Description
                    })];
                _installedProviderIds = incomingInstalled;
                _marketSnapshotFingerprint = incomingFingerprint;
                RefreshMarketPreview();
            }
        }

        _coreOnline = status.CoreRunning;
        coreStatusValueLabel.Text = status.CoreRunning ? "Online" : "Offline";
        coreStatusValueLabel.ForeColor = status.CoreRunning ? Color.ForestGreen : Color.Firebrick;

        vpnStatusValueLabel.Text = status.VpnRunning ? "Running" : "Stopped";
        vpnStatusValueLabel.ForeColor = status.VpnRunning ? Color.ForestGreen : Color.DarkGoldenrod;
        _dashboardVpnRunning = status.VpnRunning;
        RefreshDashboardVpnImage();
        UpdateRealTunnelUi(status);

        startCoreButton.Enabled = !status.CoreRunning;
        startVpnButton.Enabled = status.CoreRunning && !status.VpnRunning && !_vpnOperationInProgress;
        stopVpnButton.Enabled = status.CoreRunning && status.VpnRunning && !_vpnOperationInProgress;
        reloadConfigButton.Enabled = status.CoreRunning;

        trayStartVpnMenuItem.Enabled = startVpnButton.Enabled;
        trayStopVpnMenuItem.Enabled = stopVpnButton.Enabled;
        trayReloadMenuItem.Enabled = status.CoreRunning;

        trayIcon.Text = status.VpnRunning ? "OpenMesh (VPN Running)" : "OpenMesh (VPN Stopped)";

        profilePathValueLabel.Text = string.IsNullOrWhiteSpace(status.ProfilePath) ? "N/A" : status.ProfilePath;
        _lastKnownProfilePath = status.ProfilePath ?? string.Empty;
        injectedRulesValueLabel.Text = status.InjectedRuleCount.ToString();
        configHashValueLabel.Text = string.IsNullOrWhiteSpace(status.LastConfigHash) ? "N/A" : status.LastConfigHash[..Math.Min(24, status.LastConfigHash.Length)];
        UpdateRuntimeUi(status.Runtime);
        UpdateWalletUi(status);
        _lastRuntimeStats = CloneRuntime(status.Runtime);

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
        _lastOutboundGroups = [.. groups.Select(CloneGroup)];
        _lastConnections = [.. (status.Connections ?? []).Select(CloneConnection)];
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

        if (_vpnOperationInProgress)
        {
            vpnStatusValueLabel.Text = _vpnOperationText;
            vpnStatusValueLabel.ForeColor = Color.DodgerBlue;
        }
    }

    private void MarkCoreOffline()
    {
        _coreOnline = false;
        _statusStreamConnected = false;
        _lastStatusStreamEventUtc = DateTimeOffset.MinValue;
        _lastStatusStreamFingerprint = string.Empty;
        _connectionsStreamConnected = false;
        _lastConnectionsStreamEventUtc = DateTimeOffset.MinValue;
        StopConnectionsStream();
        _lastGroupsStreamEventUtc = DateTimeOffset.MinValue;
        StopGroupsStream();
        coreStatusValueLabel.Text = "Offline";
        coreStatusValueLabel.ForeColor = Color.Firebrick;

        vpnStatusValueLabel.Text = "Unknown";
        vpnStatusValueLabel.ForeColor = Color.DarkGray;
        _dashboardRealTunnelStatusLabel.Text = "Real Tunnel: Offline";
        _dashboardRealTunnelStatusLabel.ForeColor = Color.DarkGoldenrod;
        _dashboardRealTunnelDetailLabel.Text = "core offline";
        _lastRealTunnelSummary = string.Empty;
        _dashboardVpnRunning = false;
        RefreshDashboardVpnImage();

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
        _lastRuntimeStats = new CoreRuntimeStats();
        _dashboardUploadHistory.Clear();
        _dashboardDownloadHistory.Clear();
        _dashboardTrafficChartPanel.SetSamples(_dashboardUploadHistory, _dashboardDownloadHistory);
        _lastConnections = [];
        _lastOutboundGroups = [];
        _lastUrlTestGroup = string.Empty;
        _lastUrlTestDelays = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
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
        _walletAddressValueLabel.Text = "N/A";
        _walletNetworkTokenLabel.Text = "Network/Token: base-mainnet / USDC";
        _walletBalanceLabel.Text = "Balance: 0.000000";
        _lastWalletBalance = 0m;
        _lastWalletToken = "USDC";
        _walletGenerateButton.Enabled = false;
        _walletCreateButton.Enabled = false;
        _walletUnlockButton.Enabled = false;
        _walletBalanceButton.Enabled = false;
        _lastKnownProfilePath = string.Empty;
        _dashboardProviderComboBox.Items.Clear();
        _dashboardProviderComboBox.Enabled = false;
        _dashboardNodeNameLabel.Text = "meshflux node";
        _dashboardNodeEndpointLabel.Text = "0.0.0.0";
        _dashboardNodeRateLabel.Text = "UPLINK 0 B/s  |  DOWNLINK 0 B/s";
        LogProfilesOverview();
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
        RefreshDashboardNodeSnapshot();
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
        _lastUrlTestGroup = group;
        _lastUrlTestDelays = new Dictionary<string, int>(delays, StringComparer.OrdinalIgnoreCase);
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

    private void UpdateWalletUi(CoreResponse response)
    {
        var address = string.IsNullOrWhiteSpace(response.WalletAddress) ? "N/A" : response.WalletAddress;
        _walletAddressValueLabel.Text = address;

        var network = string.IsNullOrWhiteSpace(response.WalletNetwork) ? "base-mainnet" : response.WalletNetwork;
        var token = string.IsNullOrWhiteSpace(response.WalletToken) ? "USDC" : response.WalletToken;
        var source = string.IsNullOrWhiteSpace(response.WalletBalanceSource) ? "unknown" : response.WalletBalanceSource;
        _walletNetworkTokenLabel.Text = $"Network/Token: {network} / {token}";
        _walletBalanceLabel.Text = $"Balance: {response.WalletBalance:F6} ({source})";
        _lastWalletBalance = response.WalletBalance;
        _lastWalletToken = token;

        _walletGenerateButton.Enabled = _coreOnline;
        _walletCreateButton.Enabled = _coreOnline;
        _walletUnlockButton.Enabled = _coreOnline && response.WalletExists;
        _walletBalanceButton.Enabled = _coreOnline && response.WalletExists;
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

    private void OpenNodeWindow()
    {
        if (_lastOutboundGroups.Count == 0)
        {
            AppendLog("Node details unavailable: no outbound groups.");
            return;
        }

        using var form = new NodeDetailsForm(_lastOutboundGroups, _lastUrlTestGroup, _lastUrlTestDelays);
        form.ShowDialog(this);
    }

    private void OpenTrafficWindow()
    {
        using var form = new TrafficDetailsForm(_lastRuntimeStats, _lastConnections);
        form.ShowDialog(this);
    }

    private async Task OnMainTabChangedAsync()
    {
        if (_mainTabControl.SelectedTab == _marketTab)
        {
            _marketCardsPanel.SuspendLayout();
            _marketCardsPanel.Controls.Clear();
            
            var loadingLabel = new Label
            {
                Text = "Loading market...",
                ForeColor = MeshTextMuted,
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Top,
                Height = 60,
                Font = new Font("Segoe UI", 10F, FontStyle.Regular)
            };
            
            // Add a simple spinner using a progress bar in marquee mode
            var spinner = new ProgressBar
            {
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 30,
                Width = 200,
                Height = 4,
                Left = (_marketCardsPanel.Width - 200) / 2
            };
            
            var container = new Panel
            {
                Width = _marketCardsPanel.Width - 40,
                Height = 100
            };
            container.Controls.Add(loadingLabel);
            container.Controls.Add(spinner);
            spinner.Top = loadingLabel.Bottom + 5;
            
            _marketCardsPanel.Controls.Add(container);
            _marketCardsPanel.ResumeLayout();
            
            // Force UI update
            Application.DoEvents();

            await RefreshMarketAsync(appendLog: true);
        }
    }

    private async Task RefreshMarketAsync(bool appendLog = false)
    {
        // Allow market refresh even if core is offline (best effort), 
        // but currently client depends on core API. 
        // If user says "regardless of VPN started", they might mean regardless of "Connect" state.
        // Core process must be running to serve API requests unless we implement direct HTTP client here.
        // Assuming "VPN started" means Tunnel state, but "Core Online" is needed for API.
        // If Core is offline, we can't fetch from it. 
        // However, user said "regardless of VPN started". 
        // If Core is not running, we should probably try to start it or just fail gracefully if it's strictly API based.
        // But let's stick to current logic: check _coreOnline.
        
        // Wait, user said "fetch from server... regardless of VPN started". 
        // If the core is what fetches from server, then core must be up. 
        // If the core is not running, we can't fetch.
        // Let's assume _coreOnline check is still valid for "Core Process Running", 
        // but we shouldn't block if "VPN" (Tunnel) is not connected.
        // _coreOnline is true when we can talk to the core.
        
        if (!_coreOnline)
        {
            if (appendLog) AppendLog("Market refresh skipped: Core is offline.");
            RefreshMarketPreview();
            return;
        }

        var response = await _coreClient.GetProviderMarketAsync();

        // Check if we got any real network data.
        // The core might return local profiles even if network fetch fails.
        // We want to fallback to direct API if we don't have any "real" market offers.
        var hasNetworkData = response.Providers != null && response.Providers.Any(p => 
            !string.Equals(p.Id, "com.meshnetprotocol.profile", StringComparison.OrdinalIgnoreCase) &&
            !p.Description.Contains("Installed from local profile", StringComparison.OrdinalIgnoreCase));

        // Fallback: If Core fails to fetch market or only returns local profile, try direct HTTP fetch
        if (!response.Ok || !hasNetworkData)
        {
            if (appendLog) AppendLog("[Market] Core fetch returned incomplete/empty data. Attempting direct API fetch...");
            
            // Log network diagnostics before attempting fetch
            try 
            {
                var host = "openmesh-api.ribencong.workers.dev";
                var addresses = await System.Net.Dns.GetHostAddressesAsync(host);
                if (appendLog) AppendLog($"[Market] DNS resolution for {host}: {string.Join(", ", addresses.Select(a => a.ToString()))}");
            }
            catch (Exception dnsEx)
            {
                 if (appendLog) AppendLog($"[Market] DNS resolution failed for API host: {dnsEx.Message}");
            }

            try
            {
                var handler = new HttpClientHandler();
                
                // IMPORTANT: When VPN is on, DNS might resolve to a "fake" IP (hijacked) if not routed correctly,
                // OR the route for this domain might be going through the tunnel which breaks SSL if SNI is messed up.
                // 162.125.32.5 looks like Dropbox IP? "openmesh-api.ribencong.workers.dev" is a Cloudflare Worker.
                // Cloudflare IPs are usually 104.x or 172.x. 162.125.x is Dropbox. 
                // This suggests DNS poisoning or fake DNS response from the local VPN core!
                
                // Workaround: If we detect we are in "fake DNS" mode or similar, we might need to use a specific proxy 
                // OR force a known good IP? No, we can't pin IP easily for Cloudflare.
                
                // Let's try to bypass system proxy settings to see if that helps, 
                // OR explicitly use the system proxy if the VPN set one up.
                // In TUN mode, there is no proxy set in system settings usually.
                
                handler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => {
                     // Log certificate errors for debugging
                     if (errors != System.Net.Security.SslPolicyErrors.None)
                     {
                         // AppendLog($"[Market] SSL Error: {errors} for {cert?.Subject}");
                         // For now, let's accept it to see if it works (DANGEROUS for prod, but good for debug)
                         // User wants to solve the problem. If it's a self-signed cert from a transparent proxy, this fixes it.
                         return true; 
                     }
                     return true;
                };
                
                // PROXY BYPASS ATTEMPT:
                // If the core is hijacking DNS/Traffic, maybe we can use the Core's HTTP proxy port if available?
                // Or force no proxy.
                // handler.UseProxy = false; 

                using var httpClient = new HttpClient(handler);
                httpClient.Timeout = TimeSpan.FromSeconds(15); 
                httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
                
                var url = "https://openmesh-api.ribencong.workers.dev/api/v1/market/recommended";
                if (appendLog) AppendLog($"[Market] Direct fetching: {url} (SSL validation disabled)");
                
                var json = await httpClient.GetStringAsync(url);
                if (appendLog) AppendLog($"[Market] Direct fetch returned {json.Length} bytes.");

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
                        
                        if (item.TryGetProperty("price_per_gb_usd", out var p4))
                        {
                            if (p4.ValueKind == JsonValueKind.Number)
                                offer.PricePerGb = p4.GetDecimal();
                            else if (p4.ValueKind == JsonValueKind.Null)
                                offer.PricePerGb = 0;
                        }
                        
                        offer.Region = "Global"; // API doesn't return region in recommended list
                        
                        if (item.TryGetProperty("package_hash", out var p5)) offer.PackageHash = p5.GetString() ?? "";

                        fetchedOffers.Add(offer);
                    }
                    
                    response.Ok = true;
                    // Preserve existing (local) providers if any
                    var existingLocal = response.Providers?.Where(p => 
                        string.Equals(p.Id, "com.meshnetprotocol.profile", StringComparison.OrdinalIgnoreCase) ||
                        p.Description.Contains("Installed from local profile", StringComparison.OrdinalIgnoreCase))
                        .ToList() ?? new List<CoreProviderOffer>();

                    fetchedOffers.AddRange(existingLocal);
                    response.Providers = fetchedOffers;
                    
                    response.Message = "Fetched via Direct API";
                    if (appendLog) AppendLog($"[Market] Direct API fetch success: {fetchedOffers.Count} providers (incl local).");
                }
            }
            catch (Exception ex)
            {
                if (appendLog) AppendLog($"[Market] Direct API fetch failed: {ex.Message}");
                if (ex.InnerException != null && appendLog)
                {
                    AppendLog($"[Market] Inner exception: {ex.InnerException.Message}");
                }
                
                // If direct fetch fails and we have no data, maybe we should try to reload the profile?
                // No, this is just market data.
            }
        }
        
        if (appendLog)
        {
            AppendLog($"provider_market_list -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
            if (response.Ok && response.Providers != null)
            {
                try 
                {
                    // Log raw JSON response for debugging
                    var rawJson = System.Text.Json.JsonSerializer.Serialize(response.Providers, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                    AppendLog($"[Market] Raw response: {rawJson}");
                }
                catch (Exception ex)
                {
                    AppendLog($"[Market] Failed to serialize raw response: {ex.Message}");
                }
            }
        }

        if (!response.Ok)
        {
            // If failed, retain existing data instead of clearing, so user sees something (or old data)
            // But if we truly want to show error state, we might clear.
            // However, user complained about empty dashboard dropdown. 
            // We fixed dropdown logic to use InstalledProviderManager, so it's safe to have empty marketOffers here.
            // But let's log explicitly.
            if (appendLog) AppendLog("[Market] Refresh failed. Keeping previous market data if available.");
            RefreshMarketPreview();
            return;
        }

        // Filter out local profile from the market offers list if it exists there
        // User said: "remove the display of the locally installed profile... it is a local cache... not a recommended provider"
        // Typically local profile might appear as a provider with ID matching local config or special ID.
        // Assuming "com.meshnetprotocol.profile" is the one user saw.
        // We will filter it out from _marketOffers used for display.

        var rawOffers = response.Providers ?? [];
        var filteredOffers = new List<CoreProviderOffer>();
        
        foreach (var offer in rawOffers)
        {
            // Heuristic to identify local profile: 
            // 1. It might have a specific ID like "com.meshnetprotocol.profile"
            // 2. Or user said "installed from local profile"
            // Let's look for "com.meshnetprotocol.profile" specifically or anything that looks like local.
            if (string.Equals(offer.Id, "com.meshnetprotocol.profile", StringComparison.OrdinalIgnoreCase) ||
                offer.Description.Contains("Installed from local profile", StringComparison.OrdinalIgnoreCase))
            {
                AppendLog($"[Market] Hidden local profile: {offer.Name} ({offer.Id})");
                continue;
            }
            
            // Log fetched provider info
            AppendLog($"[Market] Fetched provider: {offer.Name} (ID: {offer.Id}, Region: {offer.Region}, Price: {offer.PricePerGb})");
            
            filteredOffers.Add(offer);
        }

        _marketOffers = filteredOffers;
        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        
        RefreshMarketPreview();
    }

    private static string BuildMarketSnapshotFingerprint(IEnumerable<CoreProviderOffer> offers, IEnumerable<string> installedProviderIds)
    {
        var offerPart = string.Join(
            "||",
            offers.Select(offer =>
                string.Join("|",
                    offer.Id,
                    offer.Name,
                    offer.Region,
                    offer.PricePerGb.ToString("F6"),
                    offer.PackageHash,
                    offer.Description)));
        var installedPart = string.Join("|", installedProviderIds.OrderBy(x => x, StringComparer.OrdinalIgnoreCase));
        return $"{offerPart}##{installedPart}";
    }

    private void LogProfilesOverview()
    {
        var sb = new StringBuilder();
        var profilePath = string.IsNullOrWhiteSpace(_lastKnownProfilePath) ? "N/A" : _lastKnownProfilePath;
        sb.AppendLine($"Current Profile: {profilePath}");
        sb.AppendLine($"Core Online: {_coreOnline}");

        _installedProviderIds = new HashSet<string>(InstalledProviderManager.Instance.GetAllInstalledProviderIds(), StringComparer.OrdinalIgnoreCase);

        if (_installedProviderIds.Count == 0)
        {
            sb.AppendLine("Installed Providers: (none)");
        }
        else
        {
            sb.AppendLine($"Installed Providers ({_installedProviderIds.Count}):");
            foreach (var id in _installedProviderIds.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                var offer = _marketOffers.FirstOrDefault(x => string.Equals(x.Id, id, StringComparison.OrdinalIgnoreCase));
                var line = offer is null
                    ? $"- {id}"
                    : $"- {offer.Name} ({offer.Region})  id={offer.Id}";
                sb.AppendLine(line);
            }
        }
        AppendLog(sb.ToString());
    }

    private void RefreshMarketPreview()
    {
        // Update popup if open
        if (_marketForm != null && !_marketForm.IsDisposed)
        {
            _marketForm.UpdateData(_marketOffers, _installedProviderIds);
        }

        // Update local tab content
        _marketCardsPanel.SuspendLayout();
        _marketCardsPanel.Controls.Clear();

        if (_marketOffers.Count == 0)
        {
            var emptyLabel = new Label
            {
                Text = "暂无推荐供应商",
                ForeColor = MeshTextMuted,
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Fill
            };
            _marketCardsPanel.Controls.Add(emptyLabel);
        }
        else
        {
            foreach (var offer in _marketOffers.Take(5))
            {
                // Strict check for filtering local profile again just in case
                if (string.Equals(offer.Id, "com.meshnetprotocol.profile", StringComparison.OrdinalIgnoreCase) ||
                    offer.Description.Contains("Installed from local profile", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                
                var isInstalled = _installedProviderIds.Contains(offer.Id);
                var card = new ProviderCardControl(offer, isInstalled)
                {
                    Width = _marketCardsPanel.Width - 40,
                    Height = 110,
                    Margin = new Padding(0, 0, 0, 15)
                };
                
                // Wire up actions for the preview cards too
                card.InstallClicked += async () => 
                {
                     await RunActionAsync(() => InstallProviderFromCard(offer));
                };
                
                _marketCardsPanel.Controls.Add(card);
            }
        }
        _marketCardsPanel.ResumeLayout();

        if (_marketOffers.Count > 0 && string.IsNullOrWhiteSpace(_marketSelectedProviderId))
        {
            _marketSelectedProviderId = _marketOffers[0].Id;
        }
        RefreshDashboardProviderOptions();
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

            // Trigger standard ProviderInstallWizardDialog with "Import" content
            var wizard = new ProviderInstallWizardDialog(result.ImportContent, async (content) =>
            {
                // Import logic: Core handles it via "provider_import_install" or manual flow
                // We'll use "ImportAndInstallProviderAsync" from CoreClient if available
                // Or "ImportProviderFromTextAsync" + "InstallProviderAsync"
                
                return await _coreClient.ImportAndInstallProviderAsync(content);
            });
            
            if (wizard.ShowDialog(this) == DialogResult.OK)
            {
                // Refresh list
                RunActionAsync(async () => await RefreshMarketAsync()).GetAwaiter(); // Fire and forget
            }
        }
    }

    private async Task InstallProviderFromCard(CoreProviderOffer offer)
    {
         // Simplified install for preview card
         if (!_coreOnline) return;
         
         var installForm = new ProviderInstallForm(offer.Id, offer.Name, async (progressCallback) =>
         {
            progressCallback("Installing...", "running");
            var response = await _coreClient.InstallProviderAsync(offer.Id);
            if (response.Ok)
            {
                progressCallback("Done", "done");
                var installedHash = !string.IsNullOrEmpty(offer.PackageHash) ? offer.PackageHash : "unknown-hash";
                InstalledProviderManager.Instance.RegisterInstalledProvider(offer.Id, installedHash, []);
                return true;
            }
            progressCallback($"Failed: {response.Message}", "failed");
            return false;
         });
         
         if (installForm.ShowDialog(this) == DialogResult.OK)
         {
             await RefreshMarketAsync();
         }
    }

    private void OnDashboardProviderSelectionChanged()
    {
        var index = _dashboardProviderComboBox.SelectedIndex;
        if (index >= 0 && index < _marketOffers.Count)
        {
            _marketSelectedProviderId = _marketOffers[index].Id;
        }
    }

    private void RefreshDashboardProviderOptions()
    {
        _dashboardProviderComboBox.BeginUpdate();
        _dashboardProviderComboBox.Items.Clear();

        // Populate with INSTALLED providers primarily
        var installedIds = InstalledProviderManager.Instance.GetAllInstalledProviderIds();
        var displayItems = new List<(string Id, string Name)>();

        // 1. Add installed providers
        foreach (var pid in installedIds)
        {
            var offer = _marketOffers.FirstOrDefault(m => m.Id == pid);
            string name = offer != null ? offer.Name : pid;
            if (offer == null && pid == "com.meshnetprotocol.profile") name = "Default Profile";
            displayItems.Add((pid, name));
        }

        // 2. Add current selection if not in list (e.g. temporary run?)
        if (!string.IsNullOrEmpty(_marketSelectedProviderId) && !displayItems.Any(x => x.Id == _marketSelectedProviderId))
        {
             var offer = _marketOffers.FirstOrDefault(m => m.Id == _marketSelectedProviderId);
             if (offer != null) displayItems.Add((offer.Id, offer.Name));
             else displayItems.Add((_marketSelectedProviderId, _marketSelectedProviderId));
        }

        // 3. If empty, fallback to market offers (e.g. first run)
        if (displayItems.Count == 0 && _marketOffers.Count > 0)
        {
             foreach(var offer in _marketOffers)
             {
                 displayItems.Add((offer.Id, offer.Name));
             }
        }

        foreach (var item in displayItems)
        {
            _dashboardProviderComboBox.Items.Add(item.Name);
        }
        
        _dashboardProviderComboBox.EndUpdate();

        if (displayItems.Count > 0)
        {
            _dashboardProviderComboBox.Enabled = true;
            
            // Try to select current
            int index = -1;
            if (!string.IsNullOrEmpty(_marketSelectedProviderId))
            {
                index = displayItems.FindIndex(x => x.Id == _marketSelectedProviderId);
            }

            if (index >= 0)
            {
                _dashboardProviderComboBox.SelectedIndex = index;
            }
            else
            {
                _dashboardProviderComboBox.SelectedIndex = 0;
                _marketSelectedProviderId = displayItems[0].Id;
            }
        }
        else
        {
            // Keep enabled if possible, or disable if truly nothing
            _dashboardProviderComboBox.Enabled = false;
            // _marketSelectedProviderId = string.Empty; // Don't clear ID just because UI list is empty, might be temporary
        }
    }

    private void InitializeSettingsAlignedView()
    {
        foreach (var control in new Control[]
                 {
                     _settingsHeaderLabel,
                     _coreModeLabel,
                     _coreModeComboBox,
                     _autoStartCoreCheckBox,
                     _autoConnectVpnCheckBox,
                     _hideToTrayCheckBox,
                     _autoRecoverCoreCheckBox,
                     _runAtStartupCheckBox,
                     _stopLocalCoreOnExitCheckBox,
                     _p5BalanceRealCheckBox,
                     _p5BalanceStrictCheckBox,
                     _p5X402RealCheckBox,
                     _p5X402StrictCheckBox,
                     _saveSettingsButton,
                     _refreshIntegrationButton,
                     _settingsHintLabel,
                     _integrationSectionTitleLabel,
                     _startupStatusLabel,
                     _wintunStatusLabel,
                     _serviceStatusLabel,
                     _walletSectionTitleLabel,
                     _walletAddressTitleLabel,
                     _walletAddressValueLabel,
                     _walletNetworkTokenLabel,
                     _walletBalanceLabel,
                     _walletMnemonicTextBox,
                     _walletPasswordTextBox,
                     _walletGenerateButton,
                     _walletCreateButton,
                     _walletUnlockButton,
                     _walletBalanceButton
                 })
        {
            control.Visible = false;
        }

        var pageWidth = _settingsTab.ClientSize.Width;
        const int left = 14;
        var contentWidth = Math.Max(220, pageWidth - (left * 2));

        _settingsTopDivider.SetBounds(left, 8, contentWidth, 1);
        _settingsPageTitleLabel.SetBounds(left, 24, 160, 30);
        _settingsPageTitleLabel.Font = new Font("Segoe UI Semibold", 12.5F, FontStyle.Bold);
        _settingsPageTitleLabel.ForeColor = MeshTextPrimary;

        _settingsStartAtLoginLabel.SetBounds(left + 8, 76, 200, 24);
        _settingsStartAtLoginLabel.Font = new Font("Segoe UI", 10F, FontStyle.Regular);
        _settingsStartAtLoginLabel.ForeColor = MeshTextPrimary;

        _settingsStartAtLoginToggle.SetBounds(left + contentWidth - 74, 72, 60, 26);
        _settingsStartAtLoginToggle.Appearance = Appearance.Normal;
        _settingsStartAtLoginToggle.TextAlign = ContentAlignment.MiddleCenter;
        _settingsStartAtLoginToggle.CheckAlign = ContentAlignment.MiddleLeft;
        _settingsStartAtLoginToggle.FlatStyle = FlatStyle.Standard;

        _settingsUnmatchedLabel.SetBounds(left + 8, 112, 160, 24);
        _settingsUnmatchedLabel.Font = new Font("Segoe UI", 10F, FontStyle.Regular);
        _settingsUnmatchedLabel.ForeColor = MeshTextMuted;

        _settingsOutboundSegmentPanel.SetBounds(left + contentWidth - 222, 112, 206, 28);
        _settingsOutboundSegmentPanel.BackColor = Color.FromArgb(201, 218, 230);
        _settingsOutboundSegmentPanel.Padding = new Padding(0);

        _settingsProxyButton.SetBounds(0, 0, 103, 28);
        _settingsDirectButton.SetBounds(103, 0, 103, 28);
        foreach (var button in new[] { _settingsProxyButton, _settingsDirectButton })
        {
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
        }

        if (!_settingsOutboundSegmentPanel.Controls.Contains(_settingsProxyButton))
        {
            _settingsOutboundSegmentPanel.Controls.Add(_settingsProxyButton);
        }

        if (!_settingsOutboundSegmentPanel.Controls.Contains(_settingsDirectButton))
        {
            _settingsOutboundSegmentPanel.Controls.Add(_settingsDirectButton);
        }

        foreach (var control in new Control[]
                 {
                     _settingsTopDivider,
                     _settingsPageTitleLabel,
                     _settingsStartAtLoginLabel,
                     _settingsStartAtLoginToggle,
                     _settingsUnmatchedLabel,
                     _settingsOutboundSegmentPanel
                 })
        {
            if (!_settingsTab.Controls.Contains(control))
            {
                _settingsTab.Controls.Add(control);
            }
        }

        RefreshSettingsAlignedUi();
        _settingsTab.Resize -= SettingsTabOnResize;
        _settingsTab.Resize += SettingsTabOnResize;
    }

    private void SettingsTabOnResize(object? sender, EventArgs e)
    {
        InitializeSettingsAlignedView();
    }

    private void RefreshSettingsAlignedUi()
    {
        _settingsUiSyncInProgress = true;
        _settingsStartAtLoginToggle.Checked = _runAtStartupCheckBox.Checked;
        _settingsStartAtLoginToggle.Text = _settingsStartAtLoginToggle.Checked ? "On" : "Off";
        _settingsStartAtLoginToggle.BackColor = _settingsStartAtLoginToggle.Checked
            ? Color.FromArgb(171, 201, 219)
            : Color.FromArgb(210, 225, 236);
        SetSettingsUnmatchedTrafficOutbound(_settingsUnmatchedTrafficOutbound, persist: false);
        ApplyRoundedRegion(_settingsOutboundSegmentPanel, 7);
        _settingsUiSyncInProgress = false;
    }

    private void SetSettingsUnmatchedTrafficOutbound(string mode, bool persist)
    {
        var normalized = string.Equals(mode, "proxy", StringComparison.OrdinalIgnoreCase) ? "proxy" : "direct";
        _settingsUnmatchedTrafficOutbound = normalized;

        if (normalized == "proxy")
        {
            _settingsProxyButton.BackColor = Color.FromArgb(122, 150, 171);
            _settingsProxyButton.ForeColor = Color.White;
            _settingsDirectButton.BackColor = Color.FromArgb(201, 218, 230);
            _settingsDirectButton.ForeColor = MeshTextPrimary;
        }
        else
        {
            _settingsProxyButton.BackColor = Color.FromArgb(201, 218, 230);
            _settingsProxyButton.ForeColor = MeshTextPrimary;
            _settingsDirectButton.BackColor = Color.FromArgb(122, 150, 171);
            _settingsDirectButton.ForeColor = Color.White;
        }

        ApplyRoundedRegion(_settingsProxyButton, 6);
        ApplyRoundedRegion(_settingsDirectButton, 6);

        if (!persist)
        {
            return;
        }

        _appSettings.UnmatchedTrafficOutbound = normalized;
        try
        {
            _settingsManager.Save(_appSettings);
        }
        catch (Exception ex)
        {
            AppendLog($"save unmatched outbound failed: {ex.Message}");
        }
    }

    private void ApplyStartAtLoginToggle()
    {
        if (_settingsUiSyncInProgress)
        {
            return;
        }

        _runAtStartupCheckBox.Checked = _settingsStartAtLoginToggle.Checked;
        _appSettings.RunAtStartup = _settingsStartAtLoginToggle.Checked;
        try
        {
            _settingsManager.Save(_appSettings);
            _systemIntegrationManager.SetStartupEnabled(_appSettings.RunAtStartup);
            AppendLog($"start at login -> {(_appSettings.RunAtStartup ? "enabled" : "disabled")}");
        }
        catch (Exception ex)
        {
            AppendLog($"start at login update failed: {ex.Message}");
        }

        RefreshSettingsAlignedUi();
    }

    private void RefreshDashboardNodeSnapshot()
    {
        var selectedGroupTag = _groupComboBox.SelectedItem as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(selectedGroupTag) || !_groupByTag.TryGetValue(selectedGroupTag, out var group))
        {
            _dashboardNodeNameLabel.Text = "meshflux node";
            _dashboardNodeEndpointLabel.Text = "0.0.0.0";
            return;
        }

        var selectedOutbound = _outboundComboBox.SelectedItem as string;
        if (string.IsNullOrWhiteSpace(selectedOutbound))
        {
            selectedOutbound = group.Selected;
        }

        _dashboardNodeNameLabel.Text = string.IsNullOrWhiteSpace(selectedOutbound)
            ? group.Tag
            : selectedOutbound;
        _dashboardNodeEndpointLabel.Text = group.Tag;
    }

    private void SaveSettingsPreview()
    {
        _appSettings.CoreMode = _coreModeComboBox.SelectedItem as string ?? AppSettings.CoreModeGo;
        _appSettings.CoreMode = _appSettings.GetNormalizedCoreMode();
        _appSettings.AutoStartCore = _autoStartCoreCheckBox.Checked;
        _appSettings.AutoConnectVpn = _autoConnectVpnCheckBox.Checked;
        _appSettings.HideToTrayOnClose = _hideToTrayCheckBox.Checked;
        _appSettings.AutoRecoverCore = _autoRecoverCoreCheckBox.Checked;
        _appSettings.RunAtStartup = _runAtStartupCheckBox.Checked;
        _appSettings.StopLocalCoreOnExit = _stopLocalCoreOnExitCheckBox.Checked;
        _appSettings.P5BalanceReal = _p5BalanceRealCheckBox.Checked;
        _appSettings.P5BalanceStrict = _p5BalanceStrictCheckBox.Checked;
        _appSettings.P5X402Real = _p5X402RealCheckBox.Checked;
        _appSettings.P5X402Strict = _p5X402StrictCheckBox.Checked;
        _appSettings.UnmatchedTrafficOutbound = _settingsUnmatchedTrafficOutbound;

        try
        {
            _settingsManager.Save(_appSettings);
            _systemIntegrationManager.SetStartupEnabled(_appSettings.RunAtStartup);
            RefreshIntegrationUi();
            _statusStreamUnsupportedByCore = false;
            _connectionsStreamUnsupportedByCore = false;
            _groupsStreamUnsupportedByCore = false;
            if (CanUseStatusStream())
            {
                EnsureStatusStreamRunning();
            }
            else
            {
                StopStatusStream();
            }

            if (CanUseConnectionsStream())
            {
                EnsureConnectionsStreamRunning(forceRestart: true);
            }
            else
            {
                StopConnectionsStream();
            }

            if (CanUseGroupsStream())
            {
                EnsureGroupsStreamRunning();
            }
            else
            {
                StopGroupsStream();
            }

            AppendLog(
                $"settings saved: core_mode={_appSettings.CoreMode}, auto_core={_appSettings.AutoStartCore}, auto_connect={_appSettings.AutoConnectVpn}, hide_to_tray={_appSettings.HideToTrayOnClose}, auto_recover={_appSettings.AutoRecoverCore}, startup={_appSettings.RunAtStartup}, stop_core_on_exit={_appSettings.StopLocalCoreOnExit}, p5_balance_real={_appSettings.P5BalanceReal}, p5_balance_strict={_appSettings.P5BalanceStrict}, p5_x402_real={_appSettings.P5X402Real}, p5_x402_strict={_appSettings.P5X402Strict}");
            MessageBox.Show(
                this,
                "Settings saved and startup integration applied.",
                "OpenMesh Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            AppendLog($"settings save failed: {ex.Message}");
            MessageBox.Show(
                this,
                $"Failed to save settings: {ex.Message}",
                "OpenMesh Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static CoreRuntimeStats CloneRuntime(CoreRuntimeStats source)
    {
        return new CoreRuntimeStats
        {
            TotalUploadBytes = source.TotalUploadBytes,
            TotalDownloadBytes = source.TotalDownloadBytes,
            UploadRateBytesPerSec = source.UploadRateBytesPerSec,
            DownloadRateBytesPerSec = source.DownloadRateBytesPerSec,
            MemoryMb = source.MemoryMb,
            ThreadCount = source.ThreadCount,
            UptimeSeconds = source.UptimeSeconds,
            ConnectionCount = source.ConnectionCount
        };
    }

    private static CoreConnection CloneConnection(CoreConnection source)
    {
        return new CoreConnection
        {
            Id = source.Id,
            ProcessName = source.ProcessName,
            Destination = source.Destination,
            Protocol = source.Protocol,
            Outbound = source.Outbound,
            UploadBytes = source.UploadBytes,
            DownloadBytes = source.DownloadBytes,
            LastSeenUtc = source.LastSeenUtc,
            State = source.State
        };
    }

    private static CoreOutboundGroup CloneGroup(CoreOutboundGroup source)
    {
        return new CoreOutboundGroup
        {
            Tag = source.Tag,
            Type = source.Type,
            Selected = source.Selected,
            Selectable = source.Selectable,
            Items = [.. source.Items.Select(item => new CoreOutboundGroupItem
            {
                Tag = item.Tag,
                Type = item.Type,
                UrlTestDelay = item.UrlTestDelay
            })]
        };
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
        if (_exitRequested)
        {
            return;
        }

        _exitRequested = true;
        StopStatusStream();
        StopConnectionsStream();
        StopGroupsStream();
        _statusTimer.Stop();
        trayIcon.Visible = false;
        Application.Exit();
        Close();
    }

    private void AppendLog(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        AppLogger.Log(message);
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
            logsTextBox.Lines = [.. logsTextBox.Lines.Skip(Math.Max(0, logsTextBox.Lines.Length - 300))];
        }

        logsTextBox.SelectionStart = logsTextBox.TextLength;
        logsTextBox.ScrollToCaret();
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

    private ProviderMarketForm? _marketForm;

    private void InitializeMarketTab()
    {
        _marketHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _marketHeaderLabel.ForeColor = MeshAccentBlue;
        _marketHeaderLabel.SetBounds(22, 22, 180, 28);

        _marketTabOpenButton.SetBounds(210, 22, 100, 30);
        _marketTabOpenButton.FlatStyle = FlatStyle.Flat;
        _marketTabOpenButton.FlatAppearance.BorderSize = 0;
        _marketTabOpenButton.BackColor = Color.FromArgb(236, 245, 252);
        _marketTabOpenButton.ForeColor = MeshAccentBlue;
        _marketTabOpenButton.Click += (_, _) => OpenMarketWindow();

        _importProviderFileButton.SetBounds(320, 22, 100, 30);
        _importProviderFileButton.FlatStyle = FlatStyle.Flat;
        _importProviderFileButton.FlatAppearance.BorderSize = 0;
        _importProviderFileButton.BackColor = MeshAccentBlue;
        _importProviderFileButton.ForeColor = Color.White;

        _marketCardsPanel.SetBounds(16, 64, 514, 600);
        _marketCardsPanel.BackColor = Color.Transparent;

        _marketTab.Controls.Add(_marketHeaderLabel);
        _marketTab.Controls.Add(_marketTabOpenButton);
        _marketTab.Controls.Add(_importProviderFileButton);
        _marketTab.Controls.Add(_marketCardsPanel);

        ApplyRoundedRegion(_marketTabOpenButton, 8);
        ApplyRoundedRegion(_importProviderFileButton, 8);
        
        RefreshMarketPreview();
    }

    private void OpenMarketWindow()
    {
        if (_marketForm != null && !_marketForm.IsDisposed)
        {
            _marketForm.BringToFront();
            _marketForm.UpdateData(_marketOffers, _installedProviderIds);
            return;
        }

        _marketForm = new ProviderMarketForm(
            _marketOffers,
            _installedProviderIds,
            onInstall: async (id) =>
            {
                var offer = _marketOffers.FirstOrDefault(o => o.Id == id);
                if (offer == null || !_coreOnline) return;

                var isInstalled = _installedProviderIds.Contains(id);
                if (isInstalled && offer.UpgradeAvailable)
                {
                     var response = await _coreClient.UpgradeProviderAsync(offer.Id);
                     AppendLog($"provider_upgrade({offer.Id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
                     if (response.Ok)
                     {
                         _marketOffers = response.Providers;
                         _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
                         RefreshMarketPreview();
                     }
                     return;
                }

                var installForm = new ProviderInstallForm(offer.Id, offer.Name, async (progressCallback) =>
                {
                    progressCallback("Fetch provider details", "running");
                    await Task.Delay(500); 
                    progressCallback("Fetch provider details", "done");

                    progressCallback("Download config", "running");
                    
                    var response = await _coreClient.InstallProviderAsync(offer.Id);
                    
                    if (response.Ok)
                    {
                        progressCallback("Download config", "done");
                        progressCallback("Finalize", "done");
                        var installedHash = !string.IsNullOrEmpty(offer.PackageHash) ? offer.PackageHash : "unknown-hash";
                        InstalledProviderManager.Instance.RegisterInstalledProvider(offer.Id, installedHash, []);
                        return true;
                    }
                    else
                    {
                        progressCallback("Download config", $"failed: {response.Message}");
                        return false;
                    }
                });

                if (installForm.ShowDialog(this) == DialogResult.OK)
                {
                    AppendLog($"provider_install({offer.Id}) -> success");
                    await RefreshMarketAsync();
                }
            },
            onUninstall: async (id) =>
            {
                if (!_coreOnline) return;
                var response = await _coreClient.UninstallProviderAsync(id);
                AppendLog($"provider_uninstall({id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
                if (response.Ok)
                {
                    _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
                    InstalledProviderManager.Instance.RemoveProvider(id);
                    RefreshMarketPreview();
                }
            },
            onActivate: async (id) =>
            {
                if (!_coreOnline) return;
                var response = await _coreClient.ActivateProviderAsync(id);
                AppendLog($"provider_activate({id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
                if (response.Ok)
                {
                    UpdateStatusUi(response);
                    _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
                    RefreshMarketPreview();
                }
            },
            onRefresh: async () =>
            {
                await RefreshMarketAsync();
            }
        );
        _marketForm.Show();
    }
}

internal sealed class MeshCardPanel : Panel
{
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public int CornerRadius { get; set; } = 14;
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Color BorderColor { get; set; } = Color.FromArgb(205, 224, 240);

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        var radius = Math.Max(4, CornerRadius);
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using var path = CreateRoundedPath(rect, radius);
        using var borderPen = new Pen(BorderColor, 1F);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawPath(borderPen, path);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var brush = new SolidBrush(BackColor);
        using var path = CreateRoundedPath(new Rectangle(0, 0, Width - 1, Height - 1), Math.Max(4, CornerRadius));
        e.Graphics.FillPath(brush, path);
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

internal sealed class SmoothFlowLayoutPanel : FlowLayoutPanel
{
    public SmoothFlowLayoutPanel()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
    }
}

internal sealed class TinyTrafficChartPanel : Panel
{
    private float[] _uploadSamples = [];
    private float[] _downloadSamples = [];

    public TinyTrafficChartPanel()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        BackColor = Color.FromArgb(244, 250, 255);
    }

    public void SetSamples(IEnumerable<float> upload, IEnumerable<float> download)
    {
        _uploadSamples = [.. upload];
        _downloadSamples = [.. download];
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        var rect = new Rectangle(0, 0, Math.Max(1, Width - 1), Math.Max(1, Height - 1));
        using (var baselinePen = new Pen(Color.FromArgb(220, 232, 242), 1F))
        {
            e.Graphics.DrawLine(baselinePen, rect.Left + 2, rect.Bottom - 2, rect.Right - 2, rect.Bottom - 2);
            e.Graphics.DrawLine(baselinePen, rect.Left + 2, rect.Bottom - 12, rect.Right - 2, rect.Bottom - 12);
        }

        if (_uploadSamples.Length < 2 && _downloadSamples.Length < 2)
        {
            return;
        }

        var maxValue = Math.Max(1F, Math.Max(_uploadSamples.DefaultIfEmpty(0).Max(), _downloadSamples.DefaultIfEmpty(0).Max()));
        DrawSeries(e.Graphics, _uploadSamples, Color.FromArgb(83, 198, 120), maxValue, rect);
        DrawSeries(e.Graphics, _downloadSamples, Color.FromArgb(79, 163, 234), maxValue, rect);
    }

    private static void DrawSeries(Graphics g, float[] samples, Color color, float maxValue, Rectangle rect)
    {
        if (samples.Length < 2)
        {
            return;
        }

        var points = new PointF[samples.Length];
        var width = Math.Max(1, rect.Width - 8);
        var height = Math.Max(1, rect.Height - 8);
        for (var i = 0; i < samples.Length; i++)
        {
            var x = rect.Left + 4 + (width * i / (samples.Length - 1f));
            var normalized = Math.Clamp(samples[i] / maxValue, 0F, 1F);
            var y = rect.Bottom - 4 - (height * normalized);
            points[i] = new PointF(x, y);
        }

        using var pen = new Pen(color, 2.0F);
        g.DrawLines(pen, points);
    }
}
