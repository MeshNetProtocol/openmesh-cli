using System.Text.Json.Serialization;

namespace OpenMeshWin;

public enum ProfileType
{
    Local = 0,
    Remote = 2,
    ICloud = 1 // Not used on Windows
}

public class Profile
{
    public long Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public uint Order { get; set; }
    public ProfileType Type { get; set; } = ProfileType.Local;
    public string Path { get; set; } = string.Empty;
    public string? RemoteURL { get; set; }
    public bool AutoUpdate { get; set; }
    public int AutoUpdateInterval { get; set; }
    public DateTime? LastUpdated { get; set; }
}
