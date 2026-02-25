namespace OpenMeshWin;

internal static class CoreClientFactory
{
    public static ICoreClient CreateDefault()
    {
        var backend = (Environment.GetEnvironmentVariable("OPENMESH_WIN_CORE_BACKEND") ?? string.Empty)
            .Trim()
            .ToLowerInvariant();

        if (backend is "" or "embedded" or "dll")
        {
            return new EmbeddedCoreClient();
        }

        if (backend is "pipe" or "core")
        {
            return new CoreClient();
        }

        return new CoreClient();
    }
}
