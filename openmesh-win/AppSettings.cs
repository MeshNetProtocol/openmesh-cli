namespace OpenMeshWin;

internal sealed class AppSettings
{
    public const string CoreModeEmbedded = "embedded";

    public bool AutoStartCore { get; set; } = true;
    public bool AutoConnectVpn { get; set; }
    public bool HideToTrayOnClose { get; set; } = true;
    public bool AutoRecoverCore { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public bool StopLocalCoreOnExit { get; set; } = true;
    public string CoreMode { get; set; } = CoreModeEmbedded;
    public bool P5BalanceReal { get; set; }
    public bool P5BalanceStrict { get; set; }
    public bool P5X402Real { get; set; }
    public bool P5X402Strict { get; set; }
    public string UnmatchedTrafficOutbound { get; set; } = "direct";

    public string GetNormalizedCoreMode()
    {
        return CoreModeEmbedded;
    }

    public static AppSettings Default => new();
}
