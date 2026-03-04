# OpenMeshWin Professional Installer (MSI)

This directory contains scripts and WiX templates to generate a professional MSI installer for OpenMeshWin, with deterministic dependency collection.

## Prerequisites
- **.NET SDK 8.0+**
- **WiX Toolset (recommended v6)**: Install via `dotnet tool install --global wix`.
- **Go 1.25+**: For building the core DLL.

## How to Generate the Installer

Recommended command:
1.  Open PowerShell.
2.  Navigate to the `installer/` directory:
    ```powershell
    cd openmesh-win/installer
    ```
3.  Run the unified build script:
    ```powershell
    ./Build-P6-Wix-Msi.ps1 -Configuration Release -Version 1.0.0 -RequireWintun
    ```
    By default, the package payload is validated after build. Use `-SkipVerifyPackage` to disable it.
    Use `-CleanOutput` to clear historical files in `installer/output` before generating new artifacts.

Optional compatibility entrypoint:
```powershell
./Create-Full-Installer.ps1 -Configuration Release -Version 1.0.0
```

## What the unified pipeline does:
- **Build Package**: Publishes app/core/service outputs and gathers required native/runtime files into a single package zip.
- **Native Dependencies**: Collects `openmesh_core.dll`, `libwinpthread-1.dll`, and `wintun.dll` (when available/required).
- **.NET Runtime**: Uses self-contained publish by default (`-r win-x64 --self-contained`) so target machines do not need preinstalled .NET runtime.
- **Build MSI**: Uses WiX to install all staged files (`app/`, `core/`, `service/`) directly into `INSTALLFOLDER`, with install directory UI and app shortcuts.
- **Validation**: `installer/Verify-Package-Contents.ps1` checks required files in the generated zip and returns non-zero on failures (CI-friendly).

## Why use this Installer?
- **Deterministic Artifacts**: One pipeline for zip + MSI, fewer mismatched outputs.
- **Dependency-Complete Payload**: Package includes native and runtime dependencies.
- **Professional Presence**: Standard Windows "Add/Remove Programs" support.

---
**Note**: The generated `.msi` output will be in the `installer/output/` directory. Send this file to your users for a seamless experience.
