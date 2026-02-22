using System.Drawing;

namespace OpenMeshWin;

public partial class Form1 : Form
{
    private bool _exitRequested;

    public Form1()
    {
        InitializeComponent();
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();
        trayOpenMenuItem.Click += (_, _) => ShowMainWindow();
        trayExitMenuItem.Click += (_, _) => ExitApplication();

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
            }
            else
            {
                trayIcon.Visible = false;
            }
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
        _exitRequested = true;
        Close();
    }
}
