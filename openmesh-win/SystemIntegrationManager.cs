using Microsoft.Win32;
using System.Diagnostics;

namespace OpenMeshWin;

internal sealed class SystemIntegrationManager
{
    private const string StartupRunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private static readonly string StartupValueName = MeshFluxPaths.ProductDisplayName;

    public IntegrationSnapshot GetSnapshot()
    {
        var startupEnabled = IsStartupEnabled();
        var wintunPath = FindWintunBinaryPath();
        var wintunServicePresent = IsWintunServicePresent();

        return new IntegrationSnapshot
        {
            StartupEnabled = startupEnabled,
            WintunBinaryFound = !string.IsNullOrWhiteSpace(wintunPath),
            WintunBinaryPath = wintunPath,
            WintunServicePresent = wintunServicePresent
        };
    }

    public bool IsStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRunKeyPath, writable: false);
        var value = key?.GetValue(StartupValueName) as string;
        return !string.IsNullOrWhiteSpace(value);
    }

    public void SetStartupEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(StartupRunKeyPath, writable: true);
        if (key is null)
        {
            throw new InvalidOperationException("Failed to open startup registry key.");
        }

        if (!enabled)
        {
            key.DeleteValue(StartupValueName, throwOnMissingValue: false);
            return;
        }

        var exePath = Application.ExecutablePath;
        key.SetValue(StartupValueName, $"\"{exePath}\"");
    }

    public string? FindWintunBinaryPath()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "wintun.dll"),
            Path.Combine(AppContext.BaseDirectory, "deps", "wintun", "wintun.dll"),
            Path.Combine(Environment.SystemDirectory, "wintun.dll")
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static bool IsWintunServicePresent()
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "sc.exe",
                Arguments = "query Wintun",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(1500);
            return process.ExitCode == 0 &&
                   output.Contains("SERVICE_NAME: Wintun", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }
}

internal sealed class IntegrationSnapshot
{
    public bool StartupEnabled { get; set; }
    public bool WintunBinaryFound { get; set; }
    public string? WintunBinaryPath { get; set; }
    public bool WintunServicePresent { get; set; }
}
