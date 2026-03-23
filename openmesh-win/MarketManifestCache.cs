using System.Net.Http.Headers;
using System.Text.Json;

namespace OpenMeshWin;

internal sealed class MarketManifestSnapshot
{
    public string UpdatedAt { get; set; } = string.Empty;
    public string ETag { get; set; } = string.Empty;
}

internal sealed class MarketManifestCache
{
    private static readonly Lazy<MarketManifestCache> _lazy = new(() => new MarketManifestCache());
    public static MarketManifestCache Instance => _lazy.Value;

    private readonly object _lock = new();
    private readonly string _path;
    private MarketManifestSnapshot _snapshot = new();

    private MarketManifestCache()
    {
        var root = MeshFluxPaths.LocalAppDataRoot;
        Directory.CreateDirectory(root);
        _path = Path.Combine(root, "market_manifest.json");
        Load();
    }

    public MarketManifestSnapshot GetSnapshot()
    {
        lock (_lock)
        {
            return new MarketManifestSnapshot { UpdatedAt = _snapshot.UpdatedAt, ETag = _snapshot.ETag };
        }
    }

    public async Task<MarketManifestSnapshot> RefreshAsync(HttpClient http, string baseUrl)
    {
        MarketManifestSnapshot current;
        lock (_lock)
        {
            current = new MarketManifestSnapshot { UpdatedAt = _snapshot.UpdatedAt, ETag = _snapshot.ETag };
        }

        using var req = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/api/v1/market/manifest");
        if (!string.IsNullOrWhiteSpace(current.ETag))
        {
            req.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(current.ETag));
        }

        using var resp = await http.SendAsync(req).ConfigureAwait(false);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotModified)
        {
            return current;
        }

        resp.EnsureSuccessStatusCode();
        var etag = resp.Headers.ETag?.ToString() ?? string.Empty;
        var body = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);

        string updatedAt = string.Empty;
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("data", out var data) &&
                data.TryGetProperty("updated_at", out var ua) &&
                ua.ValueKind == JsonValueKind.String)
            {
                updatedAt = ua.GetString() ?? string.Empty;
            }
        }
        catch
        {
        }

        lock (_lock)
        {
            _snapshot.ETag = etag;
            _snapshot.UpdatedAt = updatedAt;
            Save();
            return new MarketManifestSnapshot { UpdatedAt = _snapshot.UpdatedAt, ETag = _snapshot.ETag };
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
                    _snapshot = new MarketManifestSnapshot();
                    return;
                }

                var json = File.ReadAllText(_path);
                _snapshot = JsonSerializer.Deserialize<MarketManifestSnapshot>(json) ?? new MarketManifestSnapshot();
            }
            catch
            {
                _snapshot = new MarketManifestSnapshot();
            }
        }
    }

    private void Save()
    {
        try
        {
            var json = JsonSerializer.Serialize(_snapshot, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_path, json);
        }
        catch
        {
        }
    }
}
