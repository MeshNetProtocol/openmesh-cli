namespace OpenMeshWin;

internal sealed class AppSettings
{
    public bool AutoStartCore { get; set; } = true;
    public bool AutoConnectVpn { get; set; }
    public bool HideToTrayOnClose { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public bool StopLocalCoreOnExit { get; set; } = true;

    public static AppSettings Default => new();
}
