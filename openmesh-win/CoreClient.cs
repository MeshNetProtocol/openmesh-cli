using System.IO.Pipes;
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

    public Task<CoreResponse> StopVpnAsync(CancellationToken cancellationToken = default)
    {
        return SendAsync("stop_vpn", cancellationToken);
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
