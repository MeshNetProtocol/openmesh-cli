using System.Text;

namespace OpenMeshWin.Core;

internal static class CoreFileLogger
{
    private static readonly object Sync = new();
    private static string _logPath = string.Empty;
    private static bool _initialized;
    private const long MaxFileSizeBytes = 1_000_000;
    private const int MaxFiles = 5;

    public static void Initialize(string runtimeRoot)
    {
        lock (Sync)
        {
            var logRoot = Path.Combine(runtimeRoot, "logs");
            Directory.CreateDirectory(logRoot);
            _logPath = Path.Combine(logRoot, "core.log");
            _initialized = true;
            try
            {
                File.AppendAllText(_logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] Logger initialized.{Environment.NewLine}", Encoding.UTF8);
            }
            catch { }
        }
    }

    public static void Log(string message)
    {
        lock (Sync)
        {
            if (!_initialized || string.IsNullOrWhiteSpace(_logPath))
            {
                return;
            }

            try
            {
                // RotateIfNeeded(); // Simplified: Disable rotation for now to ensure simple append works
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}";
                File.AppendAllText(_logPath, line + Environment.NewLine, Encoding.UTF8);
            }
            catch
            {
                // Ignore logger failure.
            }
        }
    }

    private static void RotateIfNeeded()
    {
        if (!File.Exists(_logPath))
        {
            return;
        }

        var info = new FileInfo(_logPath);
        if (info.Length < MaxFileSizeBytes)
        {
            return;
        }

        for (var i = MaxFiles - 1; i >= 1; i--)
        {
            var src = $"{_logPath}.{i}";
            var dst = $"{_logPath}.{i + 1}";
            if (File.Exists(dst))
            {
                File.Delete(dst);
            }

            if (File.Exists(src))
            {
                File.Move(src, dst);
            }
        }

        var firstArchive = $"{_logPath}.1";
        if (File.Exists(firstArchive))
        {
            File.Delete(firstArchive);
        }

        File.Move(_logPath, firstArchive);
    }
}
