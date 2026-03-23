using System.Text;

namespace OpenMeshWin;

internal static class AppLogger
{
    private static readonly object Sync = new();
    private static readonly string LogRoot = Path.Combine(
        MeshFluxPaths.LocalAppDataRoot,
        "logs");
    private static readonly string LogPath = Path.Combine(LogRoot, "app.log");
    private const long MaxFileSizeBytes = 1_000_000;
    private const int MaxFiles = 5;

    public static void Log(string message)
    {
        lock (Sync)
        {
            try
            {
                Directory.CreateDirectory(LogRoot);
                RotateIfNeeded();
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}";
                File.AppendAllText(LogPath, line + Environment.NewLine, Encoding.UTF8);
            }
            catch
            {
                // Do not throw from logger.
            }
        }
    }

    public static string GetLogDirectory() => LogRoot;

    private static void RotateIfNeeded()
    {
        if (!File.Exists(LogPath))
        {
            return;
        }

        var info = new FileInfo(LogPath);
        if (info.Length < MaxFileSizeBytes)
        {
            return;
        }

        for (var i = MaxFiles - 1; i >= 1; i--)
        {
            var src = $"{LogPath}.{i}";
            var dst = $"{LogPath}.{i + 1}";
            if (File.Exists(dst))
            {
                File.Delete(dst);
            }

            if (File.Exists(src))
            {
                File.Move(src, dst);
            }
        }

        var firstArchive = $"{LogPath}.1";
        if (File.Exists(firstArchive))
        {
            File.Delete(firstArchive);
        }

        File.Move(LogPath, firstArchive);
    }
}
