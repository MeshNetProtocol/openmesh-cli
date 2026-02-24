using System.Text;
using System.ServiceProcess;

namespace OpenMeshWin.Service;

internal static class Program
{
    private const string DefaultServiceName = "OpenMeshWinService";

    private static async Task<int> Main(string[] args)
    {
        var runOnce = args.Any(a => string.Equals(a, "--run-once", StringComparison.OrdinalIgnoreCase));
        var printStatus = args.Any(a => string.Equals(a, "--status", StringComparison.OrdinalIgnoreCase));
        var runAsService = args.Any(a => string.Equals(a, "--service", StringComparison.OrdinalIgnoreCase));
        var serviceName = ReadArgValue(args, "--service-name");
        if (string.IsNullOrWhiteSpace(serviceName))
        {
            serviceName = DefaultServiceName;
        }

        var runtimeRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenMeshWin");
        var serviceRoot = Path.Combine(runtimeRoot, "service");
        var heartbeatPath = Path.Combine(serviceRoot, "service_heartbeat");

        Directory.CreateDirectory(serviceRoot);
        ServiceFileLogger.Initialize(runtimeRoot);
        ServiceFileLogger.Log("openmesh-win-service started.");

        if (printStatus)
        {
            Console.WriteLine("{\"ok\":true,\"service\":\"openmesh-win-service\",\"mode\":\"skeleton\",\"serviceName\":\"" + serviceName + "\"}");
            return 0;
        }

        if (runOnce)
        {
            WriteHeartbeat(heartbeatPath);
            ServiceFileLogger.Log("run-once heartbeat completed.");
            return 0;
        }

        if (runAsService)
        {
            if (!OperatingSystem.IsWindows())
            {
                ServiceFileLogger.Log("Service mode requested on non-Windows OS.");
                return 1;
            }

            ServiceBase.Run([new OpenMeshWindowsService(serviceName, heartbeatPath)]);
            return 0;
        }

        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cts.Cancel();
        };

        try
        {
            while (!cts.Token.IsCancellationRequested)
            {
                WriteHeartbeat(heartbeatPath);
                await Task.Delay(TimeSpan.FromSeconds(3), cts.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown path.
        }
        finally
        {
            ServiceFileLogger.Log("openmesh-win-service stopped.");
        }

        return 0;
    }

    private static void WriteHeartbeat(string heartbeatPath)
    {
        var payload = DateTimeOffset.UtcNow.ToString("O");
        File.WriteAllText(heartbeatPath, payload, new UTF8Encoding(false));
    }

    private static string ReadArgValue(string[] args, string key)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if (!string.Equals(args[i], key, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (i + 1 < args.Length)
            {
                return args[i + 1];
            }
            break;
        }

        return string.Empty;
    }
}

internal sealed class OpenMeshWindowsService : ServiceBase
{
    private readonly string _heartbeatPath;
    private CancellationTokenSource? _cts;
    private Task? _worker;

    public OpenMeshWindowsService(string serviceName, string heartbeatPath)
    {
        ServiceName = serviceName;
        _heartbeatPath = heartbeatPath;
        AutoLog = false;
        CanPauseAndContinue = false;
    }

    protected override void OnStart(string[] args)
    {
        _cts = new CancellationTokenSource();
        _worker = Task.Run(() => RunLoopAsync(_cts.Token));
        ServiceFileLogger.Log("Windows service OnStart.");
    }

    protected override void OnStop()
    {
        ServiceFileLogger.Log("Windows service OnStop.");
        if (_cts is null)
        {
            return;
        }

        _cts.Cancel();
        try
        {
            _worker?.Wait(TimeSpan.FromSeconds(5));
        }
        catch
        {
        }
        finally
        {
            _cts.Dispose();
            _cts = null;
        }
    }

    private async Task RunLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            var payload = DateTimeOffset.UtcNow.ToString("O");
            File.WriteAllText(_heartbeatPath, payload, new UTF8Encoding(false));
            await Task.Delay(TimeSpan.FromSeconds(3), token);
        }
    }
}

internal static class ServiceFileLogger
{
    private static readonly object Gate = new();
    private static string _logPath = string.Empty;

    public static void Initialize(string runtimeRoot)
    {
        var logsRoot = Path.Combine(runtimeRoot, "logs");
        Directory.CreateDirectory(logsRoot);
        _logPath = Path.Combine(logsRoot, "openmesh-win-service.log");
    }

    public static void Log(string message)
    {
        lock (Gate)
        {
            if (string.IsNullOrWhiteSpace(_logPath))
            {
                return;
            }

            var line = $"[{DateTimeOffset.UtcNow:O}] {message}{Environment.NewLine}";
            File.AppendAllText(_logPath, line, new UTF8Encoding(false));
        }
    }
}
