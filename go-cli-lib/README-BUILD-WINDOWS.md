# OpenMesh Go Core Build Guide (Windows)

This directory contains the Go core implementation for OpenMesh, including the embedded VPN engine (sing-box) and virtul network drivers.

## Prerequisites
- **Go 1.25+**
- **GCC (MinGW-w64)**: Required for CGO build. (e.g. via MSYS2 or standalone MinGW)
- **PowerShell 7+** (Recommended)

## How to Build the Windows Core DLL

Use the unified one-shot build script from the `go-cli-lib` root:

```bat
build_dll.bat
```

You can still invoke these compatibility wrappers if needed, but they now delegate to the same unified entrypoint:

```bat
cmd\openmesh-win-core-embedded\build.bat
```

```powershell
.\cmd\openmesh-win-core-embedded\Build-Core-Windows.ps1
```

### What the unified script does:
- Builds `openmesh_core.dll` and `openmesh_core.h` from `cmd/openmesh-win-core-embedded`
- Copies the generated artifacts into `openmesh-win/libs`
- Syncs the same artifacts into `openmesh-win/bin/Debug/net10.0-windows/libs` if that output exists
- Syncs the same artifacts into `openmesh-win/bin/Release/net10.0-windows/libs` if that output exists
- Copies `libwinpthread-1.dll` from `C:\msys64\ucrt64\bin` when available

## Project Structure
- `main.go`: Entry point for the Core DLL, handles C exports.
- `embeds/`: Contains binary assets like `wintun.dll` that are compiled into the core.
- `build_dll.bat`: The primary one-shot build and sync script.
- `cmd/openmesh-win-core-embedded/build.bat`: Compatibility wrapper to the unified script.
- `cmd/openmesh-win-core-embedded/Build-Core-Windows.ps1`: PowerShell wrapper to the unified script.

---
**Note**: The generated DLL does NOT require any external dependency such as `sing-box.exe`. The build script will also sync `libwinpthread-1.dll` when it is available in the standard MSYS2 toolchain path.
