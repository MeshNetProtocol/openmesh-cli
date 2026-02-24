namespace OpenMeshWin;

internal sealed class AppSettings
{
    public const string CoreModeMock = "mock";
    public const string CoreModeGo = "go";

    public bool AutoStartCore { get; set; } = true;
    public bool AutoConnectVpn { get; set; }
    public bool HideToTrayOnClose { get; set; } = true;
    public bool AutoRecoverCore { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public bool StopLocalCoreOnExit { get; set; } = true;
    public string CoreMode { get; set; } = CoreModeMock;
    public bool P5BalanceReal { get; set; }
    public bool P5BalanceStrict { get; set; }
    public bool P5X402Real { get; set; }
    public bool P5X402Strict { get; set; }

    public string GetNormalizedCoreMode()
    {
        return string.Equals(CoreMode, CoreModeGo, StringComparison.OrdinalIgnoreCase)
            ? CoreModeGo
            : CoreModeMock;
    }

    public static AppSettings Default => new();
}
