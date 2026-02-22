namespace OpenMeshWin;

partial class Form1
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
    private ToolStripMenuItem trayRefreshMenuItem;
    private ToolStripSeparator traySeparatorMenuItem;
    private ToolStripMenuItem trayExitMenuItem;
    private Label coreStatusTitleLabel;
    private Label coreStatusValueLabel;
    private Label vpnStatusTitleLabel;
    private Label vpnStatusValueLabel;
    private Button startCoreButton;
    private Button startVpnButton;
    private Button stopVpnButton;
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
        trayRefreshMenuItem = new ToolStripMenuItem();
        traySeparatorMenuItem = new ToolStripSeparator();
        trayExitMenuItem = new ToolStripMenuItem();
        trayIcon = new NotifyIcon(components);
        coreStatusTitleLabel = new Label();
        coreStatusValueLabel = new Label();
        vpnStatusTitleLabel = new Label();
        vpnStatusValueLabel = new Label();
        startCoreButton = new Button();
        startVpnButton = new Button();
        stopVpnButton = new Button();
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
            trayRefreshMenuItem,
            traySeparatorMenuItem,
            trayExitMenuItem
        });
        trayMenu.Name = "trayMenu";
        trayMenu.Size = new Size(130, 120);

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
        coreStatusTitleLabel.Location = new Point(24, 24);
        coreStatusTitleLabel.Name = "coreStatusTitleLabel";
        coreStatusTitleLabel.Size = new Size(70, 15);
        coreStatusTitleLabel.TabIndex = 0;
        coreStatusTitleLabel.Text = "Core Status:";

        // coreStatusValueLabel
        coreStatusValueLabel.AutoSize = true;
        coreStatusValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        coreStatusValueLabel.Location = new Point(124, 24);
        coreStatusValueLabel.Name = "coreStatusValueLabel";
        coreStatusValueLabel.Size = new Size(35, 15);
        coreStatusValueLabel.TabIndex = 1;
        coreStatusValueLabel.Text = "N/A";

        // vpnStatusTitleLabel
        vpnStatusTitleLabel.AutoSize = true;
        vpnStatusTitleLabel.Location = new Point(24, 50);
        vpnStatusTitleLabel.Name = "vpnStatusTitleLabel";
        vpnStatusTitleLabel.Size = new Size(67, 15);
        vpnStatusTitleLabel.TabIndex = 2;
        vpnStatusTitleLabel.Text = "VPN Status:";

        // vpnStatusValueLabel
        vpnStatusValueLabel.AutoSize = true;
        vpnStatusValueLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        vpnStatusValueLabel.Location = new Point(124, 50);
        vpnStatusValueLabel.Name = "vpnStatusValueLabel";
        vpnStatusValueLabel.Size = new Size(35, 15);
        vpnStatusValueLabel.TabIndex = 3;
        vpnStatusValueLabel.Text = "N/A";

        // startCoreButton
        startCoreButton.Location = new Point(24, 82);
        startCoreButton.Name = "startCoreButton";
        startCoreButton.Size = new Size(112, 30);
        startCoreButton.TabIndex = 4;
        startCoreButton.Text = "Start Core";
        startCoreButton.UseVisualStyleBackColor = true;

        // startVpnButton
        startVpnButton.Location = new Point(150, 82);
        startVpnButton.Name = "startVpnButton";
        startVpnButton.Size = new Size(112, 30);
        startVpnButton.TabIndex = 5;
        startVpnButton.Text = "Start VPN";
        startVpnButton.UseVisualStyleBackColor = true;

        // stopVpnButton
        stopVpnButton.Location = new Point(276, 82);
        stopVpnButton.Name = "stopVpnButton";
        stopVpnButton.Size = new Size(112, 30);
        stopVpnButton.TabIndex = 6;
        stopVpnButton.Text = "Stop VPN";
        stopVpnButton.UseVisualStyleBackColor = true;

        // refreshStatusButton
        refreshStatusButton.Location = new Point(402, 82);
        refreshStatusButton.Name = "refreshStatusButton";
        refreshStatusButton.Size = new Size(112, 30);
        refreshStatusButton.TabIndex = 7;
        refreshStatusButton.Text = "Refresh";
        refreshStatusButton.UseVisualStyleBackColor = true;

        // logsTextBox
        logsTextBox.Location = new Point(24, 154);
        logsTextBox.Multiline = true;
        logsTextBox.Name = "logsTextBox";
        logsTextBox.ReadOnly = true;
        logsTextBox.ScrollBars = ScrollBars.Vertical;
        logsTextBox.Size = new Size(568, 240);
        logsTextBox.TabIndex = 9;
        logsTextBox.TabStop = false;

        // logsTitleLabel
        logsTitleLabel.AutoSize = true;
        logsTitleLabel.Location = new Point(24, 133);
        logsTitleLabel.Name = "logsTitleLabel";
        logsTitleLabel.Size = new Size(34, 15);
        logsTitleLabel.TabIndex = 8;
        logsTitleLabel.Text = "Logs:";

        // Form1
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(620, 420);
        Controls.Add(logsTextBox);
        Controls.Add(logsTitleLabel);
        Controls.Add(refreshStatusButton);
        Controls.Add(stopVpnButton);
        Controls.Add(startVpnButton);
        Controls.Add(startCoreButton);
        Controls.Add(vpnStatusValueLabel);
        Controls.Add(vpnStatusTitleLabel);
        Controls.Add(coreStatusValueLabel);
        Controls.Add(coreStatusTitleLabel);
        MaximizeBox = false;
        MinimizeBox = true;
        Name = "Form1";
        StartPosition = FormStartPosition.CenterScreen;
        Text = "OpenMesh Win - Phase 1";
        trayMenu.ResumeLayout(false);
        ResumeLayout(false);
        PerformLayout();
    }

    #endregion
}
