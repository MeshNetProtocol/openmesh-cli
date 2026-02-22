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
    private ToolStripMenuItem trayExitMenuItem;

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
        trayExitMenuItem = new ToolStripMenuItem();
        trayIcon = new NotifyIcon(components);
        trayMenu.SuspendLayout();
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(600, 400);
        StartPosition = FormStartPosition.CenterScreen;
        Text = "OpenMesh";

        trayMenu.Items.AddRange(new ToolStripItem[] { trayOpenMenuItem, trayExitMenuItem });
        trayMenu.Name = "trayMenu";

        trayOpenMenuItem.Name = "trayOpenMenuItem";
        trayOpenMenuItem.Size = new Size(160, 22);
        trayOpenMenuItem.Text = "Open";

        trayExitMenuItem.Name = "trayExitMenuItem";
        trayExitMenuItem.Size = new Size(160, 22);
        trayExitMenuItem.Text = "Exit";

        trayIcon.ContextMenuStrip = trayMenu;
        trayIcon.Text = "OpenMesh";
        trayIcon.Visible = true;

        trayMenu.ResumeLayout(false);
    }

    #endregion
}
