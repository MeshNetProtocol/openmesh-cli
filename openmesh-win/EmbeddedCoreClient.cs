using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Runtime.CompilerServices;

namespace OpenMeshWin;

internal sealed class EmbeddedCoreClient : ICoreClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public string BackendName => "embedded";

    [DllImport("openmesh_core", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr om_request([MarshalAs(UnmanagedType.LPUTF8Str)] string requestJson);

    [DllImport("openmesh_core", CallingConvention = CallingConvention.Cdecl)]
    private static extern void om_free_string(IntPtr p);

    public Task<CoreResponse> PingAsync(CancellationToken cancellationToken = default) => SendAsync("ping", cancellationToken);
    public Task<CoreResponse> GetStatusAsync(CancellationToken cancellationToken = default) => SendAsync("status", cancellationToken);
    public Task<CoreResponse> StartVpnAsync(CancellationToken cancellationToken = default) => SendAsync("start_vpn", cancellationToken);
    public Task<CoreResponse> ReloadAsync(CancellationToken cancellationToken = default) => SendAsync("reload", cancellationToken);
    public Task<CoreResponse> SetProfileAsync(string profilePath, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "set_profile", ProfilePath = profilePath ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> UrlTestAsync(string group, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "urltest", Group = group ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> SelectOutboundAsync(string group, string outbound, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "select_outbound", Group = group ?? string.Empty, Outbound = outbound ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> GetConnectionsAsync(string search, string sortBy, bool descending, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "connections", Search = search ?? string.Empty, SortBy = sortBy ?? string.Empty, Descending = descending }, cancellationToken);
    public Task<CoreResponse> CloseConnectionAsync(int connectionId, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "close_connection", ConnectionId = connectionId }, cancellationToken);
    public Task<CoreResponse> GenerateMnemonicAsync(CancellationToken cancellationToken = default) => SendAsync("wallet_generate_mnemonic", cancellationToken);
    public Task<CoreResponse> CreateWalletAsync(string mnemonic, string password, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "wallet_create", Mnemonic = mnemonic ?? string.Empty, Password = password ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> UnlockWalletAsync(string password, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "wallet_unlock", Password = password ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> GetWalletBalanceAsync(string network, string tokenSymbol, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "wallet_balance", Network = network ?? string.Empty, TokenSymbol = tokenSymbol ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> MakeX402PaymentAsync(string to, string resource, string amount, string password, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "x402_pay", To = to ?? string.Empty, Resource = resource ?? string.Empty, Amount = amount ?? string.Empty, Password = password ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> GetProviderMarketAsync(CancellationToken cancellationToken = default) => SendAsync("provider_market_list", cancellationToken);
    public Task<CoreResponse> InstallProviderAsync(string providerId, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_install", ProviderId = providerId ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> UninstallProviderAsync(string providerId, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_uninstall", ProviderId = providerId ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> ActivateProviderAsync(string providerId, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_activate", ProviderId = providerId ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> UpgradeProviderAsync(string providerId, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_upgrade", ProviderId = providerId ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> ImportProviderFromFileAsync(string importPath, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_import_file", ImportPath = importPath ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> ImportProviderFromUrlAsync(string importUrl, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_import_url", ImportUrl = importUrl ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> ImportProviderFromTextAsync(string importContent, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_import_text", ImportContent = importContent ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> ImportAndInstallProviderAsync(string importContent, CancellationToken cancellationToken = default) => SendAsync(new CoreRequest { Action = "provider_import_install", ImportContent = importContent ?? string.Empty }, cancellationToken);
    public Task<CoreResponse> StopVpnAsync(CancellationToken cancellationToken = default) => SendAsync("stop_vpn", cancellationToken);
    public Task<CoreResponse> P3NetworkPreflightAsync(CancellationToken cancellationToken = default) => SendAsync("p3_network_preflight", cancellationToken);
    public Task<CoreResponse> P3NetworkPrepareAsync(CancellationToken cancellationToken = default) => SendAsync("p3_network_prepare", cancellationToken);
    public Task<CoreResponse> P3NetworkRollbackAsync(CancellationToken cancellationToken = default) => SendAsync("p3_network_rollback", cancellationToken);
    public Task<CoreResponse> P3EngineProbeAsync(CancellationToken cancellationToken = default) => SendAsync("p3_engine_probe", cancellationToken);
    public Task<CoreResponse> P3EngineStartAsync(CancellationToken cancellationToken = default) => SendAsync("p3_engine_start", cancellationToken);
    public Task<CoreResponse> P3EngineStopAsync(CancellationToken cancellationToken = default) => SendAsync("p3_engine_stop", cancellationToken);
    public Task<CoreResponse> P3EngineHealthAsync(CancellationToken cancellationToken = default) => SendAsync("p3_engine_health", cancellationToken);

    public async IAsyncEnumerable<CoreResponse> WatchStatusStreamAsync(
        int streamIntervalMs = 800,
        int streamMaxEvents = 0,
        bool streamHeartbeatEnabled = true,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var emitted = 0;
        var interval = Math.Max(200, streamIntervalMs);
        while (!cancellationToken.IsCancellationRequested)
        {
            yield return await GetStatusAsync(cancellationToken);
            emitted++;
            if (streamMaxEvents > 0 && emitted >= streamMaxEvents)
            {
                yield break;
            }
            await Task.Delay(interval, cancellationToken);
        }
    }

    public async IAsyncEnumerable<CoreResponse> WatchConnectionsStreamAsync(
        string search = "",
        string sortBy = "last_seen",
        bool descending = true,
        int streamIntervalMs = 900,
        int streamMaxEvents = 0,
        bool streamHeartbeatEnabled = true,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var emitted = 0;
        var interval = Math.Max(250, streamIntervalMs);
        while (!cancellationToken.IsCancellationRequested)
        {
            yield return await GetConnectionsAsync(search, sortBy, descending, cancellationToken);
            emitted++;
            if (streamMaxEvents > 0 && emitted >= streamMaxEvents)
            {
                yield break;
            }
            await Task.Delay(interval, cancellationToken);
        }
    }

    public async IAsyncEnumerable<CoreResponse> WatchGroupsStreamAsync(
        int streamIntervalMs = 900,
        int streamMaxEvents = 0,
        bool streamHeartbeatEnabled = true,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var emitted = 0;
        var interval = Math.Max(250, streamIntervalMs);
        while (!cancellationToken.IsCancellationRequested)
        {
            yield return await GetStatusAsync(cancellationToken);
            emitted++;
            if (streamMaxEvents > 0 && emitted >= streamMaxEvents)
            {
                yield break;
            }
            await Task.Delay(interval, cancellationToken);
        }
    }

    public Task<CoreResponse> SendAsync(string action, CancellationToken cancellationToken = default)
    {
        return SendAsync(new CoreRequest { Action = action }, cancellationToken);
    }

    public Task<CoreResponse> SendAsync(CoreRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var requestJson = JsonSerializer.Serialize(request, JsonOptions);
        IntPtr ptr;
        try
        {
            ptr = om_request(requestJson);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("Embedded core call failed. Ensure openmesh_core.dll is available.", ex);
        }

        if (ptr == IntPtr.Zero)
        {
            throw new InvalidOperationException("Embedded core returned null response pointer.");
        }

        try
        {
            var responseJson = Marshal.PtrToStringUTF8(ptr);
            if (string.IsNullOrWhiteSpace(responseJson))
            {
                throw new InvalidOperationException("Embedded core returned empty response.");
            }
            var response = JsonSerializer.Deserialize<CoreResponse>(responseJson, JsonOptions);
            if (response is null)
            {
                throw new InvalidOperationException("Embedded core response parse failed.");
            }
            return Task.FromResult(response);
        }
        finally
        {
            om_free_string(ptr);
        }
    }
}

