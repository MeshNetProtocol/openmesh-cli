using System.Text.Json;

namespace OpenMeshWin;

internal sealed class SelectedOutboundEntry
{
    public string GroupTag { get; set; } = string.Empty;
    public string OutboundTag { get; set; } = string.Empty;
}

internal sealed class SelectedOutboundStore
{
    private static readonly Lazy<SelectedOutboundStore> _lazy = new(() => new SelectedOutboundStore());
    public static SelectedOutboundStore Instance => _lazy.Value;

    private readonly object _lock = new();
    private readonly string _path;
    private Dictionary<string, SelectedOutboundEntry> _map = new(StringComparer.OrdinalIgnoreCase);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private SelectedOutboundStore()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenMeshWin");
        Directory.CreateDirectory(root);
        _path = Path.Combine(root, "selected_outbounds.json");
        Load();
    }

    public SelectedOutboundEntry? Get(long profileId)
    {
        if (profileId <= 0) return null;
        lock (_lock)
        {
            return _map.TryGetValue(profileId.ToString(), out var entry)
                ? new SelectedOutboundEntry { GroupTag = entry.GroupTag, OutboundTag = entry.OutboundTag }
                : null;
        }
    }

    public void Set(long profileId, string groupTag, string outboundTag)
    {
        if (profileId <= 0) return;
        groupTag = (groupTag ?? string.Empty).Trim();
        outboundTag = (outboundTag ?? string.Empty).Trim();
        if (groupTag.Length == 0 || outboundTag.Length == 0) return;

        lock (_lock)
        {
            _map[profileId.ToString()] = new SelectedOutboundEntry
            {
                GroupTag = groupTag,
                OutboundTag = outboundTag
            };
            Save();
        }
    }

    public void Remove(long profileId)
    {
        if (profileId <= 0) return;
        lock (_lock)
        {
            if (_map.Remove(profileId.ToString()))
            {
                Save();
            }
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
                    _map = new Dictionary<string, SelectedOutboundEntry>(StringComparer.OrdinalIgnoreCase);
                    return;
                }

                var json = File.ReadAllText(_path);
                _map = JsonSerializer.Deserialize<Dictionary<string, SelectedOutboundEntry>>(json, JsonOptions)
                       ?? new Dictionary<string, SelectedOutboundEntry>(StringComparer.OrdinalIgnoreCase);
            }
            catch
            {
                _map = new Dictionary<string, SelectedOutboundEntry>(StringComparer.OrdinalIgnoreCase);
            }
        }
    }

    private void Save()
    {
        try
        {
            var json = JsonSerializer.Serialize(_map, JsonOptions);
            File.WriteAllText(_path, json);
        }
        catch
        {
        }
    }
}
