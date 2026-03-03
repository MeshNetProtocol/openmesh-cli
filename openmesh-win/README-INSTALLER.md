# OpenMeshWin Professional Installer (MSI)

This directory contains the scripts and WiX templates to generate a professional, self-contained MSI installer for the OpenMesh application.

## Prerequisites
- **.NET SDK 8.0+**
- **WiX Toolset v4 or v5+**: The modern WiX version. Install via `dotnet tool install --global wix`.
- **Go 1.25+**: For building the core DLL.

## How to Generate the Installer

We have provided a master script that automates the entire process:
1.  Open PowerShell.
2.  Navigate to the `installer/` directory:
    ```powershell
    cd openmesh-win/installer
    ```
3.  Run the master build script:
    ```powershell
    ./Create-Full-Installer.ps1
    ```

## What the master script does:
- **Build Core**: Calls `go-cli-lib/cmd/openmesh-win-core-embedded/Build-Core-Windows.ps1` to ensure the latest `openmesh_core.dll` (with embedded drivers) is built and synced.
- **Publish App**: Executes `dotnet publish` in **Self-Contained** mode (`-r win-x64 --self-contained`). This bundles the .NET runtime, so users don't need to install anything.
- **Package MSI**: Uses **WiX v4+** to package the published files into a single `.msi` file.
  - Adds Desktop and Start Menu shortcuts.
  - Correctly bundles internal DLLs into the installation path.

## Why use this Installer?
- **Zero-Dependency**: No .NET installer popup for users.
- **Embedded VPN Drivers**: Wintun drivers are handled internally by the Core DLL.
- **Professional Presence**: Standard Windows "Add/Remove Programs" support.

---
**Note**: The generated `.msi` output will be in the `installer/output/` directory. Send this file to your users for a seamless experience.
