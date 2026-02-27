namespace OpenMeshWin;

partial class MeshFluxMainForm
{
    /// <summary>
    ///  Required designer variable.
    /// </summary>
    private System.ComponentModel.IContainer components = null;
    private NotifyIcon trayIcon;
    private ContextMenuStrip trayMenu;
    private ToolStripMenuItem trayOpenMenuItem;
    private ToolStripMenuItem trayStartVpnMenuItem;
    private ToolStripMenuItem trayStopVpnMenuItem;
    private ToolStripMenuItem trayReloadMenuItem;
    private ToolStripMenuItem trayRefreshMenuItem;
    private ToolStripSeparator traySeparatorMenuItem;
    private ToolStripMenuItem trayExitMenuItem;
    private Label coreStatusTitleLabel;
    private Label coreStatusValueLabel;
    private Label vpnStatusTitleLabel;
    private Label vpnStatusValueLabel;
    private Label profilePathTitleLabel;
    private Label profilePathValueLabel;
    private Label injectedRulesTitleLabel;
    private Label injectedRulesValueLabel;
    private Label configHashTitleLabel;
    private Label configHashValueLabel;
    private Button startCoreButton;
    private Button startVpnButton;
    private Button stopVpnButton;
    private Button reloadConfigButton;
    private Button refreshStatusButton;
    private TextBox logsTextBox;
    private Label logsTitleLabel;

    /// <summary>
    ///  Clean up any resources being used.
    /// </summary>
    /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
        {
            components.Dispose();
        }
        base.Dispose(disposing);
    }

    #region Windows Form Designer generated code

    /// <summary>
    ///  Required method for Designer support - do not modify
    ///  the contents of this method with the code editor.
    /// </summary>
    private void InitializeComponent()
    {
        components = new System.ComponentModel.Container();
        trayMenu = new ContextMenuStrip(components);
        trayOpenMenuItem = new ToolStripMenuItem();
        trayStartVpnMenuItem = new ToolStripMenuItem();
        trayStopVpnMenuItem = new ToolStripMenuItem();
        trayReloadMenuItem = new ToolStripMenuItem();
        trayRefreshMenuItem = new ToolStripMenuItem();
        traySeparatorMenuItem = new ToolStripSeparator();
        trayExitMenuItem = new ToolStripMenuItem();
        trayIcon = new NotifyIcon(components);
        coreStatusTitleLabel = new Label();
        coreStatusValueLabel = new Label();
        vpnStatusTitleLabel = new Label();
        vpnStatusValueLabel = new Label();
        profilePathTitleLabel = new Label();
        profilePathValueLabel = new Label();
        injectedRulesTitleLabel = new Label();
        injectedRulesValueLabel = new Label();
        configHashTitleLabel = new Label();
        configHashValueLabel = new Label();
        startCoreButton = new Button();
        startVpnButton = new Button();
        stopVpnButton = new Button();
        reloadConfigButton = new Button();
        refreshStatusButton = new Button();
        logsTextBox = new TextBox();
        logsTitleLabel = new Label();
        trayMenu.SuspendLayout();
        SuspendLayout();

        // trayMenu
        trayMenu.Items.AddRange(new ToolStripItem[]
        {
            trayOpenMenuItem,
            trayStartVpnMenuItem,
            trayStopVpnMenuItem,
            trayReloadMenuItem,
            trayRefreshMenuItem,
            traySeparatorMenuItem,
            trayExitMenuItem
        });
        trayMenu.Name = "trayMenu";
        trayMenu.Size = new Size(130, 142);

        // trayOpenMenuItem
        trayOpenMenuItem.Name = "trayOpenMenuItem";
        trayOpenMenuItem.Size = new Size(129, 22);
        trayOpenMenuItem.Text = "Open";

        // trayStartVpnMenuItem
        trayStartVpnMenuItem.Name = "trayStartVpnMenuItem";
        trayStartVpnMenuItem.Size = new Size(129, 22);
        trayStartVpnMenuItem.Text = "Start VPN";

        // trayStopVpnMenuItem
        trayStopVpnMenuItem.Name = "trayStopVpnMenuItem";
        trayStopVpnMenuItem.Size = new Size(129, 22);
        trayStopVpnMenuItem.Text = "Stop VPN";

        // trayReloadMenuItem
        trayReloadMenuItem.Name = "trayReloadMenuItem";
        trayReloadMenuItem.Size = new Size(129, 22);
        trayReloadMenuItem.Text = "Reload";

        // trayRefreshMenuItem
        trayRefreshMenuItem.Name = "trayRefreshMenuItem";
        trayRefreshMenuItem.Size = new Size(129, 22);
        trayRefreshMenuItem.Text = "Refresh";

        // traySeparatorMenuItem
        traySeparatorMenuItem.Name = "traySeparatorMenuItem";
        traySeparatorMenuItem.Size = new Size(126, 6);

        // trayExitMenuItem
        trayExitMenuItem.Name = "trayExitMenuItem";
        trayExitMenuItem.Size = new Size(129, 22);
        trayExitMenuItem.Text = "Exit";

        // trayIcon
        trayIcon.ContextMenuStrip = trayMenu;
        trayIcon.Text = "OpenMesh";
        trayIcon.Visible = true;

        // coreStatusTitleLabel
        coreStatusTitleLabel.AutoSize = true;
        coreStatusTitleLabel.Location = new Point(24, 20);
        coreStatusTitleLabel.Name = "coreStatusTitleLabel";
        coreStatusTitleLabel.Size = new Size(70, 15);
        coreStatusTitleLabel.TabIndex = 0;
        coreStatusTitleLabel.Text = "Core Status:";

        // coreStatusValueLabel
        coreStatusValueLabel.AutoSize = true;
        coreStatusValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        coreStatusValueLabel.Location = new Point(130, 20);
        coreStatusValueLabel.Name = "coreStatusValueLabel";
        coreStatusValueLabel.Size = new Size(35, 15);
        coreStatusValueLabel.TabIndex = 1;
        coreStatusValueLabel.Text = "N/A";

        // vpnStatusTitleLabel
        vpnStatusTitleLabel.AutoSize = true;
        vpnStatusTitleLabel.Location = new Point(24, 44);
        vpnStatusTitleLabel.Name = "vpnStatusTitleLabel";
        vpnStatusTitleLabel.Size = new Size(67, 15);
        vpnStatusTitleLabel.TabIndex = 2;
        vpnStatusTitleLabel.Text = "VPN Status:";

        // vpnStatusValueLabel
        vpnStatusValueLabel.AutoSize = true;
        vpnStatusValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        vpnStatusValueLabel.Location = new Point(130, 44);
        vpnStatusValueLabel.Name = "vpnStatusValueLabel";
        vpnStatusValueLabel.Size = new Size(35, 15);
        vpnStatusValueLabel.TabIndex = 3;
        vpnStatusValueLabel.Text = "N/A";

        // profilePathTitleLabel
        profilePathTitleLabel.AutoSize = true;
        profilePathTitleLabel.Location = new Point(24, 72);
        profilePathTitleLabel.Name = "profilePathTitleLabel";
        profilePathTitleLabel.Size = new Size(66, 15);
        profilePathTitleLabel.TabIndex = 4;
        profilePathTitleLabel.Text = "Profile Path:";

        // profilePathValueLabel
        profilePathValueLabel.AutoEllipsis = true;
        profilePathValueLabel.Location = new Point(130, 72);
        profilePathValueLabel.Name = "profilePathValueLabel";
        profilePathValueLabel.Size = new Size(540, 34);
        profilePathValueLabel.TabIndex = 5;
        profilePathValueLabel.Text = "N/A";

        // injectedRulesTitleLabel
        injectedRulesTitleLabel.AutoSize = true;
        injectedRulesTitleLabel.Location = new Point(24, 114);
        injectedRulesTitleLabel.Name = "injectedRulesTitleLabel";
        injectedRulesTitleLabel.Size = new Size(85, 15);
        injectedRulesTitleLabel.TabIndex = 6;
        injectedRulesTitleLabel.Text = "Injected Rules:";

        // injectedRulesValueLabel
        injectedRulesValueLabel.AutoSize = true;
        injectedRulesValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        injectedRulesValueLabel.Location = new Point(130, 114);
        injectedRulesValueLabel.Name = "injectedRulesValueLabel";
        injectedRulesValueLabel.Size = new Size(13, 15);
        injectedRulesValueLabel.TabIndex = 7;
        injectedRulesValueLabel.Text = "0";

        // configHashTitleLabel
        configHashTitleLabel.AutoSize = true;
        configHashTitleLabel.Location = new Point(24, 138);
        configHashTitleLabel.Name = "configHashTitleLabel";
        configHashTitleLabel.Size = new Size(72, 15);
        configHashTitleLabel.TabIndex = 8;
        configHashTitleLabel.Text = "Config Hash:";

        // configHashValueLabel
        configHashValueLabel.AutoEllipsis = true;
        configHashValueLabel.Location = new Point(130, 138);
        configHashValueLabel.Name = "configHashValueLabel";
        configHashValueLabel.Size = new Size(540, 15);
        configHashValueLabel.TabIndex = 9;
        configHashValueLabel.Text = "N/A";

        // startCoreButton
        startCoreButton.Location = new Point(24, 166);
        startCoreButton.Name = "startCoreButton";
        startCoreButton.Size = new Size(104, 30);
        startCoreButton.TabIndex = 10;
        startCoreButton.Text = "Start Core";
        startCoreButton.UseVisualStyleBackColor = true;

        // startVpnButton
        startVpnButton.Location = new Point(140, 166);
        startVpnButton.Name = "startVpnButton";
        startVpnButton.Size = new Size(104, 30);
        startVpnButton.TabIndex = 11;
        startVpnButton.Text = "Start VPN";
        startVpnButton.UseVisualStyleBackColor = true;

        // stopVpnButton
        stopVpnButton.Location = new Point(256, 166);
        stopVpnButton.Name = "stopVpnButton";
        stopVpnButton.Size = new Size(104, 30);
        stopVpnButton.TabIndex = 12;
        stopVpnButton.Text = "Stop VPN";
        stopVpnButton.UseVisualStyleBackColor = true;

        // reloadConfigButton
        reloadConfigButton.Location = new Point(372, 166);
        reloadConfigButton.Name = "reloadConfigButton";
        reloadConfigButton.Size = new Size(104, 30);
        reloadConfigButton.TabIndex = 13;
        reloadConfigButton.Text = "Reload Config";
        reloadConfigButton.UseVisualStyleBackColor = true;

        // refreshStatusButton
        refreshStatusButton.Location = new Point(488, 166);
        refreshStatusButton.Name = "refreshStatusButton";
        refreshStatusButton.Size = new Size(104, 30);
        refreshStatusButton.TabIndex = 14;
        refreshStatusButton.Text = "Refresh";
        refreshStatusButton.UseVisualStyleBackColor = true;

        // logsTextBox
        logsTextBox.Location = new Point(24, 226);
        logsTextBox.Multiline = true;
        logsTextBox.Name = "logsTextBox";
        logsTextBox.ReadOnly = true;
        logsTextBox.ScrollBars = ScrollBars.Vertical;
        logsTextBox.Size = new Size(646, 270);
        logsTextBox.TabIndex = 16;
        logsTextBox.TabStop = false;

        // logsTitleLabel
        logsTitleLabel.AutoSize = true;
        logsTitleLabel.Location = new Point(24, 206);
        logsTitleLabel.Name = "logsTitleLabel";
        logsTitleLabel.Size = new Size(34, 15);
        logsTitleLabel.TabIndex = 15;
        logsTitleLabel.Text = "Logs:";

        // MeshFluxMainForm
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(700, 520);
        Controls.Add(logsTextBox);
        Controls.Add(logsTitleLabel);
        Controls.Add(refreshStatusButton);
        Controls.Add(reloadConfigButton);
        Controls.Add(stopVpnButton);
        Controls.Add(startVpnButton);
        Controls.Add(startCoreButton);
        Controls.Add(configHashValueLabel);
        Controls.Add(configHashTitleLabel);
        Controls.Add(injectedRulesValueLabel);
        Controls.Add(injectedRulesTitleLabel);
        Controls.Add(profilePathValueLabel);
        Controls.Add(profilePathTitleLabel);
        Controls.Add(vpnStatusValueLabel);
        Controls.Add(vpnStatusTitleLabel);
        Controls.Add(coreStatusValueLabel);
        Controls.Add(coreStatusTitleLabel);
        MaximizeBox = false;
        MinimizeBox = true;
        Name = "MeshFluxMainForm";
        StartPosition = FormStartPosition.CenterScreen;
        Text = "OpenMesh Win - Phase 2";
        trayMenu.ResumeLayout(false);
        ResumeLayout(false);
        PerformLayout();
    }

    #endregion
}
