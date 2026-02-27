param(
    [string]$InstallDir = "$env:ProgramFiles\OpenMeshWin",
    [string]$Configuration = "Release",
    [switch]$EnableStartup,
    [switch]$EnableService,
    [switch]$StartService,
    [ValidateSet("Automatic", "Manual", "Disabled")]
    [string]$ServiceStartupType = "Automatic",
    [string]$ServiceName = "OpenMeshWinService",
    [switch]$RequireWintun,
    [switch]$AutoCopyWintun,
    [string]$WintunSourcePath = "",
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
$registerServiceScriptSource = Join-Path $scriptRoot "Register-OpenMeshWin-Service.ps1"
$unregisterServiceScriptSource = Join-Path $scriptRoot "Unregister-OpenMeshWin-Service.ps1"

$createdInstallDir = $false
$serviceRegistrationAttempted = $false
$resolvedWintunPath = ""

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

function Resolve-WintunPath([string]$explicitPath, [string]$repoRoot) {
    if (-not [string]::IsNullOrWhiteSpace($explicitPath)) {
        if (Test-Path $explicitPath) {
            return (Resolve-Path $explicitPath).Path
        }
        throw "Configured wintun source path not found: $explicitPath"
    }

    $candidates = @(
        (Join-Path $repoRoot "openmesh-win\deps\wintun.dll"),
        "C:\Windows\System32\wintun.dll",
        "C:\Windows\SysWOW64\wintun.dll"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return ""
}

try {
    $resolvedWintunPath = Resolve-WintunPath -explicitPath $WintunSourcePath -repoRoot $repoRoot
    if ($RequireWintun -and [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
        throw "wintun.dll is required but was not found. Provide -WintunSourcePath or install wintun."
    }

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
    Copy-Item -Path $registerServiceScriptSource -Destination (Join-Path $InstallDir "Register-OpenMeshWin-Service.ps1") -Force
    Copy-Item -Path $unregisterServiceScriptSource -Destination (Join-Path $InstallDir "Unregister-OpenMeshWin-Service.ps1") -Force

    if ($AutoCopyWintun -and -not [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
        Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $installCore "wintun.dll") -Force
        Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $installService "wintun.dll") -Force
    }

    if (-not $SkipRegistry) {
        $appExe = Join-Path $installApp "OpenMeshWin.exe"
        Set-StartupEntry -enabled:$EnableStartup.IsPresent -appExePath $appExe
        Set-UninstallEntry -installDir $InstallDir
    }

    if ($EnableService) {
        $registerScript = Join-Path $InstallDir "Register-OpenMeshWin-Service.ps1"
        $registerArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $registerScript,
            "-InstallDir", $InstallDir,
            "-ServiceName", $ServiceName,
            "-StartupType", $ServiceStartupType
        )
        if ($StartService -and $ServiceStartupType -ne "Disabled") {
            $registerArgs += "-StartService"
        }
        $serviceRegistrationAttempted = $true
        & powershell @registerArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Register-OpenMeshWin-Service.ps1 failed with exit code $LASTEXITCODE."
        }
    }

    Write-Host "OpenMeshWin installed successfully."
    Write-Host "InstallDir: $InstallDir"
    Write-Host "StartupEnabled: $($EnableStartup.IsPresent)"
    Write-Host "ServiceEnabled: $($EnableService.IsPresent)"
    Write-Host "RequireWintun: $($RequireWintun.IsPresent)"
    Write-Host "AutoCopyWintun: $($AutoCopyWintun.IsPresent)"
    Write-Host "WintunPath: $(if ([string]::IsNullOrWhiteSpace($resolvedWintunPath)) { '(not found)' } else { $resolvedWintunPath })"
    Write-Host "RegistryIntegration: $(-not $SkipRegistry)"
}
catch {
    Write-Warning "Install failed. Rolling back: $($_.Exception.Message)"

    if ($EnableService -and $serviceRegistrationAttempted) {
        $rollbackScript = Join-Path $InstallDir "Unregister-OpenMeshWin-Service.ps1"
        if (Test-Path $rollbackScript) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $rollbackScript -ServiceName $ServiceName | Out-Null
        }
    }

    if (-not $SkipRegistry) {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OpenMeshWin" -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenMeshWin" -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ((Test-Path $InstallDir) -and $createdInstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    throw
}
