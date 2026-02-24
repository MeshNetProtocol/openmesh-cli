using System.Text;

namespace OpenMeshWin.Service;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        var runOnce = args.Any(a => string.Equals(a, "--run-once", StringComparison.OrdinalIgnoreCase));
        var printStatus = args.Any(a => string.Equals(a, "--status", StringComparison.OrdinalIgnoreCase));

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
            Console.WriteLine("{\"ok\":true,\"service\":\"openmesh-win-service\",\"mode\":\"skeleton\"}");
            return 0;
        }

        if (runOnce)
        {
            WriteHeartbeat(heartbeatPath);
            ServiceFileLogger.Log("run-once heartbeat completed.");
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
