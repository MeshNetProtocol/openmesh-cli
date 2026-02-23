namespace OpenMeshWin;

internal sealed class AppHeartbeatWriter
{
    private readonly object _sync = new();
    private readonly string _heartbeatPath;
    private DateTimeOffset _lastTouchUtc = DateTimeOffset.MinValue;

    public AppHeartbeatWriter()
    {
        _heartbeatPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "OpenMeshWin",
            "app_heartbeat");
    }

    public void Touch()
    {
        lock (_sync)
        {
            var now = DateTimeOffset.UtcNow;
            if ((now - _lastTouchUtc).TotalSeconds < 1.5)
            {
                return;
            }

            var dir = Path.GetDirectoryName(_heartbeatPath) ?? Environment.CurrentDirectory;
            Directory.CreateDirectory(dir);
            File.WriteAllText(_heartbeatPath, now.ToString("O"));
            _lastTouchUtc = now;
        }
    }

    public void Clear()
    {
        lock (_sync)
        {
            if (File.Exists(_heartbeatPath))
            {
                File.Delete(_heartbeatPath);
            }
        }
    }

    public string HeartbeatPath => _heartbeatPath;
}
