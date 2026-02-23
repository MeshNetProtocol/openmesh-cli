namespace OpenMeshWin;

internal static class CoreProtocol
{
    public const string PipeName = "openmesh-win-core";
}

internal sealed class CoreRequest
{
    public string Action { get; set; } = string.Empty;
    public string ProfilePath { get; set; } = string.Empty;
}

internal sealed class CoreResponse
{
    public bool Ok { get; set; }
    public string Message { get; set; } = string.Empty;
    public bool CoreRunning { get; set; }
    public bool VpnRunning { get; set; }
    public string StartedAtUtc { get; set; } = string.Empty;
    public string ProfilePath { get; set; } = string.Empty;
    public string EffectiveConfigPath { get; set; } = string.Empty;
    public string LastConfigHash { get; set; } = string.Empty;
    public int InjectedRuleCount { get; set; }
    public string LastReloadAtUtc { get; set; } = string.Empty;
    public string LastReloadError { get; set; } = string.Empty;
}

internal sealed class CoreStartResult
{
    public bool Started { get; set; }
    public bool AlreadyRunning { get; set; }
    public string Message { get; set; } = string.Empty;
}
