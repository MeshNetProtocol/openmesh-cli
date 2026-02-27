using System.Text.Json;

namespace OpenMeshWin;

internal sealed class AppSettingsManager
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private readonly string _settingsPath;

    public AppSettingsManager()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "OpenMeshWin");
        _settingsPath = Path.Combine(root, "appsettings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return AppSettings.Default;
            }

            var json = File.ReadAllText(_settingsPath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json) ?? AppSettings.Default;
            if (string.Equals(settings.CoreMode, AppSettings.CoreModeMock, StringComparison.OrdinalIgnoreCase))
            {
                settings.CoreMode = AppSettings.CoreModeGo;
            }
            return settings;
        }
        catch
        {
            return AppSettings.Default;
        }
    }

    public void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(_settingsPath) ?? Environment.CurrentDirectory;
        Directory.CreateDirectory(directory);

        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(_settingsPath, json);
    }
}
