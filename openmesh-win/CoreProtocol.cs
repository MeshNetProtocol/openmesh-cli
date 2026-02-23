namespace OpenMeshWin;

internal static class CoreProtocol
{
    public const string PipeName = "openmesh-win-core";
}

internal sealed class CoreRequest
{
    public string Action { get; set; } = string.Empty;
    public string ProfilePath { get; set; } = string.Empty;
    public string Group { get; set; } = string.Empty;
    public string Outbound { get; set; } = string.Empty;
    public string Search { get; set; } = string.Empty;
    public string SortBy { get; set; } = string.Empty;
    public bool Descending { get; set; }
    public int ConnectionId { get; set; }
    public string Password { get; set; } = string.Empty;
    public string Mnemonic { get; set; } = string.Empty;
    public string Network { get; set; } = string.Empty;
    public string TokenSymbol { get; set; } = string.Empty;
    public string Amount { get; set; } = string.Empty;
    public string To { get; set; } = string.Empty;
    public string Resource { get; set; } = string.Empty;
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
    public string Group { get; set; } = string.Empty;
    public Dictionary<string, int> Delays { get; set; } = [];
    public List<CoreOutboundGroup> OutboundGroups { get; set; } = [];
    public CoreRuntimeStats Runtime { get; set; } = new();
    public List<CoreConnection> Connections { get; set; } = [];
    public bool WalletExists { get; set; }
    public bool WalletUnlocked { get; set; }
    public string WalletAddress { get; set; } = string.Empty;
    public string WalletNetwork { get; set; } = string.Empty;
    public string WalletToken { get; set; } = string.Empty;
    public decimal WalletBalance { get; set; }
    public string GeneratedMnemonic { get; set; } = string.Empty;
    public string PaymentId { get; set; } = string.Empty;
    public string P3PreflightCheckedAtUtc { get; set; } = string.Empty;
    public bool P3Admin { get; set; }
    public bool P3WintunFound { get; set; }
    public string P3WintunPath { get; set; } = string.Empty;
    public bool P3NetworkPrepared { get; set; }
    public bool P3NetworkDryRun { get; set; }
    public string P3LastNetworkError { get; set; } = string.Empty;
    public string P3LastRollbackAtUtc { get; set; } = string.Empty;
    public List<string> P3AppliedCommands { get; set; } = [];
}

internal sealed class CoreOutboundGroup
{
    public string Tag { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string Selected { get; set; } = string.Empty;
    public bool Selectable { get; set; }
    public List<CoreOutboundGroupItem> Items { get; set; } = [];
}

internal sealed class CoreOutboundGroupItem
{
    public string Tag { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public int UrlTestDelay { get; set; }
}

internal sealed class CoreRuntimeStats
{
    public long TotalUploadBytes { get; set; }
    public long TotalDownloadBytes { get; set; }
    public long UploadRateBytesPerSec { get; set; }
    public long DownloadRateBytesPerSec { get; set; }
    public double MemoryMb { get; set; }
    public int ThreadCount { get; set; }
    public long UptimeSeconds { get; set; }
    public int ConnectionCount { get; set; }
}

internal sealed class CoreConnection
{
    public int Id { get; set; }
    public string ProcessName { get; set; } = string.Empty;
    public string Destination { get; set; } = string.Empty;
    public string Protocol { get; set; } = string.Empty;
    public string Outbound { get; set; } = string.Empty;
    public long UploadBytes { get; set; }
    public long DownloadBytes { get; set; }
    public string LastSeenUtc { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty;
}

internal sealed class CoreStartResult
{
    public bool Started { get; set; }
    public bool AlreadyRunning { get; set; }
    public string Message { get; set; } = string.Empty;
}
