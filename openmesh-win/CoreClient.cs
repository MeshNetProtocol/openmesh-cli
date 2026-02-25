using System.IO.Pipes;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace OpenMeshWin;

internal sealed class CoreClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public Task<CoreResponse> PingAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("ping", cancellationToken);
    }

    public Task<CoreResponse> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("status", cancellationToken);
    }

    public Task<CoreResponse> StartVpnAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("start_vpn", cancellationToken);
    }

    public Task<CoreResponse> ReloadAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("reload", cancellationToken);
    }

    public Task<CoreResponse> SetProfileAsync(string profilePath, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "set_profile",
                ProfilePath = profilePath ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> UrlTestAsync(string group, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "urltest",
                Group = group ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> SelectOutboundAsync(string group, string outbound, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "select_outbound",
                Group = group ?? string.Empty,
                Outbound = outbound ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> GetConnectionsAsync(
        string search,
        string sortBy,
        bool descending,
        CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "connections",
                Search = search ?? string.Empty,
                SortBy = sortBy ?? string.Empty,
                Descending = descending
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> CloseConnectionAsync(int connectionId, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "close_connection",
                ConnectionId = connectionId
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> GenerateMnemonicAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("wallet_generate_mnemonic", cancellationToken);
    }

    public Task<CoreResponse> CreateWalletAsync(string mnemonic, string password, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "wallet_create",
                Mnemonic = mnemonic ?? string.Empty,
                Password = password ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> UnlockWalletAsync(string password, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "wallet_unlock",
                Password = password ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> GetWalletBalanceAsync(string network, string tokenSymbol, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "wallet_balance",
                Network = network ?? string.Empty,
                TokenSymbol = tokenSymbol ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> MakeX402PaymentAsync(
        string to,
        string resource,
        string amount,
        string password,
        CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "x402_pay",
                To = to ?? string.Empty,
                Resource = resource ?? string.Empty,
                Amount = amount ?? string.Empty,
                Password = password ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> GetProviderMarketAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("provider_market_list", cancellationToken);
    }

    public Task<CoreResponse> InstallProviderAsync(string providerId, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "provider_install",
                ProviderId = providerId ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> UninstallProviderAsync(string providerId, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "provider_uninstall",
                ProviderId = providerId ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> ActivateProviderAsync(string providerId, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "provider_activate",
                ProviderId = providerId ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> ImportProviderFromFileAsync(string importPath, CancellationToken cancellationToken = default)
    {
        return SendAsync(
            new CoreRequest
            {
                Action = "provider_import_file",
                ImportPath = importPath ?? string.Empty
            },
            cancellationToken
        );
    }

    public Task<CoreResponse> StopVpnAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("stop_vpn", cancellationToken);
    }

    public Task<CoreResponse> P3NetworkPreflightAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_network_preflight", cancellationToken);
    }

    public Task<CoreResponse> P3NetworkPrepareAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_network_prepare", cancellationToken);
    }

    public Task<CoreResponse> P3NetworkRollbackAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_network_rollback", cancellationToken);
    }

    public Task<CoreResponse> P3EngineProbeAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_engine_probe", cancellationToken);
    }

    public Task<CoreResponse> P3EngineStartAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_engine_start", cancellationToken);
    }

    public Task<CoreResponse> P3EngineStopAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_engine_stop", cancellationToken);
    }

    public Task<CoreResponse> P3EngineHealthAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("p3_engine_health", cancellationToken);
    }

    public async IAsyncEnumerable<CoreResponse> WatchStatusStreamAsync(
        int streamIntervalMs = 800,
        int streamMaxEvents = 0,
        bool streamHeartbeatEnabled = true,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        using var pipe = new NamedPipeClientStream(
            ".",
            CoreProtocol.PipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous
        );

        pipe.Connect(timeout: 1200);

        using var writer = new StreamWriter(pipe, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true)
        {
            AutoFlush = true
        };
        using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);

        var streamRequest = new CoreRequest
        {
            Action = "status_stream",
            StreamIntervalMs = streamIntervalMs,
            StreamMaxEvents = streamMaxEvents,
            StreamHeartbeatEnabled = streamHeartbeatEnabled
        };

        var requestJson = JsonSerializer.Serialize(streamRequest, JsonOptions);
        await writer.WriteLineAsync(requestJson);

        var timeoutMs = Math.Max(1500, streamIntervalMs <= 0 ? 2400 : streamIntervalMs * 3);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var readTask = reader.ReadLineAsync(cancellationToken).AsTask();
            var timeoutTask = Task.Delay(timeoutMs, cancellationToken);
            var finishedTask = await Task.WhenAny(readTask, timeoutTask);
            if (finishedTask == timeoutTask)
            {
                throw new TimeoutException("Core stream heartbeat timeout.");
            }

            var line = await readTask;
            if (line is null)
            {
                yield break;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var response = JsonSerializer.Deserialize<CoreResponse>(line, JsonOptions);
            if (response is null)
            {
                continue;
            }

            yield return response;
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
        using var pipe = new NamedPipeClientStream(
            ".",
            CoreProtocol.PipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous
        );

        pipe.Connect(timeout: 1200);

        using var writer = new StreamWriter(pipe, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true)
        {
            AutoFlush = true
        };
        using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);

        var streamRequest = new CoreRequest
        {
            Action = "connections_stream",
            Search = search ?? string.Empty,
            SortBy = sortBy ?? "last_seen",
            Descending = descending,
            StreamIntervalMs = streamIntervalMs,
            StreamMaxEvents = streamMaxEvents,
            StreamHeartbeatEnabled = streamHeartbeatEnabled
        };

        var requestJson = JsonSerializer.Serialize(streamRequest, JsonOptions);
        await writer.WriteLineAsync(requestJson);

        var timeoutMs = Math.Max(1500, streamIntervalMs <= 0 ? 2400 : streamIntervalMs * 3);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var readTask = reader.ReadLineAsync(cancellationToken).AsTask();
            var timeoutTask = Task.Delay(timeoutMs, cancellationToken);
            var finishedTask = await Task.WhenAny(readTask, timeoutTask);
            if (finishedTask == timeoutTask)
            {
                throw new TimeoutException("Core connections stream heartbeat timeout.");
            }

            var line = await readTask;
            if (line is null)
            {
                yield break;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var response = JsonSerializer.Deserialize<CoreResponse>(line, JsonOptions);
            if (response is null)
            {
                continue;
            }

            yield return response;
        }
    }

    public async IAsyncEnumerable<CoreResponse> WatchGroupsStreamAsync(
        int streamIntervalMs = 900,
        int streamMaxEvents = 0,
        bool streamHeartbeatEnabled = true,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        using var pipe = new NamedPipeClientStream(
            ".",
            CoreProtocol.PipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous
        );

        pipe.Connect(timeout: 1200);

        using var writer = new StreamWriter(pipe, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true)
        {
            AutoFlush = true
        };
        using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);

        var streamRequest = new CoreRequest
        {
            Action = "groups_stream",
            StreamIntervalMs = streamIntervalMs,
            StreamMaxEvents = streamMaxEvents,
            StreamHeartbeatEnabled = streamHeartbeatEnabled
        };

        var requestJson = JsonSerializer.Serialize(streamRequest, JsonOptions);
        await writer.WriteLineAsync(requestJson);

        var timeoutMs = Math.Max(1500, streamIntervalMs <= 0 ? 2400 : streamIntervalMs * 3);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var readTask = reader.ReadLineAsync(cancellationToken).AsTask();
            var timeoutTask = Task.Delay(timeoutMs, cancellationToken);
            var finishedTask = await Task.WhenAny(readTask, timeoutTask);
            if (finishedTask == timeoutTask)
            {
                throw new TimeoutException("Core groups stream heartbeat timeout.");
            }

            var line = await readTask;
            if (line is null)
            {
                yield break;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var response = JsonSerializer.Deserialize<CoreResponse>(line, JsonOptions);
            if (response is null)
            {
                continue;
            }

            yield return response;
        }
    }

    public async Task<CoreResponse> SendAsync(string action, CancellationToken cancellationToken = default)
    {
        return await SendAsync(new CoreRequest { Action = action }, cancellationToken);
    }

    public async Task<CoreResponse> SendAsync(CoreRequest request, CancellationToken cancellationToken = default)
    {
        using var pipe = new NamedPipeClientStream(
            ".",
            CoreProtocol.PipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous
        );

        pipe.Connect(timeout: 1200);

        using var writer = new StreamWriter(pipe, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true)
        {
            AutoFlush = true
        };
        using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);

        var requestJson = JsonSerializer.Serialize(request, JsonOptions);
        await writer.WriteLineAsync(requestJson);

        var readTask = reader.ReadLineAsync(cancellationToken).AsTask();
        var timeoutTask = Task.Delay(1200, cancellationToken);
        var finishedTask = await Task.WhenAny(readTask, timeoutTask);
        if (finishedTask == timeoutTask)
        {
            throw new TimeoutException("Core response timeout.");
        }

        var line = await readTask;
        if (string.IsNullOrWhiteSpace(line))
        {
            throw new InvalidOperationException("Core returned empty response.");
        }

        var response = JsonSerializer.Deserialize<CoreResponse>(line, JsonOptions);
        if (response is null)
        {
            throw new InvalidOperationException("Failed to parse core response.");
        }

        return response;
    }
}
