namespace OpenMeshWin;

internal sealed class CoreProcessManager
{
    private string _lastStartedMode = AppSettings.CoreModeEmbedded;

    public async Task<CoreStartResult> EnsureStartedAsync(
        ICoreClient client,
        AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        _lastStartedMode = settings.GetNormalizedCoreMode();

        if (!string.Equals(client.BackendName, AppSettings.CoreModeEmbedded, StringComparison.OrdinalIgnoreCase))
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = $"Unsupported core backend '{client.BackendName}'. Embedded mode is required."
            };
        }

        try
        {
            var ping = await client.PingAsync(cancellationToken).ConfigureAwait(false);
            if (ping.Ok)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = true,
                    Message = "Embedded core backend is active."
                };
            }
        }
        catch
        {
            // Embedded backend does not support local process bootstrap.
        }

        return new CoreStartResult
        {
            Started = false,
            AlreadyRunning = false,
            Message = "Embedded core backend is unavailable."
        };
    }

    public async Task<string> TryStopLocalCoreAsync(ICoreClient client, CancellationToken cancellationToken = default)
    {
        try
        {
            await client.StopVpnAsync(cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            // Ignore: VPN may already be offline.
        }

        return $"No local external core process to stop. mode={_lastStartedMode}";
    }

    public string TryStopLocalCoreOnExitBestEffort()
    {
        return $"No local external core process to stop during exit. mode={_lastStartedMode}";
    }
}
