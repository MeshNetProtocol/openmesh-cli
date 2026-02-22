using System.IO.Pipes;
using System.Text;
using System.Text.Json;

namespace OpenMeshWin.Core;

internal static class Program
{
    private const string PipeName = "openmesh-win-core";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };
    private static readonly CoreState State = new();

    private static async Task Main()
    {
        Console.WriteLine("OpenMeshWin.Core is running.");

        while (true)
        {
            var server = new NamedPipeServerStream(
                PipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous
            );

            try
            {
                await server.WaitForConnectionAsync();
                _ = Task.Run(() => HandleClientAsync(server));
            }
            catch (Exception)
            {
                server.Dispose();
            }
        }
    }

    private static async Task HandleClientAsync(NamedPipeServerStream server)
    {
        using (server)
        using (var reader = new StreamReader(server, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true))
        using (var writer = new StreamWriter(server, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), leaveOpen: true) { AutoFlush = true })
        {
            var requestLine = await reader.ReadLineAsync();
            if (string.IsNullOrWhiteSpace(requestLine))
            {
                return;
            }

            CoreRequest? request = null;
            try
            {
                request = JsonSerializer.Deserialize<CoreRequest>(requestLine, JsonOptions);
            }
            catch (JsonException)
            {
                // Invalid JSON will be handled by the default response below.
            }

            var response = State.Handle(request);
            var responseJson = JsonSerializer.Serialize(response, JsonOptions);
            await writer.WriteLineAsync(responseJson);
        }
    }

    private sealed class CoreState
    {
        private readonly object _gate = new();
        private readonly DateTimeOffset _startedAtUtc = DateTimeOffset.UtcNow;
        private bool _vpnRunning;

        public CoreResponse Handle(CoreRequest? request)
        {
            lock (_gate)
            {
                var action = request?.Action?.Trim().ToLowerInvariant() ?? string.Empty;

                return action switch
                {
                    "ping" => BuildResponse(ok: true, message: "pong"),
                    "status" => BuildResponse(ok: true, message: "status"),
                    "start_vpn" => StartVpn(),
                    "stop_vpn" => StopVpn(),
                    _ => BuildResponse(ok: false, message: "unknown action")
                };
            }
        }

        private CoreResponse StartVpn()
        {
            _vpnRunning = true;
            return BuildResponse(ok: true, message: "vpn started");
        }

        private CoreResponse StopVpn()
        {
            _vpnRunning = false;
            return BuildResponse(ok: true, message: "vpn stopped");
        }

        private CoreResponse BuildResponse(bool ok, string message)
        {
            return new CoreResponse
            {
                Ok = ok,
                Message = message,
                CoreRunning = true,
                VpnRunning = _vpnRunning,
                StartedAtUtc = _startedAtUtc.ToString("O")
            };
        }
    }

    private sealed class CoreRequest
    {
        public string Action { get; set; } = string.Empty;
    }

    private sealed class CoreResponse
    {
        public bool Ok { get; set; }
        public string Message { get; set; } = string.Empty;
        public bool CoreRunning { get; set; }
        public bool VpnRunning { get; set; }
        public string StartedAtUtc { get; set; } = string.Empty;
    }
}
