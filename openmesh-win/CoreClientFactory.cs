namespace OpenMeshWin;

internal static class CoreClientFactory
{
    public static ICoreClient CreateDefault()
    {
        return new EmbeddedCoreClient();
    }
}
