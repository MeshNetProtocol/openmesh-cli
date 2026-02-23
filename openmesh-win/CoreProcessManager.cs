using System.Diagnostics;

namespace OpenMeshWin;

internal sealed class CoreProcessManager
{
    private const string LegacyMockCoreDisplayName = "OpenMeshWin.Core (legacy/mock)";
    private const string GoCoreDisplayName = "openmesh-win-core (go)";
    private Process? _coreProcess;
    private string _lastStartedMode = AppSettings.CoreModeMock;

    public async Task<CoreStartResult> EnsureStartedAsync(
        CoreClient client,
        AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        var mode = settings.GetNormalizedCoreMode();
        try
        {
            var ping = await client.PingAsync(cancellationToken);
            if (ping.Ok)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = true,
                    Message = $"Core is already running. requested_mode={mode}"
                };
            }
        }
        catch
        {
            // Core not reachable yet. Continue with local process start.
        }

        if (string.Equals(mode, AppSettings.CoreModeGo, StringComparison.OrdinalIgnoreCase))
        {
            return await EnsureGoCoreStartedAsync(client, cancellationToken);
        }

        return await EnsureLegacyMockCoreStartedAsync(client, cancellationToken);
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
            return $"Local core process stopped. mode={_lastStartedMode}";
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

    private async Task<CoreStartResult> EnsureLegacyMockCoreStartedAsync(CoreClient client, CancellationToken cancellationToken)
    {
        var coreDllPath = FindLegacyMockCoreDllPath();
        if (coreDllPath is null)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = $"Cannot find {LegacyMockCoreDisplayName} dll. Build the legacy/mock core project first."
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

        return await StartProcessAndWaitForPingAsync(
            client,
            startInfo,
            LegacyMockCoreDisplayName,
            AppSettings.CoreModeMock,
            cancellationToken);
    }

    private async Task<CoreStartResult> EnsureGoCoreStartedAsync(CoreClient client, CancellationToken cancellationToken)
    {
        var coreExePath = FindGoCoreExePath();
        if (coreExePath is null)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message =
                    "Cannot find openmesh-win-core.exe for CoreMode=go. " +
                    "Set OPENMESH_WIN_GO_CORE_EXE or build with: " +
                    "powershell -ExecutionPolicy Bypass -File .\\openmesh-win\\tests\\Build-P1-GoCore.ps1"
            };
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = coreExePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(coreExePath) ?? Environment.CurrentDirectory
        };

        return await StartProcessAndWaitForPingAsync(
            client,
            startInfo,
            GoCoreDisplayName,
            AppSettings.CoreModeGo,
            cancellationToken);
    }

    private async Task<CoreStartResult> StartProcessAndWaitForPingAsync(
        CoreClient client,
        ProcessStartInfo startInfo,
        string coreDisplayName,
        string mode,
        CancellationToken cancellationToken)
    {
        try
        {
            _coreProcess = Process.Start(startInfo);
            if (_coreProcess is null)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = false,
                    Message = $"Failed to launch {coreDisplayName} process."
                };
            }
        }
        catch (Exception ex)
        {
            return new CoreStartResult
            {
                Started = false,
                AlreadyRunning = false,
                Message = $"Failed to launch {coreDisplayName}: {ex.Message}"
            };
        }

        _lastStartedMode = mode;

        var startDeadline = DateTime.UtcNow.AddSeconds(8);
        while (DateTime.UtcNow < startDeadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(250, cancellationToken);

            if (_coreProcess.HasExited)
            {
                return new CoreStartResult
                {
                    Started = false,
                    AlreadyRunning = false,
                    Message = $"{coreDisplayName} exited early with code {_coreProcess.ExitCode}."
                };
            }

            try
            {
                var ping = await client.PingAsync(cancellationToken);
                if (ping.Ok)
                {
                    return new CoreStartResult
                    {
                        Started = true,
                        AlreadyRunning = false,
                        Message = $"{coreDisplayName} started successfully. mode={mode}"
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
            Message = $"{coreDisplayName} process started but did not respond within timeout. mode={mode}"
        };
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

    private static string? FindLegacyMockCoreDllPath()
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

    private static string? FindGoCoreExePath()
    {
        var envPath = Environment.GetEnvironmentVariable("OPENMESH_WIN_GO_CORE_EXE");
        if (!string.IsNullOrWhiteSpace(envPath) && File.Exists(envPath))
        {
            return envPath;
        }

        var baseDir = AppContext.BaseDirectory;
        var candidates = new List<string>
        {
            Path.Combine(baseDir, "openmesh-win-core.exe"),
            Path.Combine(Environment.CurrentDirectory, "go-cli-lib", "cmd", "openmesh-win-core", "openmesh-win-core.exe"),
            Path.Combine(Environment.CurrentDirectory, "..", "go-cli-lib", "cmd", "openmesh-win-core", "openmesh-win-core.exe"),
            Path.Combine(Environment.CurrentDirectory, "go-cli-lib", "bin", "openmesh-win-core.exe"),
            Path.Combine(Environment.CurrentDirectory, "..", "go-cli-lib", "bin", "openmesh-win-core.exe")
        };

        var baseDirCursor = new DirectoryInfo(baseDir);
        for (var i = 0; i < 8 && baseDirCursor is not null; i++)
        {
            candidates.Add(Path.Combine(baseDirCursor.FullName, "go-cli-lib", "cmd", "openmesh-win-core", "openmesh-win-core.exe"));
            candidates.Add(Path.Combine(baseDirCursor.FullName, "go-cli-lib", "bin", "openmesh-win-core.exe"));
            candidates.Add(Path.Combine(baseDirCursor.FullName, "openmesh-win-core.exe"));
            baseDirCursor = baseDirCursor.Parent;
        }

        return candidates.FirstOrDefault(File.Exists);
    }
}
