using System.Text.Json;

namespace OpenMeshWin;

/// <summary>
/// Manages profiles for the application, aligning with macOS App's ProfileManager/Database.
/// Stores profiles in profiles.json in the user's Local AppData folder.
/// </summary>
internal sealed class ProfileManager
{
    private static readonly Lazy<ProfileManager> _lazy = new(() => new ProfileManager());
    public static ProfileManager Instance => _lazy.Value;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _storagePath;
    private List<Profile> _profiles = new();
    private readonly object _lock = new();
    private long _nextId = 1;

    private ProfileManager()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenMeshWin");
        Directory.CreateDirectory(root);
        _storagePath = Path.Combine(root, "profiles.json");
        Load();
    }

    private void Load()
    {
        lock (_lock)
        {
            try
            {
                if (File.Exists(_storagePath))
                {
                    var json = File.ReadAllText(_storagePath);
                    _profiles = JsonSerializer.Deserialize<List<Profile>>(json, JsonOptions) ?? new List<Profile>();
                    
                    if (_profiles.Count > 0)
                    {
                        _nextId = _profiles.Max(p => p.Id) + 1;
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to load profiles: {ex.Message}");
                _profiles = new List<Profile>();
            }
        }
    }

    private void Save()
    {
        lock (_lock)
        {
            try
            {
                // Ensure unique IDs and Order
                var json = JsonSerializer.Serialize(_profiles, JsonOptions);
                File.WriteAllText(_storagePath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to save profiles: {ex.Message}");
            }
        }
    }

    public async Task<Profile> CreateAsync(Profile profile)
    {
        return await Task.Run(() =>
        {
            lock (_lock)
            {
                profile.Id = _nextId++;
                if (profile.Order == 0)
                {
                    profile.Order = (uint)_profiles.Count;
                }
                _profiles.Add(profile);
                Save();
                return profile;
            }
        });
    }

    public async Task<Profile?> GetAsync(long id)
    {
        return await Task.Run(() =>
        {
            lock (_lock)
            {
                return _profiles.FirstOrDefault(p => p.Id == id);
            }
        });
    }

    public async Task<List<Profile>> ListAsync()
    {
        return await Task.Run(() =>
        {
            lock (_lock)
            {
                return _profiles.OrderBy(p => p.Order).ToList();
            }
        });
    }

    public async Task UpdateAsync(Profile profile)
    {
        await Task.Run(() =>
        {
            lock (_lock)
            {
                var index = _profiles.FindIndex(p => p.Id == profile.Id);
                if (index >= 0)
                {
                    _profiles[index] = profile;
                    Save();
                }
            }
        });
    }

    public async Task DeleteAsync(long id)
    {
        await Task.Run(() =>
        {
            lock (_lock)
            {
                var profile = _profiles.FirstOrDefault(p => p.Id == id);
                if (profile != null)
                {
                    _profiles.Remove(profile);
                    Save();
                    
                    // Cleanup file if it exists and is local?
                    // macOS logic deletes DB record. File deletion handled separately usually.
                    // But here we might want to clean up if needed.
                }
            }
        });
    }
}
