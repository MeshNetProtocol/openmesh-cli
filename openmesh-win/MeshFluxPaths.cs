using System.IO;

namespace OpenMeshWin;

internal static class MeshFluxPaths
{
#if DEBUG
    public const string AppDataRootName = "OpenMeshWin";
    public const string ProductDisplayName = "OpenMeshWin";
    public const string SingleInstanceMutexName = @"Local\OpenMeshWin.SingleInstance";
#else
    public const string AppDataRootName = "MeshFlux";
    public const string ProductDisplayName = "MeshFlux";
    public const string SingleInstanceMutexName = @"Local\MeshFlux.SingleInstance";
#endif

    public static string LocalAppDataRoot =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppDataRootName);

    public static string RoamingAppDataRoot =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppDataRootName);
}

