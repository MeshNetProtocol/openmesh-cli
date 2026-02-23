using System.Diagnostics;

namespace OpenMeshWin;

internal sealed class CoreProcessManager
{
    private Process? _coreProcess;

    public async Task<CoreStartResult> EnsureStartedAsync(CoreClient client, CancellationToken cancellationToken = default)
    {
        try
        {
            var ping = await client.PingAsync(cancellationToken);
            if (ping.Ok)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = true,
                    Message = "Core is already running."
                };
            }
        }
        catch
        {
            // Core not reachable yet. Continue with local process start.
        }

        var coreDllPath = FindCoreDllPath();
        if (coreDllPath is null)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = "Cannot find OpenMeshWin.Core.dll. Build the OpenMeshWin.Core project first."
            };
        }

        var dotnetPath = FindDotnetPath();
        if (dotnetPath is null)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = "Cannot find dotnet runtime executable."
            };
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = dotnetPath,
            Arguments = $"\"{coreDllPath}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(coreDllPath) ?? Environment.CurrentDirectory
        };

        try
        {
            _coreProcess = Process.Start(startInfo);
            if (_coreProcess is null)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = false,
                    Message = "Failed to launch OpenMeshWin.Core process."
                };
            }
        }
        catch (Exception ex)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = $"Failed to launch core process: {ex.Message}"
            };
        }

        var startDeadline = DateTime.UtcNow.AddSeconds(8);
        while (DateTime.UtcNow < startDeadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(250, cancellationToken);

            try
            {
                var ping = await client.PingAsync(cancellationToken);
                if (ping.Ok)
                {
                    return new CoreStartResult
                    {
                        Started = true,
                        AlreadyRunning = false,
                        Message = "Core started successfully."
                    };
                }
            }
            catch
            {
                // Keep waiting.
            }
        }

        return new CoreStartResult
        {
            Started = false,
            AlreadyRunning = false,
            Message = "Core process started but did not respond within timeout."
        };
    }

    public async Task<string> TryStopLocalCoreAsync(CoreClient client, CancellationToken cancellationToken = default)
    {
        try
        {
            await client.StopVpnAsync(cancellationToken);
        }
        catch
        {
            // Ignore: core might already be offline.
        }

        if (_coreProcess is null || _coreProcess.HasExited)
        {
            return "No local core process to stop.";
        }

        try
        {
            _coreProcess.Kill(entireProcessTree: true);
            await _coreProcess.WaitForExitAsync(cancellationToken);
            return "Local core process stopped.";
        }
        catch (Exception ex)
        {
            return $"Failed to stop local core process: {ex.Message}";
        }
        finally
        {
            _coreProcess.Dispose();
            _coreProcess = null;
        }
    }

    private static string? FindDotnetPath()
    {
        var dotnetRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        if (!string.IsNullOrWhiteSpace(dotnetRoot))
        {
            var dotnetFromRoot = Path.Combine(dotnetRoot, "dotnet.exe");
            if (File.Exists(dotnetFromRoot))
            {
                return dotnetFromRoot;
            }
        }

        var candidates = new[]
        {
            @"C:\Program Files\dotnet\dotnet.exe",
            @"C:\Program Files (x86)\dotnet\dotnet.exe"
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? FindCoreDllPath()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new List<string>
        {
            Path.Combine(baseDir, "OpenMeshWin.Core.dll"),
            Path.Combine(Environment.CurrentDirectory, "core", "OpenMeshWin.Core", "bin", "Debug", "net10.0", "OpenMeshWin.Core.dll"),
            Path.Combine(Environment.CurrentDirectory, "core", "OpenMeshWin.Core", "bin", "Release", "net10.0", "OpenMeshWin.Core.dll")
        };

        var dir = new DirectoryInfo(baseDir);
        for (var i = 0; i < 8 && dir is not null; i++)
        {
            candidates.Add(Path.Combine(dir.FullName, "core", "OpenMeshWin.Core", "bin", "Debug", "net10.0", "OpenMeshWin.Core.dll"));
            candidates.Add(Path.Combine(dir.FullName, "core", "OpenMeshWin.Core", "bin", "Release", "net10.0", "OpenMeshWin.Core.dll"));
            dir = dir.Parent;
        }

        return candidates.FirstOrDefault(File.Exists);
    }
}
