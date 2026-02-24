param(
    [string]$InstallDir = "$env:ProgramFiles\OpenMeshWin",
    [string]$Configuration = "Release",
    [switch]$EnableStartup,
    [switch]$SkipPublish,
    [switch]$SkipRegistry
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

$uiProject = Join-Path $repoRoot "openmesh-win\OpenMeshWin.csproj"
$coreProject = Join-Path $repoRoot "openmesh-win\core\OpenMeshWin.Core\OpenMeshWin.Core.csproj"
$serviceProject = Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\OpenMeshWin.Service.csproj"

$stagingRoot = Join-Path $scriptRoot "staging"
$stagingApp = Join-Path $stagingRoot "app"
$stagingCore = Join-Path $stagingRoot "core"
$stagingService = Join-Path $stagingRoot "service"
$installApp = Join-Path $InstallDir "app"
$installCore = Join-Path $InstallDir "core"
$installService = Join-Path $InstallDir "service"

$createdInstallDir = $false

function Set-StartupEntry([bool]$enabled, [string]$appExePath) {
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $name = "OpenMeshWin"
    if (-not (Test-Path $runKeyPath)) {
        New-Item -Path $runKeyPath -Force | Out-Null
    }

    if ($enabled) {
        Set-ItemProperty -Path $runKeyPath -Name $name -Value "`"$appExePath`""
    } else {
        Remove-ItemProperty -Path $runKeyPath -Name $name -ErrorAction SilentlyContinue
    }
}

function Set-UninstallEntry([string]$installDir) {
    $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenMeshWin"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    $uninstallScript = Join-Path $installDir "Uninstall-OpenMeshWin.ps1"
    $uninstallCmd = "powershell.exe -ExecutionPolicy Bypass -File `"$uninstallScript`" -InstallDir `"$installDir`""

    Set-ItemProperty -Path $keyPath -Name "DisplayName" -Value "OpenMeshWin"
    Set-ItemProperty -Path $keyPath -Name "Publisher" -Value "OpenMesh"
    Set-ItemProperty -Path $keyPath -Name "DisplayVersion" -Value "0.1.0"
    Set-ItemProperty -Path $keyPath -Name "InstallLocation" -Value $installDir
    Set-ItemProperty -Path $keyPath -Name "UninstallString" -Value $uninstallCmd
}

try {
    if (-not $SkipPublish) {
        if (Test-Path $stagingRoot) {
            Remove-Item -Path $stagingRoot -Recurse -Force
        }

        New-Item -Path $stagingApp -ItemType Directory -Force | Out-Null
        New-Item -Path $stagingCore -ItemType Directory -Force | Out-Null
        New-Item -Path $stagingService -ItemType Directory -Force | Out-Null

        & dotnet publish $uiProject -c $Configuration -o $stagingApp
        & dotnet publish $coreProject -c $Configuration -o $stagingCore
        & dotnet publish $serviceProject -c $Configuration -o $stagingService
    } else {
        if (-not (Test-Path $stagingApp) -or -not (Test-Path $stagingCore) -or -not (Test-Path $stagingService)) {
            throw "SkipPublish was set but staging app/core/service output is missing."
        }
    }

    if (-not (Test-Path $InstallDir)) {
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        $createdInstallDir = $true
    }

    New-Item -Path $installApp -ItemType Directory -Force | Out-Null
    New-Item -Path $installCore -ItemType Directory -Force | Out-Null
    New-Item -Path $installService -ItemType Directory -Force | Out-Null

    Copy-Item -Path (Join-Path $stagingApp "*") -Destination $installApp -Recurse -Force
    Copy-Item -Path (Join-Path $stagingCore "*") -Destination $installCore -Recurse -Force
    Copy-Item -Path (Join-Path $stagingService "*") -Destination $installService -Recurse -Force
    Copy-Item -Path (Join-Path $scriptRoot "Uninstall-OpenMeshWin.ps1") -Destination (Join-Path $InstallDir "Uninstall-OpenMeshWin.ps1") -Force

    if (-not $SkipRegistry) {
        $appExe = Join-Path $installApp "OpenMeshWin.exe"
        Set-StartupEntry -enabled:$EnableStartup.IsPresent -appExePath $appExe
        Set-UninstallEntry -installDir $InstallDir
    }

    Write-Host "OpenMeshWin installed successfully."
    Write-Host "InstallDir: $InstallDir"
    Write-Host "StartupEnabled: $($EnableStartup.IsPresent)"
    Write-Host "RegistryIntegration: $(-not $SkipRegistry)"
}
catch {
    Write-Warning "Install failed. Rolling back: $($_.Exception.Message)"

    if (-not $SkipRegistry) {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OpenMeshWin" -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenMeshWin" -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $InstallDir -and $createdInstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    throw
}
