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
    public void RegisterInstalledProvider(string providerId, string packageHash, List<string> pendingRuleSets, Dictionary<string, string> ruleSetUrls)
    {
        lock (_lock)
        {
            _state.InstalledPackageHashes[providerId] = packageHash;
            
            // Pending
            if (pendingRuleSets != null && pendingRuleSets.Count > 0)
            {
                _state.PendingRuleSets[providerId] = new List<string>(pendingRuleSets);
            }
            else
            {
                _state.PendingRuleSets.Remove(providerId);
            }
            
            // URLs
            if (ruleSetUrls != null && ruleSetUrls.Count > 0)
            {
                _state.RuleSetUrls[providerId] = new Dictionary<string, string>(ruleSetUrls);
            }
            // Do not remove if empty, as we might need them later or they might be persistent?
            // Actually macOS updates the whole map.
            else if (ruleSetUrls != null) 
            {
                _state.RuleSetUrls.Remove(providerId);
            }

            Save();
        }
    }
    
    public Dictionary<string, string> GetRuleSetUrls(string providerId)
    {
        lock (_lock)
        {
            return _state.RuleSetUrls.TryGetValue(providerId, out var map) ? new Dictionary<string, string>(map) : new Dictionary<string, string>();
        }
    }

    /// <summary>
    /// Maps a Profile ID to a Provider ID (like macOS installed_provider_id_by_profile).
    /// </summary>
    public void MapProfileToProvider(long profileId, string providerId)
    {
        lock (_lock)
        {
            _state.InstalledProviderIdByProfile[profileId.ToString()] = providerId;
            Save();
        }
    }

    /// <summary>
    /// Gets the Provider ID associated with a Profile ID.
    /// </summary>
    public string GetProviderIdForProfile(long profileId)
    {
        lock (_lock)
        {
            return _state.InstalledProviderIdByProfile.TryGetValue(profileId.ToString(), out var pid) ? pid : string.Empty;
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
            _state.RuleSetUrls.Remove(providerId);
            
            // Also remove any profile mappings for this provider
            var keysToRemove = _state.InstalledProviderIdByProfile
                .Where(kv => kv.Value == providerId)
                .Select(kv => kv.Key)
                .ToList();
            
            foreach (var k in keysToRemove)
            {
                _state.InstalledProviderIdByProfile.Remove(k);
            }

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

    // Maps ProviderID -> Dictionary<Tag, URL>
    // Stores the URLs of rule-sets for later retry
    public Dictionary<string, Dictionary<string, string>> RuleSetUrls { get; set; } = new();

    // Maps ProfileID (string) -> ProviderID
    // Used to look up which Provider a Profile belongs to.
    public Dictionary<string, string> InstalledProviderIdByProfile { get; set; } = new();
}

