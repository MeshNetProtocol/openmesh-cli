param(
    [string]$InstallDir = "$env:ProgramFiles\OpenMeshWin",
    [switch]$RemoveUserData,
    [switch]$SkipRegistry
)

$ErrorActionPreference = "Stop"

function Remove-StartupEntry {
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $runKeyPath -Name "OpenMeshWin" -ErrorAction SilentlyContinue
}

function Remove-UninstallEntry {
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenMeshWin" -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    Get-Process -Name "OpenMeshWin" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "OpenMeshWin.Core" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "OpenMeshWin.Service" -ErrorAction SilentlyContinue | Stop-Process -Force

    if (-not $SkipRegistry) {
        Remove-StartupEntry
        Remove-UninstallEntry
    }

    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
    }

    if ($RemoveUserData) {
        $userDataDir = Join-Path $env:APPDATA "OpenMeshWin"
        if (Test-Path $userDataDir) {
            Remove-Item -Path $userDataDir -Recurse -Force
        }
    }

    Write-Host "OpenMeshWin uninstalled."
}
catch {
    Write-Error "Uninstall failed: $($_.Exception.Message)"
    throw
}
