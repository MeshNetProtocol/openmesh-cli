param(
    [string]$InstallDir = "$env:ProgramFiles\OpenMeshWin",
    [switch]$RemoveUserData,
    [switch]$SkipService,
    [string]$ServiceName = "OpenMeshWinService",
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

function Remove-ServiceEntry {
    param([string]$installDir, [string]$name)

    $unregisterScript = Join-Path $installDir "Unregister-OpenMeshWin-Service.ps1"
    if (Test-Path $unregisterScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $unregisterScript -ServiceName $name
        return
    }

    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $name | Out-Null
}

try {
    Get-Process -Name "OpenMeshWin" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "OpenMeshWin.Core" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "OpenMeshWin.Service" -ErrorAction SilentlyContinue | Stop-Process -Force

    if (-not $SkipService) {
        Remove-ServiceEntry -installDir $InstallDir -name $ServiceName
    }

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
