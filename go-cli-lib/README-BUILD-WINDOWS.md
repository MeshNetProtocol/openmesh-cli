# OpenMesh Go Core Build Guide (Windows)

This directory contains the Go core implementation for OpenMesh, including the embedded VPN engine (sing-box) and virtul network drivers.

## Prerequisites
- **Go 1.25+**
- **GCC (MinGW-w64)**: Required for CGO build. (e.g. via MSYS2 or standalone MinGW)
- **PowerShell 7+** (Recommended)

## How to Build the Windows Core DLL

To generate the self-contained `openmesh_core.dll` and `openmesh_core.h` files required by the Windows UI project, follow these steps:

1. Open PowerShell.
2. Navigate to the embedded core directory:
   ```powershell
   cd cmd/openmesh-win-core-embedded
   ```
3. Run the automated build script:
   ```powershell
   ./Build-Core-Windows.ps1
   ```

### What the script does:
- **Dependency Retrieval**: Automatically downloads the official `wintun.dll` driver from wintun.net if not found in `embeds/`.
- **Self-Contained Build**: Builds the Go source and **embeds** the driver binary directly into the resulting DLL.
- **Auto-Sync**: Automatically copies the generated `.dll` and `.h` to the `openmesh-win/libs` directory, making them immediately available for the Windows UI project.

## Project Structure
- `main.go`: Entry point for the Core DLL, handles C exports.
- `embeds/`: Contains binary assets like `wintun.dll` that are compiled into the core.
- `Build-Core-Windows.ps1`: The primary build and sync script.

---
**Note**: The generated DLL does NOT require any external dependencies like `sing-box.exe` or `wintun.dll` to be present on the target machine. The core handles driver extraction and initialization automatically at runtime.
