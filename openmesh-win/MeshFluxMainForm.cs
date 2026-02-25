using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;

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
    private readonly CoreClient _coreClient = new();
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
    private readonly TabPage _profilesTab = new("Profiles");
    private readonly TabPage _logsTab = new("Logs");
    private readonly Label _profilesHeaderLabel = new() { Text = "Profiles (Alignment Phase)" };
    private readonly Label _profilesHintLabel = new() { Text = "Current selected profile and installed providers." };
    private readonly ListBox _profilesListBox = new();
    private readonly Button _profilesRefreshButton = new() { Text = "Refresh Profiles", Width = 132, Height = 30 };
    private readonly Label _logsHeaderLabel = new() { Text = "Runtime Logs" };
    private readonly Button _openNodeWindowButton = new() { Text = "Node Details", Width = 118, Height = 30 };
    private readonly Button _openTrafficWindowButton = new() { Text = "Traffic Details", Width = 118, Height = 30 };
    private readonly Label _marketHeaderLabel = new() { Text = "Market + x402 (Phase 7)" };
    private readonly Label _walletBalanceTitleLabel = new() { Text = "Wallet Balance:" };
    private readonly Label _walletBalanceValueLabel = new() { Text = "USDC 0.00" };
    private readonly ListBox _marketListBox = new();
    private readonly SmoothFlowLayoutPanel _marketCardsPanel = new()
    {
        FlowDirection = FlowDirection.TopDown,
        WrapContents = false,
        AutoScroll = true
    };
    private readonly Panel _marketTopDivider = new() { Height = 1 };
    private readonly Button _refreshMarketButton = new() { Text = "Refresh Market", Width = 120, Height = 30 };
    private readonly TextBox _importProviderPathTextBox = new();
    private readonly Button _importProviderFileButton = new() { Text = "Import File", Width = 92, Height = 30 };
    private readonly Button _activateProviderButton = new() { Text = "Use Selected", Width = 124, Height = 30 };
    private readonly Button _installProviderButton = new() { Text = "Install Selected", Width = 124, Height = 30 };
    private readonly Button _uninstallProviderButton = new() { Text = "Uninstall Selected", Width = 132, Height = 30 };
    private readonly Label _settingsHeaderLabel = new() { Text = "Runtime Settings (Phase 5 Preview)" };
    private readonly Panel _settingsTopDivider = new() { Height = 1 };
    private readonly Label _settingsPageTitleLabel = new() { Text = "Settings" };
    private readonly Label _settingsStartAtLoginLabel = new() { Text = "Start at login" };
    private readonly CheckBox _settingsStartAtLoginToggle = new() { Text = "Off", AutoSize = false };
    private readonly Label _settingsUnmatchedLabel = new() { Text = "未命中流量出口" };
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
    private readonly Label _x402ToLabel = new() { Text = "To:" };
    private readonly TextBox _x402ToTextBox = new();
    private readonly Label _x402ResourceLabel = new() { Text = "Resource:" };
    private readonly TextBox _x402ResourceTextBox = new();
    private readonly Label _x402AmountLabel = new() { Text = "Amount:" };
    private readonly TextBox _x402AmountTextBox = new() { Text = "0.010000" };
    private readonly Button _x402PayButton = new() { Text = "Pay x402", Width = 104, Height = 30 };
    private readonly Label _x402LastPaymentLabel = new() { Text = "Last Payment: N/A" };
    private string _marketSelectedProviderId = string.Empty;
    private readonly MeshCardPanel _dashboardHeroCard = new();
    private readonly MeshCardPanel _dashboardTrafficCard = new();
    private readonly MeshCardPanel _dashboardNodeCard = new();
    private readonly PictureBox _dashboardLogoPictureBox = new() { SizeMode = PictureBoxSizeMode.Zoom };
    private readonly Label _dashboardAppNameLabel = new() { Text = "MeshFlux" };
    private readonly Label _dashboardVersionLabel = new() { Text = "1.0 (Windows)" };
    private readonly Label _dashboardProviderLabel = new() { Text = "流量商户" };
    private readonly ComboBox _dashboardProviderComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Label _dashboardUpBadgeLabel = new() { Text = "UP 0 B" };
    private readonly Label _dashboardDownBadgeLabel = new() { Text = "DOWN 0 B" };
    private readonly Label _dashboardNodeNameLabel = new() { Text = "meshflux node" };
    private readonly Label _dashboardNodeEndpointLabel = new() { Text = "0.0.0.0" };
    private readonly Label _dashboardNodeRateLabel = new() { Text = "UPLINK 0 KB/s  |  DOWNLINK 0 KB/s" };
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
    private bool _marketUiSyncInProgress;
    private string _settingsUnmatchedTrafficOutbound = "direct";
    private bool _settingsUiSyncInProgress;

    public MeshFluxMainForm()
    {
        InitializeComponent();
        InitializePhase5Shell();

        trayIcon.Icon = SystemIcons.Application;
        trayIcon.BalloonTipTitle = "OpenMesh";
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
        _refreshConnectionsButton.Click += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(appendLog: true, forceStreamRestart: true));
        _closeConnectionButton.Click += async (_, _) => await RunActionAsync(CloseSelectedConnectionAsync);
        _openNodeWindowButton.Click += (_, _) => OpenNodeWindow();
        _openTrafficWindowButton.Click += (_, _) => OpenTrafficWindow();
        _connectionSortComboBox.SelectedIndexChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(forceStreamRestart: true));
        _connectionDescCheckBox.CheckedChanged += async (_, _) => await RunActionAsync(() => RefreshConnectionsAsync(forceStreamRestart: true));
        _refreshMarketButton.Click += async (_, _) => await RunActionAsync(() => RefreshMarketAsync(appendLog: true));
        _importProviderFileButton.Click += async (_, _) => await RunActionAsync(ImportProviderFromFileAsync);
        _activateProviderButton.Click += async (_, _) => await RunActionAsync(ActivateSelectedProviderAsync);
        _installProviderButton.Click += async (_, _) => await RunActionAsync(InstallSelectedProviderAsync);
        _uninstallProviderButton.Click += async (_, _) => await RunActionAsync(UninstallSelectedProviderAsync);
        _saveSettingsButton.Click += (_, _) => SaveSettingsPreview();
        _refreshIntegrationButton.Click += (_, _) => RefreshIntegrationUi();
        _walletGenerateButton.Click += async (_, _) => await RunActionAsync(GenerateMnemonicAsync);
        _walletCreateButton.Click += async (_, _) => await RunActionAsync(CreateWalletAsync);
        _walletUnlockButton.Click += async (_, _) => await RunActionAsync(UnlockWalletAsync);
        _walletBalanceButton.Click += async (_, _) => await RunActionAsync(GetWalletBalanceAsync);
        _x402PayButton.Click += async (_, _) => await RunActionAsync(MakeX402PaymentAsync);
        _profilesRefreshButton.Click += (_, _) => RefreshProfilesOverview();
        _dashboardProviderComboBox.SelectedIndexChanged += (_, _) => SyncDashboardProviderSelectionToMarket();
        _settingsStartAtLoginToggle.CheckedChanged += (_, _) => ApplyStartAtLoginToggle();
        _settingsProxyButton.Click += (_, _) => SetSettingsUnmatchedTrafficOutbound("proxy", persist: true);
        _settingsDirectButton.Click += (_, _) => SetSettingsUnmatchedTrafficOutbound("direct", persist: true);
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
        _coreModeComboBox.SelectedItem = AppSettings.CoreModeMock;

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
        };
    }

    private void InitializePhase5Shell()
    {
        Text = "MeshFlux";
        ClientSize = new Size(430, 760);
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

        _mainTabControl.SetBounds(0, 0, 430, 760);
        _mainTabControl.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _mainTabControl.Appearance = TabAppearance.Normal;
        _mainTabControl.DrawMode = TabDrawMode.OwnerDrawFixed;
        _mainTabControl.SizeMode = TabSizeMode.Fixed;
        _mainTabControl.ItemSize = new Size(118, 34);
        _mainTabControl.Padding = new Point(20, 6);
        _mainTabControl.DrawItem -= MainTabControl_DrawItem;
        _mainTabControl.DrawItem += MainTabControl_DrawItem;

        _dashboardTab.BackColor = MeshPageBackground;
        _marketTab.BackColor = MeshPageBackground;
        _settingsTab.BackColor = MeshPageBackground;
        _profilesTab.BackColor = MeshPageBackground;
        _logsTab.BackColor = MeshPageBackground;
        _dashboardTab.AutoScroll = true;
        _marketTab.AutoScroll = true;
        _settingsTab.AutoScroll = true;

        _mainTabControl.TabPages.AddRange([_dashboardTab, _marketTab, _settingsTab]);
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
        MoveControlToLogs(logsTitleLabel);
        MoveControlToLogs(logsTextBox);
    }

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
        _openNodeWindowButton.SetBounds(24, 548, 118, 30);
        _openTrafficWindowButton.SetBounds(152, 548, 118, 30);
        _dashboardTab.Controls.Add(_openNodeWindowButton);
        _dashboardTab.Controls.Add(_openTrafficWindowButton);

        _marketTopDivider.SetBounds(14, 8, 392, 1);
        _marketTopDivider.BackColor = Color.FromArgb(205, 220, 233);

        _marketHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _marketHeaderLabel.Text = "推荐供应商";
        _marketHeaderLabel.SetBounds(14, 26, 180, 28);

        _walletBalanceTitleLabel.SetBounds(14, 54, 44, 18);
        _walletBalanceTitleLabel.Font = new Font("Segoe UI", 8.5F, FontStyle.Regular);
        _walletBalanceTitleLabel.Text = "余额:";
        _walletBalanceValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        _walletBalanceValueLabel.ForeColor = Color.FromArgb(18, 102, 83);
        _walletBalanceValueLabel.SetBounds(58, 53, 160, 20);

        _importProviderPathTextBox.SetBounds(14, 78, 270, 24);
        _importProviderPathTextBox.Text = @".\provider_market_import.json";
        _importProviderFileButton.SetBounds(322, 26, 84, 24);
        _importProviderFileButton.Text = "导入安装";
        _refreshMarketButton.SetBounds(226, 26, 90, 24);
        _refreshMarketButton.Text = "供应商市场";
        _activateProviderButton.SetBounds(322, 78, 84, 24);
        _installProviderButton.SetBounds(226, 78, 90, 24);
        _uninstallProviderButton.SetBounds(226, 104, 180, 22);

        _x402ToLabel.SetBounds(24, 94, 22, 20);
        _x402ToTextBox.SetBounds(50, 92, 190, 24);
        _x402ToTextBox.Text = "provider.openmesh";
        _x402ResourceLabel.SetBounds(252, 94, 58, 20);
        _x402ResourceTextBox.SetBounds(312, 92, 198, 24);
        _x402ResourceTextBox.Text = "/api/v1/relay";
        _x402AmountLabel.SetBounds(522, 94, 48, 20);
        _x402AmountTextBox.SetBounds(572, 92, 64, 24);
        _x402PayButton.SetBounds(24, 124, 104, 30);
        _x402LastPaymentLabel.SetBounds(138, 129, 538, 20);

        _marketListBox.SetBounds(14, 120, 392, 18);
        _marketListBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _marketListBox.Visible = false;
        _marketListBox.HorizontalScrollbar = true;
        _marketCardsPanel.SetBounds(14, 108, 392, 618);
        _marketCardsPanel.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _marketCardsPanel.Padding = new Padding(0, 0, 0, 8);

        _marketTab.Controls.Add(_marketTopDivider);
        _marketTab.Controls.Add(_marketHeaderLabel);
        _marketTab.Controls.Add(_walletBalanceTitleLabel);
        _marketTab.Controls.Add(_walletBalanceValueLabel);
        _marketTab.Controls.Add(_importProviderPathTextBox);
        _marketTab.Controls.Add(_importProviderFileButton);
        _marketTab.Controls.Add(_refreshMarketButton);
        _marketTab.Controls.Add(_activateProviderButton);
        _marketTab.Controls.Add(_installProviderButton);
        _marketTab.Controls.Add(_uninstallProviderButton);
        _marketTab.Controls.Add(_x402ToLabel);
        _marketTab.Controls.Add(_x402ToTextBox);
        _marketTab.Controls.Add(_x402ResourceLabel);
        _marketTab.Controls.Add(_x402ResourceTextBox);
        _marketTab.Controls.Add(_x402AmountLabel);
        _marketTab.Controls.Add(_x402AmountTextBox);
        _marketTab.Controls.Add(_x402PayButton);
        _marketTab.Controls.Add(_x402LastPaymentLabel);
        _marketTab.Controls.Add(_marketListBox);
        _marketTab.Controls.Add(_marketCardsPanel);
        _importProviderPathTextBox.Visible = false;
        _walletBalanceTitleLabel.Visible = false;
        _walletBalanceValueLabel.Visible = false;
        _x402ToLabel.Visible = false;
        _x402ToTextBox.Visible = false;
        _x402ResourceLabel.Visible = false;
        _x402ResourceTextBox.Visible = false;
        _x402AmountLabel.Visible = false;
        _x402AmountTextBox.Visible = false;
        _x402PayButton.Visible = false;
        _x402LastPaymentLabel.Visible = false;
        _activateProviderButton.Visible = false;
        _installProviderButton.Visible = false;
        _uninstallProviderButton.Visible = false;
        _marketListBox.SelectedIndexChanged += (_, _) =>
        {
            if (_marketUiSyncInProgress)
            {
                return;
            }

            RefreshMarketButtons();
            RefreshDashboardProviderOptions();
            BuildMarketCards();
        };
        _marketTab.Resize += (_, _) => ApplyMarketLayout();

        _settingsHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _settingsHeaderLabel.Text = "Runtime + Wallet + Installer Settings (Phase 7)";
        _settingsHeaderLabel.SetBounds(22, 22, 390, 28);

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

        _profilesHeaderLabel.Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold);
        _profilesHeaderLabel.SetBounds(22, 18, 320, 28);
        _profilesHintLabel.ForeColor = Color.FromArgb(92, 92, 104);
        _profilesHintLabel.SetBounds(24, 50, 520, 20);
        _profilesRefreshButton.SetBounds(544, 18, 132, 30);
        _profilesListBox.SetBounds(24, 78, 652, 614);
        _profilesListBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _profilesListBox.HorizontalScrollbar = true;

        _profilesTab.Controls.Add(_profilesHeaderLabel);
        _profilesTab.Controls.Add(_profilesHintLabel);
        _profilesTab.Controls.Add(_profilesRefreshButton);
        _profilesTab.Controls.Add(_profilesListBox);

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
        ApplyMarketLayout();
        RefreshMarketPreview();
        RefreshMarketButtons();
        RefreshProfilesOverview();
    }

    private void ApplyMeshFluxPalette()
    {
        _marketHeaderLabel.ForeColor = MeshAccentBlue;
        _settingsHeaderLabel.ForeColor = MeshTextPrimary;
        _walletBalanceValueLabel.ForeColor = Color.FromArgb(26, 128, 96);
        _profilesHintLabel.ForeColor = MeshTextMuted;
        _settingsHintLabel.ForeColor = MeshTextMuted;
        _integrationSectionTitleLabel.ForeColor = MeshTextPrimary;
        _walletSectionTitleLabel.ForeColor = MeshTextPrimary;

        _marketListBox.BackColor = MeshCardBackground;
        _profilesListBox.BackColor = MeshCardBackground;
        _urlTestResultListBox.BackColor = MeshCardBackground;
        _connectionListView.BackColor = MeshCardBackground;
        logsTextBox.BackColor = MeshCardBackground;
        _refreshMarketButton.FlatStyle = FlatStyle.Flat;
        _refreshMarketButton.FlatAppearance.BorderSize = 0;
        _refreshMarketButton.BackColor = Color.FromArgb(201, 220, 232);
        _refreshMarketButton.ForeColor = MeshTextPrimary;
        _refreshMarketButton.Font = new Font("Segoe UI Semibold", 8.3F, FontStyle.Bold);
        _importProviderFileButton.FlatStyle = FlatStyle.Flat;
        _importProviderFileButton.FlatAppearance.BorderSize = 0;
        _importProviderFileButton.BackColor = Color.FromArgb(65, 122, 223);
        _importProviderFileButton.ForeColor = Color.White;
        _importProviderFileButton.Font = new Font("Segoe UI Semibold", 8.3F, FontStyle.Bold);
        ApplyRoundedRegion(_refreshMarketButton, 8);
        ApplyRoundedRegion(_importProviderFileButton, 8);
        _settingsTopDivider.BackColor = Color.FromArgb(205, 220, 233);
        _settingsStartAtLoginToggle.ForeColor = MeshTextPrimary;
        _settingsOutboundSegmentPanel.BackColor = Color.FromArgb(201, 218, 230);
        RefreshSettingsAlignedUi();
    }

    private void InitializeDashboardCards()
    {
        _dashboardHeroCard.SetBounds(16, 18, 390, 116);
        _dashboardTrafficCard.SetBounds(16, 146, 390, 126);
        _dashboardNodeCard.SetBounds(16, 284, 390, 136);

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

        _dashboardLogoPictureBox.SetBounds(16, 18, 48, 48);
        TryLoadDashboardLogo();
        _dashboardHeroCard.Controls.Add(_dashboardLogoPictureBox);

        _dashboardAppNameLabel.Font = new Font("Segoe UI Semibold", 15F, FontStyle.Bold);
        _dashboardAppNameLabel.ForeColor = MeshAccentBlue;
        _dashboardAppNameLabel.SetBounds(74, 15, 170, 28);
        _dashboardHeroCard.Controls.Add(_dashboardAppNameLabel);

        _dashboardVersionLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _dashboardVersionLabel.ForeColor = MeshTextMuted;
        _dashboardVersionLabel.SetBounds(74, 42, 170, 20);
        _dashboardHeroCard.Controls.Add(_dashboardVersionLabel);

        vpnStatusTitleLabel.Text = "连接状态";
        vpnStatusTitleLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        vpnStatusTitleLabel.ForeColor = MeshTextMuted;
        vpnStatusTitleLabel.SetBounds(74, 64, 52, 20);
        MoveToCard(vpnStatusTitleLabel, _dashboardHeroCard);

        vpnStatusValueLabel.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
        vpnStatusValueLabel.SetBounds(128, 62, 108, 22);
        MoveToCard(vpnStatusValueLabel, _dashboardHeroCard);

        _dashboardProviderLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _dashboardProviderLabel.ForeColor = MeshTextMuted;
        _dashboardProviderLabel.SetBounds(246, 19, 100, 20);
        _dashboardHeroCard.Controls.Add(_dashboardProviderLabel);

        _dashboardProviderComboBox.SetBounds(246, 42, 130, 26);
        _dashboardHeroCard.Controls.Add(_dashboardProviderComboBox);

        startVpnButton.SetBounds(246, 74, 62, 30);
        startVpnButton.Text = "连接";
        MoveToCard(startVpnButton, _dashboardHeroCard);

        stopVpnButton.SetBounds(314, 74, 62, 30);
        stopVpnButton.Text = "断开";
        MoveToCard(stopVpnButton, _dashboardHeroCard);

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

        _dashboardUpBadgeLabel.SetBounds(18, 18, 120, 24);
        ConfigureTrafficBadge(_dashboardUpBadgeLabel, Color.FromArgb(86, 173, 228));
        _dashboardTrafficCard.Controls.Add(_dashboardUpBadgeLabel);

        _dashboardDownBadgeLabel.SetBounds(144, 18, 130, 24);
        ConfigureTrafficBadge(_dashboardDownBadgeLabel, Color.FromArgb(60, 199, 128));
        _dashboardTrafficCard.Controls.Add(_dashboardDownBadgeLabel);

        _trafficTitleLabel.Text = "实时流量";
        _trafficTitleLabel.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
        _trafficTitleLabel.SetBounds(18, 52, 70, 20);
        MoveToCard(_trafficTitleLabel, _dashboardTrafficCard);

        _trafficValueLabel.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
        _trafficValueLabel.SetBounds(18, 72, 354, 20);
        MoveToCard(_trafficValueLabel, _dashboardTrafficCard);

        _runtimeTitleLabel.Text = "运行状态";
        _runtimeTitleLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _runtimeTitleLabel.ForeColor = MeshTextMuted;
        _runtimeTitleLabel.SetBounds(18, 94, 64, 20);
        MoveToCard(_runtimeTitleLabel, _dashboardTrafficCard);

        _runtimeValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _runtimeValueLabel.SetBounds(84, 94, 288, 20);
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

        _openTrafficWindowButton.SetBounds(252, 56, 124, 32);
        _openTrafficWindowButton.Text = "More info";
        MoveToCard(_openTrafficWindowButton, _dashboardNodeCard);

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
        label.BackColor = Color.FromArgb(232, 243, 252);
        label.ForeColor = markerColor;
        label.TextAlign = ContentAlignment.MiddleCenter;
        label.Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold);
        label.Padding = new Padding(4, 0, 4, 0);
        label.BorderStyle = BorderStyle.FixedSingle;
    }

    private static void ApplyRoundedRegion(Control control, int radius)
    {
        var rect = new Rectangle(0, 0, Math.Max(1, control.Width), Math.Max(1, control.Height));
        using var path = CreateRoundedPath(rect, Math.Max(2, radius));
        control.Region = new Region(path);
    }

    private void MoveToCard(Control control, Control card)
    {
        if (control.Parent == card)
        {
            return;
        }

        if (control.Parent is not null)
        {
            control.Parent.Controls.Remove(control);
        }

        card.Controls.Add(control);
    }

    private void TryLoadDashboardLogo()
    {
        if (_dashboardLogoPictureBox.Image is not null)
        {
            return;
        }

        var logoPath = Path.Combine(AppContext.BaseDirectory, "assets", "meshflux", "mesh_logo_mark.png");
        if (!File.Exists(logoPath))
        {
            return;
        }

        try
        {
            _dashboardLogoPictureBox.Image = Image.FromFile(logoPath);
        }
        catch
        {
            // Keep text-only fallback when image loading fails.
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
        ScaleHorizontalLayout(_profilesTab, scale);
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
                    listView.Columns[listView.Columns.Count - 1].Width += (child.Width - 20) - nextLeft;
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
        _heartbeatWriter.Touch();
        LoadAndApplySettingsFromDisk();
        AppendLog($"core mode: {_appSettings.GetNormalizedCoreMode()}");
        AppendLog(
            $"p5 wallet bridge: balance_real={_appSettings.P5BalanceReal}, balance_strict={_appSettings.P5BalanceStrict}, x402_real={_appSettings.P5X402Real}, x402_strict={_appSettings.P5X402Strict}");
        RefreshIntegrationUi();

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

        var response = await _coreClient.StartVpnAsync();
        AppendLog($"start_vpn -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        await RefreshStatusAsync();
        EnsureStatusStreamRunning();
        EnsureConnectionsStreamRunning();
        EnsureGroupsStreamRunning();
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

    private async Task MakeX402PaymentAsync()
    {
        var to = _x402ToTextBox.Text.Trim();
        var resource = _x402ResourceTextBox.Text.Trim();
        var amount = _x402AmountTextBox.Text.Trim();
        var password = _walletPasswordTextBox.Text;

        var response = await _coreClient.MakeX402PaymentAsync(to, resource, amount, password);
        var paymentMode = string.IsNullOrWhiteSpace(response.PaymentMode) ? "unknown" : response.PaymentMode;
        AppendLog($"x402_pay -> {(response.Ok ? "ok" : "failed")} [{paymentMode}]: {response.Message}");
        if (response.Ok && !string.IsNullOrWhiteSpace(response.PaymentId))
        {
            _x402LastPaymentLabel.Text = $"Last Payment: {response.PaymentId} ({paymentMode})";
        }
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
        _lastConnections = (response.Connections ?? []).Select(CloneConnection).ToList();
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
                    _lastConnections = connections.Select(CloneConnection).ToList();
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
                    _lastOutboundGroups = groups.Select(CloneGroup).ToList();
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
                _marketOffers = status.Providers
                    .Select(offer => new CoreProviderOffer
                    {
                        Id = offer.Id,
                        Name = offer.Name,
                        Region = offer.Region,
                        PricePerGb = offer.PricePerGb,
                        PackageHash = offer.PackageHash,
                        Description = offer.Description
                    })
                    .ToList();
                _installedProviderIds = incomingInstalled;
                _marketSnapshotFingerprint = incomingFingerprint;
                RenderMarketOffers();
            }
        }

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
        _lastOutboundGroups = groups.Select(CloneGroup).ToList();
        _lastConnections = (status.Connections ?? []).Select(CloneConnection).ToList();
        BindOutboundGroups(groups);
        RefreshProfilesOverview();
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
        _walletBalanceValueLabel.Text = "USDC 0.00";
        _lastWalletBalance = 0m;
        _lastWalletToken = "USDC";
        _walletGenerateButton.Enabled = false;
        _walletCreateButton.Enabled = false;
        _walletUnlockButton.Enabled = false;
        _walletBalanceButton.Enabled = false;
        _x402PayButton.Enabled = false;
        RefreshMarketButtons();
        _lastKnownProfilePath = string.Empty;
        _dashboardProviderComboBox.Items.Clear();
        _dashboardProviderComboBox.Enabled = false;
        _dashboardNodeNameLabel.Text = "meshflux node";
        _dashboardNodeEndpointLabel.Text = "0.0.0.0";
        _dashboardNodeRateLabel.Text = "UPLINK 0 B/s  |  DOWNLINK 0 B/s";
        RefreshProfilesOverview();
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
        _runtimeValueLabel.Text = $"Memory {runtime.MemoryMb:F2} MB | Threads {runtime.ThreadCount} | Uptime {runtime.UptimeSeconds}s | Conns {runtime.ConnectionCount}";
        _dashboardUpBadgeLabel.Text = $"UP  {FormatBytes(runtime.TotalUploadBytes)}";
        _dashboardDownBadgeLabel.Text = $"DOWN  {FormatBytes(runtime.TotalDownloadBytes)}";
        _dashboardNodeRateLabel.Text =
            $"UPLINK {FormatRate(runtime.UploadRateBytesPerSec)}  |  DOWNLINK {FormatRate(runtime.DownloadRateBytesPerSec)}";
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
        _walletBalanceValueLabel.Text = $"{token} {response.WalletBalance:F4}";
        _lastWalletBalance = response.WalletBalance;
        _lastWalletToken = token;

        _walletGenerateButton.Enabled = _coreOnline;
        _walletCreateButton.Enabled = _coreOnline;
        _walletUnlockButton.Enabled = _coreOnline && response.WalletExists;
        _walletBalanceButton.Enabled = _coreOnline && response.WalletExists;
        _x402PayButton.Enabled = _coreOnline && response.WalletExists;
        RefreshMarketButtons();
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

    private async Task RefreshMarketAsync(bool appendLog = false)
    {
        if (!_coreOnline)
        {
            RefreshMarketPreview();
            RefreshMarketButtons();
            return;
        }

        var response = await _coreClient.GetProviderMarketAsync();
        if (appendLog)
        {
            AppendLog($"provider_market_list -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        }

        if (!response.Ok || response.Providers.Count == 0)
        {
            RefreshMarketPreview();
            RefreshMarketButtons();
            return;
        }

        _marketOffers = response.Providers;
        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        RenderMarketOffers();
    }

    private async Task InstallSelectedProviderAsync()
    {
        if (!_coreOnline)
        {
            AppendLog("provider_install skipped: core is offline.");
            return;
        }

        var offer = GetSelectedMarketOffer();
        if (offer is null)
        {
            AppendLog("provider_install skipped: no provider selected.");
            return;
        }

        var response = await _coreClient.InstallProviderAsync(offer.Id);
        AppendLog($"provider_install({offer.Id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (!response.Ok)
        {
            return;
        }

        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        RenderMarketOffers(selectedProviderId: offer.Id);
    }

    private async Task UninstallSelectedProviderAsync()
    {
        if (!_coreOnline)
        {
            AppendLog("provider_uninstall skipped: core is offline.");
            return;
        }

        var offer = GetSelectedMarketOffer();
        if (offer is null)
        {
            AppendLog("provider_uninstall skipped: no provider selected.");
            return;
        }

        var response = await _coreClient.UninstallProviderAsync(offer.Id);
        AppendLog($"provider_uninstall({offer.Id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (!response.Ok)
        {
            return;
        }

        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        RenderMarketOffers(selectedProviderId: offer.Id);
    }

    private async Task ActivateSelectedProviderAsync()
    {
        if (!_coreOnline)
        {
            AppendLog("provider_activate skipped: core is offline.");
            return;
        }

        var offer = GetSelectedMarketOffer();
        if (offer is null)
        {
            AppendLog("provider_activate skipped: no provider selected.");
            return;
        }

        var response = await _coreClient.ActivateProviderAsync(offer.Id);
        AppendLog($"provider_activate({offer.Id}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (!response.Ok)
        {
            return;
        }

        UpdateStatusUi(response);
        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        RenderMarketOffers(selectedProviderId: offer.Id);
    }

    private async Task ImportProviderFromFileAsync()
    {
        if (!_coreOnline)
        {
            AppendLog("provider_import_file skipped: core is offline.");
            return;
        }

        var importPath = _importProviderPathTextBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(importPath) || !File.Exists(importPath))
        {
            using var picker = new OpenFileDialog
            {
                Title = "Select provider package/json",
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                RestoreDirectory = true
            };

            if (picker.ShowDialog(this) != DialogResult.OK)
            {
                AppendLog("provider_import_file cancelled by user.");
                return;
            }

            importPath = picker.FileName;
            _importProviderPathTextBox.Text = importPath;
        }

        if (string.IsNullOrWhiteSpace(importPath))
        {
            AppendLog("provider_import_file skipped: import path is empty.");
            return;
        }

        var response = await _coreClient.ImportProviderFromFileAsync(importPath);
        AppendLog($"provider_import_file({importPath}) -> {(response.Ok ? "ok" : "failed")}: {response.Message}");
        if (!response.Ok)
        {
            return;
        }

        _marketOffers = response.Providers;
        _installedProviderIds = new HashSet<string>(response.InstalledProviderIds, StringComparer.OrdinalIgnoreCase);
        RenderMarketOffers();
    }

    private CoreProviderOffer? GetSelectedMarketOffer()
    {
        var selectedIndex = _marketListBox.SelectedIndex;
        if (selectedIndex < 0 || selectedIndex >= _marketOffers.Count)
        {
            return null;
        }

        return _marketOffers[selectedIndex];
    }

    private void RenderMarketOffers(string selectedProviderId = "")
    {
        _marketSnapshotFingerprint = BuildMarketSnapshotFingerprint(_marketOffers, _installedProviderIds);
        var prevSelectedProviderId = selectedProviderId;
        if (string.IsNullOrWhiteSpace(prevSelectedProviderId))
        {
            var selected = GetSelectedMarketOffer();
            prevSelectedProviderId = selected?.Id ?? string.Empty;
        }

        _marketUiSyncInProgress = true;
        try
        {
            _marketListBox.BeginUpdate();
            _marketListBox.Items.Clear();
            foreach (var offer in _marketOffers)
            {
                var installed = _installedProviderIds.Contains(offer.Id);
                var marker = installed ? "[INSTALLED]" : "[AVAILABLE]";
                _marketListBox.Items.Add(
                    $"{marker} {offer.Name}  ({offer.Region})  {offer.PricePerGb:F3} USDC/GB  id={offer.Id}");
            }
            _marketListBox.EndUpdate();

            var selectedIndex = -1;
            if (!string.IsNullOrWhiteSpace(prevSelectedProviderId))
            {
                selectedIndex = _marketOffers.FindIndex(x => string.Equals(x.Id, prevSelectedProviderId, StringComparison.OrdinalIgnoreCase));
            }
            if (selectedIndex < 0 && _marketOffers.Count > 0)
            {
                selectedIndex = 0;
            }
            if (selectedIndex >= 0)
            {
                _marketListBox.SelectedIndex = selectedIndex;
                _marketSelectedProviderId = _marketOffers[selectedIndex].Id;
            }
            else
            {
                _marketSelectedProviderId = string.Empty;
            }
        }
        finally
        {
            _marketUiSyncInProgress = false;
        }

        _walletBalanceValueLabel.Text = $"{_lastWalletToken} {_lastWalletBalance:F4}";
        RefreshDashboardProviderOptions();
        BuildMarketCards();
        RefreshMarketButtons();
        RefreshProfilesOverview();
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

    private void RefreshProfilesOverview()
    {
        _profilesListBox.BeginUpdate();
        _profilesListBox.Items.Clear();

        var profilePath = string.IsNullOrWhiteSpace(_lastKnownProfilePath)
            ? "N/A"
            : _lastKnownProfilePath;
        _profilesListBox.Items.Add($"Current Profile: {profilePath}");
        _profilesListBox.Items.Add($"Core Online: {_coreOnline}");
        _profilesListBox.Items.Add(string.Empty);

        if (_installedProviderIds.Count == 0)
        {
            _profilesListBox.Items.Add("Installed Providers: (none)");
        }
        else
        {
            _profilesListBox.Items.Add($"Installed Providers ({_installedProviderIds.Count}):");
            foreach (var id in _installedProviderIds.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                var offer = _marketOffers.FirstOrDefault(x => string.Equals(x.Id, id, StringComparison.OrdinalIgnoreCase));
                var line = offer is null
                    ? $"- {id}"
                    : $"- {offer.Name} ({offer.Region})  id={offer.Id}";
                _profilesListBox.Items.Add(line);
            }
        }

        _profilesListBox.EndUpdate();
    }

    private void RefreshMarketPreview()
    {
        var totalGb = (_lastRuntimeStats.TotalUploadBytes + _lastRuntimeStats.TotalDownloadBytes) / 1024d / 1024d / 1024d;
        var estimatedCost = totalGb * 0.028d;
        _marketOffers = [];
        _installedProviderIds.Clear();

        _marketListBox.BeginUpdate();
        _marketListBox.Items.Clear();
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] x402 edge.us-east-1.openmesh  0.024 USDC/GB");
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] x402 edge.us-west-2.openmesh  0.021 USDC/GB");
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] Premium route: gaming-low-latency    0.040 USDC/GB");
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] Shared route: ai-balanced          0.028 USDC/GB");
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] Wallet endpoint: Base testnet available");
        _marketListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] Estimated spend by traffic snapshot: {estimatedCost:F4} USDC");
        _marketListBox.EndUpdate();

        _marketOffers =
        [
            new CoreProviderOffer
            {
                Id = "preview-ai",
                Name = "AI 加速-仅示例",
                Region = "OpenMesh Team",
                PricePerGb = 0.028m,
                Description = "AI 加速服务专属配置，仅配置作展示，非商业用途，请勿滥用。"
            },
            new CoreProviderOffer
            {
                Id = "preview-default",
                Name = "通用加速-仅示例",
                Region = "OpenMesh Team",
                PricePerGb = 0.024m,
                Description = "本配置文件仅用于展示，非商业用途，请勿滥用。"
            }
        ];
        _marketSelectedProviderId = _marketOffers[0].Id;
        _marketListBox.SelectedIndex = 0;
        _walletBalanceValueLabel.Text = $"{_lastWalletToken} {_lastWalletBalance:F4}";
        RefreshDashboardProviderOptions();
        BuildMarketCards();
        RefreshMarketButtons();
    }

    private void RefreshDashboardProviderOptions()
    {
        var selectedOffer = GetSelectedMarketOffer();
        var selectedProviderId = selectedOffer?.Id ?? string.Empty;

        _dashboardProviderComboBox.BeginUpdate();
        _dashboardProviderComboBox.Items.Clear();
        foreach (var offer in _marketOffers)
        {
            _dashboardProviderComboBox.Items.Add(offer.Name);
        }
        _dashboardProviderComboBox.EndUpdate();

        if (_dashboardProviderComboBox.Items.Count == 0)
        {
            _dashboardProviderComboBox.Enabled = false;
            return;
        }

        _dashboardProviderComboBox.Enabled = true;
        var selectedIndex = 0;
        if (!string.IsNullOrWhiteSpace(selectedProviderId))
        {
            var found = _marketOffers.FindIndex(x => string.Equals(x.Id, selectedProviderId, StringComparison.OrdinalIgnoreCase));
            if (found >= 0)
            {
                selectedIndex = found;
            }
        }

        if (_dashboardProviderComboBox.SelectedIndex != selectedIndex)
        {
            _dashboardProviderComboBox.SelectedIndex = selectedIndex;
        }
    }

    private void ApplyMarketLayout()
    {
        var pageWidth = _marketTab.ClientSize.Width;
        var pageHeight = _marketTab.ClientSize.Height;
        if (pageWidth <= 60 || pageHeight <= 80)
        {
            return;
        }

        const int left = 14;
        const int right = 14;
        var contentWidth = Math.Max(220, pageWidth - left - right);

        _marketTopDivider.SetBounds(left, 8, contentWidth, 1);
        _marketHeaderLabel.SetBounds(left, 26, 180, 28);

        const int importButtonWidth = 96;
        const int marketButtonWidth = 90;
        const int buttonGap = 8;
        var importButtonLeft = left + contentWidth - importButtonWidth;
        var marketButtonLeft = importButtonLeft - buttonGap - marketButtonWidth;
        _refreshMarketButton.SetBounds(marketButtonLeft, 26, marketButtonWidth, 24);
        _importProviderFileButton.SetBounds(importButtonLeft, 26, importButtonWidth, 24);

        _marketCardsPanel.SetBounds(left, 64, contentWidth, Math.Max(120, pageHeight - 72));
        _marketListBox.SetBounds(left, 64, contentWidth, 18);
        BuildMarketCards();
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

    private void SyncDashboardProviderSelectionToMarket()
    {
        var index = _dashboardProviderComboBox.SelectedIndex;
        if (index < 0 || index >= _marketOffers.Count)
        {
            return;
        }

        if (_marketListBox.SelectedIndex != index)
        {
            _marketListBox.SelectedIndex = index;
        }
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

    private void RefreshMarketButtons()
    {
        var offer = GetSelectedMarketOffer();
        var hasOffer = offer is not null;
        var installed = hasOffer && _installedProviderIds.Contains(offer!.Id);

        _refreshMarketButton.Enabled = true;
        _importProviderFileButton.Enabled = _coreOnline;
        _importProviderPathTextBox.Enabled = _coreOnline;
        _activateProviderButton.Enabled = _coreOnline && hasOffer && installed;
        _installProviderButton.Enabled = _coreOnline && hasOffer && !installed;
        _uninstallProviderButton.Enabled = _coreOnline && hasOffer && installed;
    }

    private void BuildMarketCards()
    {
        _marketCardsPanel.SuspendLayout();
        _marketCardsPanel.Controls.Clear();

        if (_marketOffers.Count == 0)
        {
            var emptyLabel = new Label
            {
                AutoSize = false,
                Width = _marketCardsPanel.ClientSize.Width - 16,
                Height = 44,
                Text = "暂无推荐供应商，可点击上方“供应商市场/导入安装”。",
                ForeColor = MeshTextMuted,
                Font = new Font("Segoe UI", 9F, FontStyle.Regular),
                TextAlign = ContentAlignment.MiddleLeft
            };
            _marketCardsPanel.Controls.Add(emptyLabel);
            _marketCardsPanel.ResumeLayout();
            return;
        }

        foreach (var offer in _marketOffers)
        {
            var installed = _installedProviderIds.Contains(offer.Id);
            var card = new MeshCardPanel
            {
                Width = Math.Max(220, _marketCardsPanel.ClientSize.Width - 8),
                Height = 120,
                BackColor = Color.FromArgb(241, 248, 253),
                BorderColor = string.Equals(_marketSelectedProviderId, offer.Id, StringComparison.OrdinalIgnoreCase)
                    ? Color.FromArgb(146, 188, 218)
                    : Color.FromArgb(197, 216, 231),
                CornerRadius = 12,
                Margin = new Padding(0, 0, 0, 10),
                Padding = new Padding(10, 8, 10, 8)
            };

            var nameLabel = new Label
            {
                Text = offer.Name,
                Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold),
                ForeColor = MeshTextPrimary,
                AutoSize = false,
                Left = 10,
                Top = 10,
                Width = card.Width - 120,
                Height = 20
            };
            card.Controls.Add(nameLabel);

            var authorLabel = new Label
            {
                Text = offer.Region,
                Font = new Font("Segoe UI", 8.5F, FontStyle.Regular),
                ForeColor = MeshTextMuted,
                AutoSize = false,
                Left = 10,
                Top = 30,
                Width = card.Width - 120,
                Height = 18
            };
            card.Controls.Add(authorLabel);

            var descLabel = new Label
            {
                Text = string.IsNullOrWhiteSpace(offer.Description)
                    ? $"价格: {offer.PricePerGb:F3} USDC/GB"
                    : offer.Description,
                Font = new Font("Segoe UI", 8.8F, FontStyle.Regular),
                ForeColor = Color.FromArgb(78, 96, 114),
                AutoSize = false,
                Left = 10,
                Top = 50,
                Width = card.Width - 20,
                Height = 30
            };
            card.Controls.Add(descLabel);

            var tags = ResolveMarketTags(offer, installed);
            var tagLeft = 10;
            foreach (var tag in tags)
            {
                var tagLabel = new Label
                {
                    AutoSize = true,
                    Text = $" {tag} ",
                    Font = new Font("Segoe UI", 8F, FontStyle.Regular),
                    ForeColor = Color.FromArgb(98, 112, 127),
                    BackColor = Color.FromArgb(229, 236, 244),
                    Left = tagLeft,
                    Top = 86
                };
                card.Controls.Add(tagLabel);
                tagLeft += tagLabel.PreferredWidth + 6;
                tagLabel.Click += (_, _) => SelectMarketOfferById(offer.Id);
            }

            var actionButton = new Button
            {
                Width = 74,
                Height = 22,
                Left = card.Width - 84,
                Top = 10,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI Semibold", 8.5F, FontStyle.Bold),
                Text = installed ? "Reinstall" : "Install",
                BackColor = Color.FromArgb(86, 203, 228),
                ForeColor = Color.White,
                Tag = offer.Id
            };
            actionButton.FlatAppearance.BorderSize = 0;
            ApplyRoundedRegion(actionButton, 9);
            actionButton.Click += async (_, _) =>
            {
                if (actionButton.Tag is not string providerId)
                {
                    return;
                }

                SelectMarketOfferById(providerId);
                await RunActionAsync(InstallSelectedProviderAsync);
            };
            card.Controls.Add(actionButton);

            card.Click += (_, _) => SelectMarketOfferById(offer.Id);
            nameLabel.Click += (_, _) => SelectMarketOfferById(offer.Id);
            authorLabel.Click += (_, _) => SelectMarketOfferById(offer.Id);
            descLabel.Click += (_, _) => SelectMarketOfferById(offer.Id);
            _marketCardsPanel.Controls.Add(card);
        }

        _marketCardsPanel.ResumeLayout();
    }

    private static List<string> ResolveMarketTags(CoreProviderOffer offer, bool installed)
    {
        var tags = new List<string> { "Official" };
        var text = $"{offer.Name} {offer.Description}".ToLowerInvariant();
        if (text.Contains("ai"))
        {
            tags.Add("AI");
            tags.Add("SplitTunnel");
            tags.Add("ForceProxy");
            return tags;
        }

        if (installed)
        {
            tags.Add("AI");
            tags.Add("SplitTunnel");
            tags.Add("ForceProxy");
            return tags;
        }

        tags.Add("Online");
        return tags;
    }

    private void SelectMarketOfferById(string providerId)
    {
        if (string.IsNullOrWhiteSpace(providerId))
        {
            return;
        }

        var index = _marketOffers.FindIndex(x => string.Equals(x.Id, providerId, StringComparison.OrdinalIgnoreCase));
        if (index < 0)
        {
            return;
        }

        _marketSelectedProviderId = providerId;
        if (_marketListBox.SelectedIndex != index)
        {
            _marketListBox.SelectedIndex = index;
        }
        else
        {
            RefreshMarketButtons();
            BuildMarketCards();
        }
    }

    private void SaveSettingsPreview()
    {
        _appSettings.CoreMode = _coreModeComboBox.SelectedItem as string ?? AppSettings.CoreModeMock;
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
            Items = source.Items.Select(item => new CoreOutboundGroupItem
            {
                Tag = item.Tag,
                Type = item.Type,
                UrlTestDelay = item.UrlTestDelay
            }).ToList()
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
            logsTextBox.Lines = logsTextBox.Lines.Skip(Math.Max(0, logsTextBox.Lines.Length - 300)).ToArray();
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
