param(
    [string]$Configuration = "Release",
    [switch]$SkipPackageBuild,
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$reportsDir = Join-Path $scriptRoot "reports"
$serviceProject = Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\OpenMeshWin.Service.csproj"
$serviceOutputRootWindows = Join-Path $repoRoot ("openmesh-win\service\OpenMeshWin.Service\bin\" + $Configuration + "\net10.0-windows")
$serviceOutputRoot = Join-Path $repoRoot ("openmesh-win\service\OpenMeshWin.Service\bin\" + $Configuration + "\net10.0")
$serviceExe = Join-Path $serviceOutputRootWindows "OpenMeshWin.Service.exe"
$serviceDll = Join-Path $serviceOutputRootWindows "OpenMeshWin.Service.dll"
$serviceExeLegacy = Join-Path $serviceOutputRoot "OpenMeshWin.Service.exe"
$serviceDllLegacy = Join-Path $serviceOutputRoot "OpenMeshWin.Service.dll"
$heartbeatPath = Join-Path $env:LOCALAPPDATA "OpenMeshWin\service\service_heartbeat"
$buildPackageScript = Join-Path $repoRoot "openmesh-win\installer\Build-Package.ps1"
$packageOutputDir = Join-Path $repoRoot "openmesh-win\installer\output"
$packageZip = Join-Path $packageOutputDir ("OpenMeshWin-" + $Configuration + ".zip")

if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

$results = New-Object System.Collections.Generic.List[psobject]

function Add-Result([string]$level, [string]$check, [string]$detail) {
    $results.Add([pscustomobject]@{
            Level = $level
            Check = $check
            Detail = $detail
        })
}

function Stop-ConflictingProcesses {
    $names = @(
        "OpenMeshWin.Service",
        "OpenMeshWin",
        "OpenMeshWin.Core"
    )
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ServiceBinaryPath {
    if (Test-Path $serviceExe) {
        return $serviceExe
    }
    if (Test-Path $serviceDll) {
        return $serviceDll
    }
    if (Test-Path $serviceExeLegacy) {
        return $serviceExeLegacy
    }
    if (Test-Path $serviceDllLegacy) {
        return $serviceDllLegacy
    }
    return $null
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses
}

if (-not (Test-Path $serviceProject)) {
    Add-Result "FAIL" "service_project" ("Missing project file: " + $serviceProject)
} else {
    Add-Result "PASS" "service_project" ("Project found: " + $serviceProject)
}

if (Test-Path $heartbeatPath) {
    Remove-Item -Path $heartbeatPath -Force -ErrorAction SilentlyContinue
}

& dotnet build $serviceProject -c $Configuration -v minimal | Out-Null
if ($LASTEXITCODE -eq 0) {
    Add-Result "PASS" "build_service" ("dotnet build OpenMeshWin.Service succeeded (" + $Configuration + ").")
} else {
    Add-Result "FAIL" "build_service" ("dotnet build OpenMeshWin.Service failed with exit code " + $LASTEXITCODE)
}

$serviceBinary = Resolve-ServiceBinaryPath
if ($null -eq $serviceBinary) {
    Add-Result "FAIL" "service_binary" ("Missing service binary in " + $serviceOutputRootWindows + " or " + $serviceOutputRoot)
} else {
    Add-Result "PASS" "service_binary" ("Service binary present: " + $serviceBinary)

    if ($serviceBinary.ToLowerInvariant().EndsWith(".dll")) {
        & dotnet $serviceBinary --run-once
    } else {
        & $serviceBinary --run-once
    }
    if ($LASTEXITCODE -eq 0) {
        Add-Result "PASS" "service_run_once" "OpenMeshWin.Service --run-once exited with code 0."
    } else {
        Add-Result "FAIL" "service_run_once" ("OpenMeshWin.Service --run-once failed with exit code " + $LASTEXITCODE)
    }
}

if (Test-Path $heartbeatPath) {
    $heartbeatItem = Get-Item -Path $heartbeatPath
    $ageSeconds = [Math]::Abs(((Get-Date).ToUniversalTime() - $heartbeatItem.LastWriteTimeUtc).TotalSeconds)
    if ($ageSeconds -le 120) {
        Add-Result "PASS" "service_heartbeat" ("service_heartbeat exists and is fresh: " + $heartbeatPath)
    } else {
        Add-Result "FAIL" "service_heartbeat" ("service_heartbeat is stale (" + [int]$ageSeconds + "s): " + $heartbeatPath)
    }
} else {
    Add-Result "FAIL" "service_heartbeat" ("service_heartbeat missing: " + $heartbeatPath)
}

if (-not $SkipPackageBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildPackageScript -Configuration $Configuration -OutputDir $packageOutputDir
    if ($LASTEXITCODE -eq 0) {
        Add-Result "PASS" "build_package" "Build-Package.ps1 succeeded."
    } else {
        Add-Result "FAIL" "build_package" ("Build-Package.ps1 failed with exit code " + $LASTEXITCODE)
    }
} else {
    Add-Result "WARN" "build_package" "Skipped by -SkipPackageBuild."
}

if (Test-Path $packageZip) {
    Add-Result "PASS" "package_zip" ("Package zip present: " + $packageZip)
    $expandDir = Join-Path $env:TEMP ("openmesh-win-p6-service-" + [Guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -Path $packageZip -DestinationPath $expandDir -Force
        $packagedServiceExe = Join-Path $expandDir "service\OpenMeshWin.Service.exe"
        $packagedServiceDll = Join-Path $expandDir "service\OpenMeshWin.Service.dll"
        if ((Test-Path $packagedServiceExe) -or (Test-Path $packagedServiceDll)) {
            Add-Result "PASS" "package_service_payload" "Package includes service payload."
        } else {
            Add-Result "FAIL" "package_service_payload" "Package missing service payload under service\\."
        }

        $packagedRegisterScript = Join-Path $expandDir "Register-OpenMeshWin-Service.ps1"
        $packagedUnregisterScript = Join-Path $expandDir "Unregister-OpenMeshWin-Service.ps1"
        if ((Test-Path $packagedRegisterScript) -and (Test-Path $packagedUnregisterScript)) {
            Add-Result "PASS" "package_service_scripts" "Package includes service register/unregister scripts."
        } else {
            Add-Result "FAIL" "package_service_scripts" "Package missing service register/unregister scripts."
        }
    }
    finally {
        if (Test-Path $expandDir) {
            Remove-Item -Path $expandDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Add-Result "FAIL" "package_zip" ("Package zip missing: " + $packageZip)
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p6-service-scaffold-" + $timestamp + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P6 Service Scaffold")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("")
foreach ($r in $results) {
    $lines.Add("[" + $r.Level + "] " + $r.Check + " - " + $r.Detail)
}
$lines | Set-Content -Path $reportPath -Encoding UTF8

$failCount = ($results | Where-Object { $_.Level -eq "FAIL" } | Measure-Object).Count
$warnCount = ($results | Where-Object { $_.Level -eq "WARN" } | Measure-Object).Count

Write-Host ("P6 service scaffold report written: " + $reportPath)
Write-Host ("Summary: FAIL=" + $failCount + " WARN=" + $warnCount)

if ($failCount -gt 0) {
    throw "P6 service scaffold checks failed."
}

Write-Host "P6 service scaffold checks passed."
