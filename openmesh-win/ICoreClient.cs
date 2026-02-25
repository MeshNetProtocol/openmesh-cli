namespace OpenMeshWin;

internal interface ICoreClient
{
    string BackendName { get; }

    Task<CoreResponse> PingAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> GetStatusAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> StartVpnAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> ReloadAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> SetProfileAsync(string profilePath, CancellationToken cancellationToken = default);
    Task<CoreResponse> UrlTestAsync(string group, CancellationToken cancellationToken = default);
    Task<CoreResponse> SelectOutboundAsync(string group, string outbound, CancellationToken cancellationToken = default);
    Task<CoreResponse> GetConnectionsAsync(string search, string sortBy, bool descending, CancellationToken cancellationToken = default);
    Task<CoreResponse> CloseConnectionAsync(int connectionId, CancellationToken cancellationToken = default);
    Task<CoreResponse> GenerateMnemonicAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> CreateWalletAsync(string mnemonic, string password, CancellationToken cancellationToken = default);
    Task<CoreResponse> UnlockWalletAsync(string password, CancellationToken cancellationToken = default);
    Task<CoreResponse> GetWalletBalanceAsync(string network, string tokenSymbol, CancellationToken cancellationToken = default);
    Task<CoreResponse> MakeX402PaymentAsync(string to, string resource, string amount, string password, CancellationToken cancellationToken = default);
    Task<CoreResponse> GetProviderMarketAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> InstallProviderAsync(string providerId, CancellationToken cancellationToken = default);
    Task<CoreResponse> UninstallProviderAsync(string providerId, CancellationToken cancellationToken = default);
    Task<CoreResponse> ActivateProviderAsync(string providerId, CancellationToken cancellationToken = default);
    Task<CoreResponse> UpgradeProviderAsync(string providerId, CancellationToken cancellationToken = default);
    Task<CoreResponse> ImportProviderFromFileAsync(string importPath, CancellationToken cancellationToken = default);
    Task<CoreResponse> ImportProviderFromUrlAsync(string importUrl, CancellationToken cancellationToken = default);
    Task<CoreResponse> ImportProviderFromTextAsync(string importContent, CancellationToken cancellationToken = default);
    Task<CoreResponse> ImportAndInstallProviderAsync(string importContent, CancellationToken cancellationToken = default);
    Task<CoreResponse> StopVpnAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3NetworkPreflightAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3NetworkPrepareAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3NetworkRollbackAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3EngineProbeAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3EngineStartAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3EngineStopAsync(CancellationToken cancellationToken = default);
    Task<CoreResponse> P3EngineHealthAsync(CancellationToken cancellationToken = default);
    IAsyncEnumerable<CoreResponse> WatchStatusStreamAsync(int streamIntervalMs = 800, int streamMaxEvents = 0, bool streamHeartbeatEnabled = true, CancellationToken cancellationToken = default);
    IAsyncEnumerable<CoreResponse> WatchConnectionsStreamAsync(string search = "", string sortBy = "last_seen", bool descending = true, int streamIntervalMs = 900, int streamMaxEvents = 0, bool streamHeartbeatEnabled = true, CancellationToken cancellationToken = default);
    IAsyncEnumerable<CoreResponse> WatchGroupsStreamAsync(int streamIntervalMs = 900, int streamMaxEvents = 0, bool streamHeartbeatEnabled = true, CancellationToken cancellationToken = default);
    Task<CoreResponse> SendAsync(string action, CancellationToken cancellationToken = default);
    Task<CoreResponse> SendAsync(CoreRequest request, CancellationToken cancellationToken = default);
}
