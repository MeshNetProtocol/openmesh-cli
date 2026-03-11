using System.Text.Json;

namespace OpenMeshWin;

internal sealed class SelectedProfileStore
{
    private static readonly Lazy<SelectedProfileStore> _lazy = new(() => new SelectedProfileStore());
    public static SelectedProfileStore Instance => _lazy.Value;

    private readonly object _lock = new();
    private readonly string _path;
    private string _selectedRef = string.Empty;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private sealed class Payload
    {
        public string SelectedRef { get; set; } = string.Empty;
    }

    private SelectedProfileStore()
    {
        var root = MeshFluxPaths.LocalAppDataRoot;
        Directory.CreateDirectory(root);
        _path = Path.Combine(root, "selected_profile.json");
        Load();
    }

    public string Get()
    {
        lock (_lock)
        {
            return _selectedRef;
        }
    }

    public void Set(string selectedRef)
    {
        selectedRef = (selectedRef ?? string.Empty).Trim();
        lock (_lock)
        {
            _selectedRef = selectedRef;
            Save();
        }
    }

    private void Load()
    {
        lock (_lock)
        {
            try
            {
                if (!File.Exists(_path))
                {
                    _selectedRef = string.Empty;
                    return;
                }

                var json = File.ReadAllText(_path);
                var payload = JsonSerializer.Deserialize<Payload>(json, JsonOptions);
                _selectedRef = payload?.SelectedRef?.Trim() ?? string.Empty;
            }
            catch
            {
                _selectedRef = string.Empty;
            }
        }
    }

    private void Save()
    {
        try
        {
            var payload = new Payload { SelectedRef = _selectedRef };
            var json = JsonSerializer.Serialize(payload, JsonOptions);
            File.WriteAllText(_path, json);
        }
        catch
        {
        }
    }
}
