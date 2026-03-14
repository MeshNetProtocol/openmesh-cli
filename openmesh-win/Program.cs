namespace OpenMeshWin;

static class Program
{
    private const int SW_RESTORE = 9;

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint hWnd);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(nint hWnd, int nCmdShow);

    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        using var singleInstanceMutex = new System.Threading.Mutex(true, MeshFluxPaths.SingleInstanceMutexName, out var createdNew);
        if (!createdNew)
        {
            TryActivateExistingInstanceWindow();
            return;
        }

        AppLogger.Log("Application bootstrap started.");
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
        {
            AppLogger.Log($"UI thread exception: {e.Exception}");
            MessageBox.Show(
                $"Unhandled UI exception: {e.Exception.Message}",
                MeshFluxPaths.ProductDisplayName,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            AppLogger.Log($"AppDomain unhandled exception: {e.ExceptionObject}");
        };
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            AppLogger.Log($"Task unobserved exception: {e.Exception}");
            e.SetObserved();
        };

        // To customize application configuration such as set high DPI settings or default font,
        // see https://aka.ms/applicationconfiguration.
        ApplicationConfiguration.Initialize();
        Application.Run(new MeshFluxMainForm());
        AppLogger.Log("Application exited.");
    }

    private static void TryActivateExistingInstanceWindow()
    {
        try
        {
            using var current = System.Diagnostics.Process.GetCurrentProcess();
            var running = System.Diagnostics.Process.GetProcessesByName(current.ProcessName);
            foreach (var process in running)
            {
                if (process.Id == current.Id)
                {
                    continue;
                }

                var handle = process.MainWindowHandle;
                if (handle == nint.Zero)
                {
                    continue;
                }

                _ = ShowWindowAsync(handle, SW_RESTORE);
                _ = SetForegroundWindow(handle);
                return;
            }
        }
        catch (Exception ex)
        {
            AppLogger.Log($"Failed to activate existing instance window: {ex}");
        }
    }
}
