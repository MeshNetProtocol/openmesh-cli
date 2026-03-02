using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Text;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;

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
    private readonly TrafficBadgeLabel _dashboardUpBadgeLabel = new() { Text = "UP  0 B" };
    private readonly TrafficBadgeLabel _dashboardDownBadgeLabel = new() { Text = "DOWN  0 B" };
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

    // UI-selected profile (may differ from core-reported profile while offline or mid-switch)
    private long _selectedProfileId;
    private string _selectedProfileName = string.Empty;
    private string _selectedProfilePath = string.Empty;
    private NodeProfileMetadata _selectedProfileMeta = new();
    private string _selectedPreferredGroupTag = string.Empty;
    private string _lastUrlTestGroup = string.Empty;
    private CoreRuntimeStats _lastRuntimeStats = new();
    private List<CoreConnection> _lastConnections = [];
    private decimal _lastWalletBalance;
    private string _lastWalletToken = "USDC";

    private HashSet<string> _installedProviderIds = new(StringComparer.OrdinalIgnoreCase);
    private string _lastKnownProfilePath = string.Empty;
    private long _activeProfileId;
    private string _activeProfileName = string.Empty;
    private NodeProfileMetadata _activeProfileMeta = new();
    private string _activePreferredGroupTag = string.Empty;
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
    private TrafficDetailsForm? _activeTrafficDetailsForm;
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
        _dashboardBottomLeftPrimaryButton.Click += async (_, _) => await OpenMarketWindow();
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
        _coreModeComboBox.Items.Add("embedded");
        _coreModeComboBox.SelectedItem = "embedded";
        _coreModeComboBox.Enabled = false;

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
        _dashboardOpenMarketButton.Click += async (_, _) => await OpenMarketWindow();
        
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

        _dashboardUpBadgeLabel.SetBounds(18, 16, 140, 22);
        ConfigureTrafficBadge(_dashboardUpBadgeLabel, Color.FromArgb(71, 167, 230));
        _dashboardTrafficCard.Controls.Add(_dashboardUpBadgeLabel);

        _dashboardDownBadgeLabel.SetBounds(166, 16, 140, 22);
        ConfigureTrafficBadge(_dashboardDownBadgeLabel, Color.FromArgb(60, 199, 128));
        _dashboardTrafficCard.Controls.Add(_dashboardDownBadgeLabel);

        _dashboardTrafficChartPanel.SetBounds(18, 48, 448, 104);
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

        _openTrafficWindowButton.SetBounds(358, 14, 108, 24);
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
        _dashboardTrafficChartPanel.SetBounds(18, 48, Math.Max(230, cardWidth - 36), 104);
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

    private static void ConfigureTrafficBadge(TrafficBadgeLabel label, Color markerColor)
    {
        label.BackColor = Color.FromArgb(234, 244, 252);
        label.ForeColor = Color.FromArgb(50, 60, 72);
        label.TextAlign = ContentAlignment.MiddleLeft;
        label.Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold);
        label.Padding = new Padding(6, 0, 6, 0);
        label.BorderStyle = BorderStyle.None;
        label.MarkerColor = markerColor;
        ApplyRoundedRegion(label, 11);
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
        AppendLog(
            $"p5 wallet bridge: balance_real={_appSettings.P5BalanceReal}, balance_strict={_appSettings.P5BalanceStrict}, x402_real={_appSettings.P5X402Real}, x402_strict={_appSettings.P5X402Strict}");
        RefreshIntegrationUi();

        // Restore last user-selected profile (providerId or "profile:ID") for dashboard picker + offline node view.
        var storedSelection = SelectedProfileStore.Instance.Get();
        if (!string.IsNullOrWhiteSpace(storedSelection))
        {
            _marketSelectedProviderId = storedSelection;
        }
        RefreshDashboardProviderOptions(); // Ensure installed profiles are loaded in dashboard UI
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

    private async Task ApplyDashboardProfileSelectionAsync(string selectionId, bool applyToCore)
    {
        selectionId = (selectionId ?? string.Empty).Trim();
        SelectedProfileStore.Instance.Set(selectionId);

        var profile = await ResolveProfileForSelectionAsync(selectionId);
        if (profile is null || string.IsNullOrWhiteSpace(profile.Path) || !File.Exists(profile.Path))
        {
            _selectedProfileId = 0;
            _selectedProfileName = string.Empty;
            _selectedProfilePath = string.Empty;
            _selectedProfileMeta = new NodeProfileMetadata();
            _selectedPreferredGroupTag = string.Empty;
            _lastOutboundGroups = [];
            _lastUrlTestDelays = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            BindOutboundGroups([]);
            RefreshDashboardNodeSnapshot();
            return;
        }

        _selectedProfileId = profile.Id;
        _selectedProfileName = profile.Name ?? string.Empty;
        _selectedProfilePath = profile.Path ?? string.Empty;
        _selectedProfileMeta = NodeProfileMetadata.TryLoad(_selectedProfilePath);
        _selectedPreferredGroupTag = _selectedProfileMeta.PickPreferredGroupTag();

        // Avoid showing stale nodes from a previous profile while switching.
        if (!applyToCore || !_coreOnline)
        {
            _lastOutboundGroups = [];
            _lastUrlTestDelays = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            BindOutboundGroups([]);
        }

        RefreshDashboardNodeSnapshot();

        if (!applyToCore || !_coreOnline)
        {
            return;
        }

        _lastOutboundGroups = [];
        _lastUrlTestDelays = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        BindOutboundGroups([]);

        AppendLog($"switch profile -> {_selectedProfileName} ({_selectedProfilePath})");
        var resp = await _coreClient.SetProfileAsync(_selectedProfilePath);
        AppendLog($"set_profile -> {(resp.Ok ? "ok" : "failed")}: {resp.Message}");
        // Refresh status/groups after core applied profile.
        await RefreshStatusAsync();
        StopGroupsStream();
        EnsureGroupsStreamRunning();
    }

    private static bool IsProfileRef(string selectionId)
    {
        return selectionId.StartsWith("profile:", StringComparison.OrdinalIgnoreCase);
    }

    private async Task<Profile?> ResolveProfileForSelectionAsync(string selectionId)
    {
        var allProfiles = await ProfileManager.Instance.ListAsync();
        if (allProfiles.Count == 0)
        {
            return null;
        }

        if (string.IsNullOrWhiteSpace(selectionId))
        {
            return allProfiles[0];
        }

        var byProviderId = allProfiles.FirstOrDefault(p =>
            string.Equals(InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id), selectionId, StringComparison.OrdinalIgnoreCase));
        if (byProviderId is not null)
        {
            return byProviderId;
        }

        if (IsProfileRef(selectionId))
        {
            var idText = selectionId.Substring("profile:".Length);
            if (long.TryParse(idText, out var pid))
            {
                return await ProfileManager.Instance.GetAsync(pid);
            }
        }

        return allProfiles[0];
    }

    private void LoadAndApplySettingsFromDisk()
    {
        _appSettings = _settingsManager.Load();
        ApplySettingsToControls();
    }

    private void ApplySettingsToControls()
    {
        _coreModeComboBox.SelectedItem = "embedded";
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
        var ping = await _coreClient.PingAsync();
        AppendLog(ping.Ok ? "Embedded core backend is active." : $"Embedded core backend is unavailable: {ping.Message}");
        _statusStreamUnsupportedByCore = false;
        _connectionsStreamUnsupportedByCore = false;
        _groupsStreamUnsupportedByCore = false;
        await RefreshStatusAsync();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
    }

    private async Task OnVpnStateChangedAsync(bool isRunning)
    {
        if (isRunning)
        {
            // Try to initialize pending rule-sets if any
            await InitializePendingRuleSetsAsync();
        }
    }

    private async Task InitializePendingRuleSetsAsync()
    {
        // 1. Check if current profile has pending rule-sets
        // We need to know the current ProviderID.
        if (string.IsNullOrEmpty(_marketSelectedProviderId)) return;
        
        var pendingTags = InstalledProviderManager.Instance.GetPendingRuleSets(_marketSelectedProviderId);
        if (pendingTags.Count == 0) return;

        AppendLog($"[RuleSet] Found {pendingTags.Count} pending rule-sets for provider {_marketSelectedProviderId}. Attempting download...");

        // 2. We need the URLs. Currently InstalledProviderManager only stores Tags.
        // We now have RuleSetUrls stored in Manager (aligned with macOS).
        var ruleSetUrlMap = InstalledProviderManager.Instance.GetRuleSetUrls(_marketSelectedProviderId);
        
        var remoteRuleSets = new Dictionary<string, string>();
        
        // Use stored URLs if available
        if (ruleSetUrlMap != null && ruleSetUrlMap.Count > 0)
        {
             foreach(var tag in pendingTags)
             {
                 if (ruleSetUrlMap.TryGetValue(tag, out var url))
                 {
                     remoteRuleSets[tag] = url;
                 }
             }
        }
        
        // Fallback: Parse config_full.json if URLs missing (legacy support)
        if (remoteRuleSets.Count < pendingTags.Count)
        {
            var allProfiles = await ProfileManager.Instance.ListAsync();
            var activeProfile = allProfiles.FirstOrDefault(p => 
                InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == _marketSelectedProviderId);
                
            if (activeProfile == null || !File.Exists(activeProfile.Path))
            {
                AppendLog($"[RuleSet] Cannot retry download: Config file not found.");
                return;
            }

            try 
            {
                var providerDir = Path.GetDirectoryName(activeProfile.Path);
                var fullConfigPath = Path.Combine(providerDir!, "config_full.json");
                
                if (File.Exists(fullConfigPath))
                {
                    var fullJson = await File.ReadAllTextAsync(fullConfigPath);
                    var root = System.Text.Json.Nodes.JsonNode.Parse(fullJson);
                    
                    var ruleSets = root?["config"]?["route"]?["rule_set"] as System.Text.Json.Nodes.JsonArray 
                                   ?? root?["route"]?["rule_set"] as System.Text.Json.Nodes.JsonArray;
                                   
                    if (ruleSets != null)
                    {
                        foreach (var node in ruleSets)
                        {
                            if (node?["type"]?.ToString() == "remote" &&
                                node?["tag"]?.ToString() is string tag &&
                                node?["url"]?.ToString() is string url &&
                                pendingTags.Contains(tag) &&
                                !remoteRuleSets.ContainsKey(tag))
                            {
                                remoteRuleSets[tag] = url;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                 AppendLog($"[RuleSet] Failed to parse config for URLs: {ex.Message}");
            }
        }
            
        if (remoteRuleSets.Count == 0)
        {
            AppendLog("[RuleSet] No matching remote rule-sets found in config.");
            return;
        }

        try
        {
            // 3. Download concurrently
            // We need providerDir for target path
            var allProfiles2 = await ProfileManager.Instance.ListAsync();
        var activeProfile2 = allProfiles2.FirstOrDefault(p => 
            InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == _marketSelectedProviderId);
        if (activeProfile2 == null) return;
        var providerDir2 = Path.GetDirectoryName(activeProfile2.Path);
        
        var ruleSetDir = Path.Combine(providerDir2!, "rule-set");
        Directory.CreateDirectory(ruleSetDir);
        
        var successTags = new HashSet<string>();
            
        using var semaphore = new SemaphoreSlim(2);
        var tasks = remoteRuleSets.Select(async rs =>
        {
            await semaphore.WaitAsync();
            try
            {
                var tag = rs.Key;
                var url = rs.Value;
                AppendLog($"[RuleSet] Downloading {tag}...");
                
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
                http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
                
                var data = await http.GetByteArrayAsync(url);
                if (data.Length > 0)
                {
                    var targetPath = Path.Combine(ruleSetDir, $"{tag}.srs");
                    await File.WriteAllBytesAsync(targetPath, data);
                    lock (successTags) successTags.Add(tag);
                    AppendLog($"[RuleSet] {tag} downloaded.");
                }
            }
            catch (Exception ex)
            {
                AppendLog($"[RuleSet] Failed to download {rs.Key}: {ex.Message}");
            }
            finally
            {
                semaphore.Release();
            }
        });
        
        await Task.WhenAll(tasks);
        
        // 4. If any success, update config.json and reload
        if (successTags.Count > 0)
        {
            AppendLog($"[RuleSet] {successTags.Count} rule-sets recovered. Updating config...");
            
            // Read full config again to patch
            // We need to re-read it to ensure we have the base
            string fullJsonContent = "{}";
            var providerDir3 = Path.GetDirectoryName(activeProfile2.Path);
            var fullConfigPath3 = Path.Combine(providerDir3!, "config_full.json");
            
            if (File.Exists(fullConfigPath3))
            {
                fullJsonContent = await File.ReadAllTextAsync(fullConfigPath3);
            }
            else if (File.Exists(activeProfile2.Path))
            {
                // Fallback to current config if full not found (risky but better than crash)
                fullJsonContent = await File.ReadAllTextAsync(activeProfile2.Path);
            }
            
            var fullConfigNode = System.Text.Json.Nodes.JsonNode.Parse(fullJsonContent);
            
            // Get all currently installed tags (previously installed + newly recovered)
            var existingFiles = Directory.GetFiles(ruleSetDir, "*.srs")
                                         .Select(Path.GetFileNameWithoutExtension)
                                         .Where(x => x != null)
                                         .Select(x => x!)
                                         .ToHashSet(StringComparer.OrdinalIgnoreCase);
                                         
            // Patch config
            PatchConfigRuleSets(fullConfigNode, ruleSetDir, existingFiles);
            
            // Write new config.json
            var newConfigJson = fullConfigNode!.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(activeProfile2.Path, newConfigJson);
            
            // Update Manager State
            var newPending = pendingTags.Where(t => !successTags.Contains(t)).ToList();
            var packageHash = InstalledProviderManager.Instance.GetLocalPackageHash(_marketSelectedProviderId);
            var currentUrls = InstalledProviderManager.Instance.GetRuleSetUrls(_marketSelectedProviderId);
            
            InstalledProviderManager.Instance.RegisterInstalledProvider(
                _marketSelectedProviderId, 
                packageHash, 
                newPending,
                currentUrls
            );
            
            // Reload Core
            AppendLog("[RuleSet] Reloading core with updated rules...");
            await _coreClient.ReloadAsync();
        }
    }
    catch (Exception ex)
    {
        AppendLog($"[RuleSet] Initialization failed: {ex.Message}");
    }
}

    private void PatchConfigRuleSets(System.Text.Json.Nodes.JsonNode? root, string finalRuleSetDir, HashSet<string> availableTags)
    {
        var ruleSets = root?["config"]?["route"]?["rule_set"] as System.Text.Json.Nodes.JsonArray 
                       ?? root?["route"]?["rule_set"] as System.Text.Json.Nodes.JsonArray;
                       
        if (ruleSets != null)
        {
            for (int i = 0; i < ruleSets.Count; i++)
            {
                var node = ruleSets[i];
                if (node?["type"]?.ToString() == "remote" &&
                    node?["tag"]?.ToString() is string tag &&
                    availableTags.Contains(tag))
                {
                    var newNode = new System.Text.Json.Nodes.JsonObject
                    {
                        ["type"] = "local",
                        ["tag"] = tag,
                        ["format"] = "binary",
                        ["path"] = Path.Combine(finalRuleSetDir, $"{tag}.srs")
                    };
                    ruleSets[i] = newNode;
                }
            }
        }
    }

    private async Task StartVpnAsync()
    {
        var sw = Stopwatch.StartNew();
        if (!EnsureAdminBeforeVpnStart())
        {
            return;
        }

        SetVpnOperationUiState(true, "Starting...");
        try
        {
            var allProfiles = await ProfileManager.Instance.ListAsync();
            var activeProfile = allProfiles.FirstOrDefault(p => 
                InstalledProviderManager.Instance.GetProviderIdForProfile(p.Id) == _marketSelectedProviderId);
            
            // If no profile found by provider ID (maybe _marketSelectedProviderId IS the profile ID?)
            // We changed Dashboard to store "providerId" OR "profile:ID".
            if (activeProfile == null && _marketSelectedProviderId.StartsWith("profile:"))
            {
                if (long.TryParse(_marketSelectedProviderId.Substring(8), out var pid))
                {
                    activeProfile = await ProfileManager.Instance.GetAsync(pid);
                }
            }
            
            // Fallback to first profile if nothing selected but we have profiles
            if (activeProfile == null && allProfiles.Count > 0)
            {
                activeProfile = allProfiles[0];
            }

            object? payload = null;
            if (activeProfile != null && !string.IsNullOrEmpty(activeProfile.Path))
            {
                // Verify file exists
                if (File.Exists(activeProfile.Path))
                {
                    var setProfileResp = await _coreClient.SetProfileAsync(activeProfile.Path);
                    AppendLog($"set_profile -> {(setProfileResp.Ok ? "ok" : "failed")}: {setProfileResp.Message}");
                    if (!setProfileResp.Ok)
                    {
                        MessageBox.Show(this, $"加载配置失败: {setProfileResp.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        SetVpnOperationUiState(false, "Start");
                        return;
                    }

                    var meta = NodeProfileMetadata.TryLoad(activeProfile.Path);
                    var preferredGroup = meta.PickPreferredGroupTag();
                    var offlineSelected = SelectedOutboundStore.Instance.Get(activeProfile.Id)?.OutboundTag ?? string.Empty;
                    if (string.IsNullOrWhiteSpace(offlineSelected) &&
                        meta.GroupDefaultOutboundByTag.TryGetValue(preferredGroup, out var def) &&
                        !string.IsNullOrWhiteSpace(def))
                    {
                        offlineSelected = def;
                    }
                    if (!string.IsNullOrWhiteSpace(preferredGroup) && !string.IsNullOrWhiteSpace(offlineSelected))
                    {
                        var selResp = await _coreClient.SelectOutboundAsync(preferredGroup, offlineSelected);
                        AppendLog($"select_outbound(pre-start) -> {(selResp.Ok ? "ok" : "failed")}: {selResp.Message}");
                    }

                    // Pass the config file path to the core
                    payload = new { config_path = activeProfile.Path };
                    AppendLog($"Starting VPN with profile: {activeProfile.Name} ({activeProfile.Path})");
                }
                else
                {
                    AppendLog($"Warning: Profile path not found: {activeProfile.Path}");
                    MessageBox.Show(this, "配置文件路径不存在，请重新安装。", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    SetVpnOperationUiState(false, "Start");
                    return;
                }
            }
            else
            {
                 AppendLog($"Warning: No active profile found for selection {_marketSelectedProviderId}.");
                 MessageBox.Show(this, "未找到有效的启动配置文件，请先安装或导入配置。", "无配置文件", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                 SetVpnOperationUiState(false, "Start");
                 return;
            }

            AppendLog($"Requesting Core StartVpn... (prep took {sw.ElapsedMilliseconds}ms)");
            var swCore = Stopwatch.StartNew();
            var response = await _coreClient.StartVpnAsync(payload);
            swCore.Stop();
            
            if (!response.Ok)
            {
                AppendLog($"start_vpn -> failed: {response.Message} (core took {swCore.ElapsedMilliseconds}ms)");
                SetVpnOperationUiState(false, "Start");
            }
            else
            {
                AppendLog($"start_vpn -> success (core took {swCore.ElapsedMilliseconds}ms)");
                _dashboardVpnRunning = true;
                // Success - wait for status stream to update UI, but clear busy state now to be safe
                // or keep it busy until status confirms running?
                // Let's clear it to avoid stuck UI if stream is slow
                SetVpnOperationUiState(false, "Running");
            }
            await RefreshStatusAsync();
        }
        catch (Exception ex)
        {
            AppendLog($"Start VPN exception: {ex.Message}");
            SetVpnOperationUiState(false, "Start");
        }
        finally
        {
             sw.Stop();
             if (sw.ElapsedMilliseconds > 2000)
             {
                 AppendLog($"Total StartVpn sequence took {sw.ElapsedMilliseconds}ms");
             }
        }
    }

    private async Task ReloadConfigAsync()
    {
        var response = await _coreClient.ReloadAsync();
        AppendLog($"reload -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        await RefreshStatusAsync();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
    }

    private async Task StopVpnAsync()
    {
        var sw = Stopwatch.StartNew();
        SetVpnOperationUiState(true, "Stopping...");
        try
        {
            var response = await _coreClient.StopVpnAsync();
            AppendLog($"stop_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message} (took {sw.ElapsedMilliseconds}ms)");
            await RefreshStatusAsync();
        }
        finally
        {
            SetVpnOperationUiState(false, string.Empty);
            sw.Stop();
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
            var ping = await _coreClient.PingAsync();
            AppendLog($"auto_recover result: {(ping.Ok ? "embedded core ok" : $"embedded core failed: {ping.Message}")}");
            if (ping.Ok)
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

        var previousProfilePath = _lastKnownProfilePath;
        profilePathValueLabel.Text = string.IsNullOrWhiteSpace(status.ProfilePath) ? "N/A" : status.ProfilePath;
        _lastKnownProfilePath = status.ProfilePath ?? string.Empty;
        if (!string.Equals(previousProfilePath, _lastKnownProfilePath, StringComparison.OrdinalIgnoreCase))
        {
            _activeProfileMeta = NodeProfileMetadata.TryLoad(_lastKnownProfilePath);
            _activePreferredGroupTag = _activeProfileMeta.PickPreferredGroupTag();
            _activeProfileId = 0;
            _activeProfileName = string.Empty;
            if (!string.IsNullOrWhiteSpace(_lastKnownProfilePath))
            {
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var profiles = await ProfileManager.Instance.ListAsync();
                        var match = profiles.FirstOrDefault(p =>
                            string.Equals(p.Path, _lastKnownProfilePath, StringComparison.OrdinalIgnoreCase));
                        if (match != null)
                        {
                            BeginInvoke(new Action(() =>
                            {
                                _activeProfileId = match.Id;
                                _activeProfileName = match.Name ?? string.Empty;
                            }));
                        }
                    }
                    catch
                    {
                    }
                });
            }
        }
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
        RefreshDashboardNodeSnapshot();
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
        var name = string.IsNullOrWhiteSpace(_selectedProfileName) ? (_dashboardProviderComboBox.Text ?? string.Empty) : _selectedProfileName;
        if (string.IsNullOrWhiteSpace(name)) name = "当前配置";

        var liveMeta = _selectedProfileMeta;
        if (!string.IsNullOrWhiteSpace(_selectedProfilePath) && File.Exists(_selectedProfilePath))
        {
            liveMeta = NodeProfileMetadata.TryLoad(_selectedProfilePath);
            _selectedProfileMeta = liveMeta;
            _selectedPreferredGroupTag = liveMeta.PickPreferredGroupTag();
        }

        var groupTag = SelectedOutboundStore.Instance.Get(_selectedProfileId)?.GroupTag ?? string.Empty;
        if (string.IsNullOrWhiteSpace(groupTag))
        {
            groupTag = PickPreferredGroupTag(_lastOutboundGroups, _selectedPreferredGroupTag);
        }

        using var form = new NodePickerForm(
            _coreClient,
            () => _coreOnline && _dashboardVpnRunning,
            _selectedProfileId,
            name,
            _selectedProfilePath,
            groupTag,
            _lastOutboundGroups,
            _lastUrlTestDelays,
            liveMeta);
        form.ShowDialog(this);

        RefreshDashboardNodeSnapshot();
    }

    private void OpenTrafficWindow()
    {
        if (_activeTrafficDetailsForm != null && !_activeTrafficDetailsForm.IsDisposed)
        {
            _activeTrafficDetailsForm.BringToFront();
            return;
        }

        _activeTrafficDetailsForm = new TrafficDetailsForm();
        _activeTrafficDetailsForm.FormClosed += (s, e) => _activeTrafficDetailsForm = null;
        _activeTrafficDetailsForm.UpdateData(_lastRuntimeStats, _dashboardUploadHistory, _dashboardDownloadHistory);
        _activeTrafficDetailsForm.Show(this);
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
        var stored = SelectedOutboundStore.Instance.Get(_selectedProfileId);
        var groupTag = stored?.GroupTag ?? string.Empty;
        if (string.IsNullOrWhiteSpace(groupTag))
        {
            groupTag = PickPreferredGroupTag(_lastOutboundGroups, _selectedPreferredGroupTag);
        }
        if (string.IsNullOrWhiteSpace(groupTag))
        {
            groupTag = _selectedProfileMeta.PickPreferredGroupTag();
        }

        if (string.IsNullOrWhiteSpace(groupTag))
        {
            _dashboardNodeNameLabel.Text = "meshflux node";
            _dashboardNodeEndpointLabel.Text = "0.0.0.0";
            return;
        }

        var group = _lastOutboundGroups.FirstOrDefault(g => string.Equals(g.Tag, groupTag, StringComparison.OrdinalIgnoreCase))
                    ?? (_groupByTag.TryGetValue(groupTag, out var g2) ? g2 : null);
        if (group == null)
        {
            // Offline: use profile metadata to render a reasonable snapshot.
            if (_selectedProfileMeta.GroupOutboundsByTag.TryGetValue(groupTag, out var outbounds) && outbounds.Count > 0)
            {
                var offlineSelectedOutbound = stored?.OutboundTag ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(offlineSelectedOutbound) && !outbounds.Any(o => string.Equals(o, offlineSelectedOutbound, StringComparison.OrdinalIgnoreCase)))
                {
                    offlineSelectedOutbound = string.Empty;
                }

                if (string.IsNullOrWhiteSpace(offlineSelectedOutbound) &&
                    _selectedProfileMeta.GroupDefaultOutboundByTag.TryGetValue(groupTag, out var def) &&
                    !string.IsNullOrWhiteSpace(def) &&
                    outbounds.Any(o => string.Equals(o, def, StringComparison.OrdinalIgnoreCase)))
                {
                    offlineSelectedOutbound = def;
                }

                if (string.IsNullOrWhiteSpace(offlineSelectedOutbound))
                {
                    offlineSelectedOutbound = outbounds[0] ?? string.Empty;
                }

                _dashboardNodeNameLabel.Text = string.IsNullOrWhiteSpace(offlineSelectedOutbound) ? groupTag : offlineSelectedOutbound;
                var offlineAddress = !string.IsNullOrWhiteSpace(offlineSelectedOutbound) &&
                                     _selectedProfileMeta.OutboundAddressByTag.TryGetValue(offlineSelectedOutbound, out var offlineAddr)
                    ? offlineAddr
                    : string.Empty;
                _dashboardNodeEndpointLabel.Text = string.IsNullOrWhiteSpace(offlineAddress) ? "0.0.0.0" : offlineAddress;
                return;
            }

            _dashboardNodeNameLabel.Text = groupTag;
            _dashboardNodeEndpointLabel.Text = "0.0.0.0";
            return;
        }

        var selectedOutbound = stored?.OutboundTag ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(selectedOutbound) && !(group.Items?.Any(i => string.Equals(i.Tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)) ?? false))
        {
            selectedOutbound = string.Empty;
        }

        if (string.IsNullOrWhiteSpace(selectedOutbound))
        {
            selectedOutbound = group.Selected ?? string.Empty;
        }

        if (string.IsNullOrWhiteSpace(selectedOutbound) && group.Items is { Count: > 0 })
        {
            selectedOutbound = group.Items[0].Tag ?? string.Empty;
        }

        _dashboardNodeNameLabel.Text = string.IsNullOrWhiteSpace(selectedOutbound)
            ? group.Tag
            : selectedOutbound;
        var address = !string.IsNullOrWhiteSpace(selectedOutbound) && _selectedProfileMeta.OutboundAddressByTag.TryGetValue(selectedOutbound, out var addr)
            ? addr
            : string.Empty;
        _dashboardNodeEndpointLabel.Text = string.IsNullOrWhiteSpace(address) ? "0.0.0.0" : address;
    }

    private static string PickPreferredGroupTag(List<CoreOutboundGroup> groups, string fallback)
    {
        if (!string.IsNullOrWhiteSpace(fallback) && groups.Any(g => string.Equals(g.Tag, fallback, StringComparison.OrdinalIgnoreCase)))
        {
            return fallback;
        }

        if (groups.Any(g => string.Equals(g.Tag, "proxy", StringComparison.OrdinalIgnoreCase)))
        {
            return "proxy";
        }

        if (groups.Any(g => string.Equals(g.Tag, "auto", StringComparison.OrdinalIgnoreCase)))
        {
            return "auto";
        }

        var firstSelectable = groups.FirstOrDefault(g => g.Selectable);
        if (firstSelectable != null) return firstSelectable.Tag;
        var first = groups.FirstOrDefault();
        return first?.Tag ?? string.Empty;
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



    private void InitializeMarketTab()
    {
        _marketHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _marketHeaderLabel.ForeColor = MeshAccentBlue;
        _marketHeaderLabel.SetBounds(22, 22, 180, 28);

        _marketTabOpenButton.SetBounds(210, 22, 110, 30);
        _marketTabOpenButton.FlatStyle = FlatStyle.Flat;
        _marketTabOpenButton.FlatAppearance.BorderSize = 0;
        _marketTabOpenButton.BackColor = Color.FromArgb(242, 242, 247); // macOS secondary button gray
        _marketTabOpenButton.ForeColor = Color.FromArgb(60, 60, 67);    // Darker text
        _marketTabOpenButton.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        _marketTabOpenButton.Click += async (_, _) => await OpenMarketWindow();

        _importProviderFileButton.SetBounds(330, 22, 100, 30); // Shifted right slightly
        _importProviderFileButton.FlatStyle = FlatStyle.Flat;
        _importProviderFileButton.FlatAppearance.BorderSize = 0;
        _importProviderFileButton.BackColor = MeshAccentBlue;
        _importProviderFileButton.ForeColor = Color.White;
        _importProviderFileButton.Font = new Font("Segoe UI", 9F, FontStyle.Bold);

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
        
        // Baseline and grid
        using (var baselinePen = new Pen(Color.FromArgb(228, 238, 248), 1F))
        {
            e.Graphics.DrawLine(baselinePen, rect.Left, rect.Bottom - 10, rect.Right, rect.Bottom - 10);
            e.Graphics.DrawLine(baselinePen, rect.Left, rect.Top + 10, rect.Right, rect.Top + 10);
        }

        if (_uploadSamples.Length < 2 && _downloadSamples.Length < 2)
        {
            return;
        }

        var maxValue = Math.Max(1024F, Math.Max(_uploadSamples.DefaultIfEmpty(0).Max(), _downloadSamples.DefaultIfEmpty(0).Max()));
        
        // Draw Up (Blue)
        DrawSeries(e.Graphics, _uploadSamples, Color.FromArgb(71, 167, 230), maxValue, rect, true);
        // Draw Down (Green)
        DrawSeries(e.Graphics, _downloadSamples, Color.FromArgb(60, 199, 128), maxValue, rect, true);
    }

    private static void DrawSeries(Graphics g, float[] samples, Color color, float maxValue, Rectangle rect, bool fill)
    {
        if (samples.Length < 2)
        {
            return;
        }

        var points = new PointF[samples.Length];
        var width = rect.Width;
        var height = rect.Height - 16;
        for (var i = 0; i < samples.Length; i++)
        {
            var x = rect.Left + (width * i / (samples.Length - 1f));
            var normalized = Math.Clamp(samples[i] / maxValue, 0F, 1F);
            var y = rect.Bottom - 4 - (height * normalized);
            points[i] = new PointF(x, y);
        }

        if (fill)
        {
            using var fillPath = new GraphicsPath();
            fillPath.AddLines(points);
            fillPath.AddLine(points.Last(), new PointF(points.Last().X, rect.Bottom));
            fillPath.AddLine(new PointF(points.First().X, rect.Bottom), points.First());
            fillPath.CloseFigure();

            using var fillBrush = new LinearGradientBrush(
                new Rectangle(0, rect.Top, 1, rect.Height),
                Color.FromArgb(40, color),
                Color.FromArgb(0, color),
                90F);
            g.FillPath(fillBrush, fillPath);
        }

        using var pen = new Pen(color, 2.0F) { LineJoin = LineJoin.Round };
        g.DrawLines(pen, points);
    }
}

internal sealed class TrafficBadgeLabel : Label
{
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Color MarkerColor { get; set; } = Color.DodgerBlue;

    public TrafficBadgeLabel()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        // Background
        using (var bgBrush = new SolidBrush(BackColor))
        {
            e.Graphics.FillRectangle(bgBrush, ClientRectangle);
        }

        // Dot indicator
        const int dotSize = 7;
        var dotX = Padding.Left + 2;
        var dotY = (Height - dotSize) / 2;
        using (var dotBrush = new SolidBrush(MarkerColor))
        {
            e.Graphics.FillEllipse(dotBrush, dotX, dotY, dotSize, dotSize);
        }

        // Text
        var textX = dotX + dotSize + 6;
        var textRect = new RectangleF(textX, 0, Width - textX - Padding.Right, Height);
        using var textBrush = new SolidBrush(ForeColor);
        using var sf = new StringFormat
        {
            Alignment = StringAlignment.Near,
            LineAlignment = StringAlignment.Center,
            Trimming = StringTrimming.EllipsisCharacter
        };
        e.Graphics.DrawString(Text, Font, textBrush, textRect, sf);
    }
}
