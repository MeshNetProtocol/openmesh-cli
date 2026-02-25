namespace OpenMeshWin;

static class Program
{
    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        AppLogger.Log("Application bootstrap started.");
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
        {
            AppLogger.Log($"UI thread exception: {e.Exception}");
            MessageBox.Show(
                $"Unhandled UI exception: {e.Exception.Message}",
                "OpenMeshWin",
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
}
