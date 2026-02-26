using System.Text.Json;

namespace OpenMeshWin;

/// <summary>
/// Manages the local state of installed providers, aligning with Mac App's SharedPreferences.
/// Persists data to installed_providers.json in the user's AppData folder.
/// </summary>
internal sealed class InstalledProviderManager
{
    private static readonly Lazy<InstalledProviderManager> _lazy = new(() => new InstalledProviderManager());
    public static InstalledProviderManager Instance => _lazy.Value;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _storagePath;
    private InstalledProviderState _state = new();
    private readonly object _lock = new();

    private InstalledProviderManager()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenMeshWin");
        Directory.CreateDirectory(root);
        _storagePath = Path.Combine(root, "installed_providers.json");
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
                    _state = JsonSerializer.Deserialize<InstalledProviderState>(json, JsonOptions) ?? new InstalledProviderState();
                }
            }
            catch (Exception ex)
            {
                // Log error but fallback to empty state
                System.Diagnostics.Debug.WriteLine($"Failed to load installed providers: {ex.Message}");
                _state = new InstalledProviderState();
            }
        }
    }

    private void Save()
    {
        lock (_lock)
        {
            try
            {
                var json = JsonSerializer.Serialize(_state, JsonOptions);
                File.WriteAllText(_storagePath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to save installed providers: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Checks if a provider is installed by verifying if we have a local package hash for it.
    /// </summary>
    public bool IsInstalled(string providerId)
    {
        lock (_lock)
        {
            return _state.InstalledPackageHashes.ContainsKey(providerId) &&
                   !string.IsNullOrEmpty(_state.InstalledPackageHashes[providerId]);
        }
    }

    /// <summary>
    /// Gets the locally installed package hash for a provider.
    /// Returns empty string if not installed.
    /// </summary>
    public string GetLocalPackageHash(string providerId)
    {
        lock (_lock)
        {
            return _state.InstalledPackageHashes.TryGetValue(providerId, out var hash) ? hash : string.Empty;
        }
    }

    /// <summary>
    /// Gets the list of pending rule-set tags that need initialization.
    /// </summary>
    public List<string> GetPendingRuleSets(string providerId)
    {
        lock (_lock)
        {
            return _state.PendingRuleSets.TryGetValue(providerId, out var tags) ? new List<string>(tags) : new List<string>();
        }
    }

    /// <summary>
    /// Updates the state after a successful installation.
    /// </summary>
    public void RegisterInstalledProvider(string providerId, string packageHash, List<string> pendingRuleSets)
    {
        lock (_lock)
        {
            _state.InstalledPackageHashes[providerId] = packageHash;
            if (pendingRuleSets != null && pendingRuleSets.Count > 0)
            {
                _state.PendingRuleSets[providerId] = new List<string>(pendingRuleSets);
            }
            else
            {
                _state.PendingRuleSets.Remove(providerId);
            }
            Save();
        }
    }

    /// <summary>
    /// Removes a provider's local state (e.g. after uninstall).
    /// </summary>
    public void RemoveProvider(string providerId)
    {
        lock (_lock)
        {
            _state.InstalledPackageHashes.Remove(providerId);
            _state.PendingRuleSets.Remove(providerId);
            Save();
        }
    }

    /// <summary>
    /// Gets all installed provider IDs.
    /// </summary>
    public IEnumerable<string> GetAllInstalledProviderIds()
    {
        lock (_lock)
        {
            return _state.InstalledPackageHashes.Keys.ToList();
        }
    }
}

internal class InstalledProviderState
{
    // Maps ProviderID -> PackageHash
    public Dictionary<string, string> InstalledPackageHashes { get; set; } = new();

    // Maps ProviderID -> List of pending rule-set tags
    public Dictionary<string, List<string>> PendingRuleSets { get; set; } = new();
}
