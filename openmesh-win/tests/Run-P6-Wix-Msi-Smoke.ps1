param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0-p6"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$installerRoot = Join-Path $repoRoot "openmesh-win\installer"
$outputDir = Join-Path $installerRoot "output"
$buildPackageScript = Join-Path $installerRoot "Build-Package.ps1"
$buildMsiScript = Join-Path $installerRoot "Build-P6-Wix-Msi.ps1"

function Resolve-WixToolchainType {
    $wix = Get-Command wix -ErrorAction SilentlyContinue
    if ($null -ne $wix -and -not [string]::IsNullOrWhiteSpace($wix.Source) -and (Test-Path $wix.Source)) {
        return "wix4"
    }
    $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
    $light = Get-Command light.exe -ErrorAction SilentlyContinue
    if ($null -ne $candle -and $null -ne $light -and (Test-Path $candle.Source) -and (Test-Path $light.Source)) {
        return "wix3"
    }
    return ""
}

function Stop-ConflictingProcesses {
    $targets = New-Object System.Collections.Generic.List[object]
    $processes = Get-CimInstance Win32_Process
    foreach ($p in $processes) {
        $nameText = if ($null -eq $p.Name) { "" } else { [string]$p.Name }
        $name = $nameText.ToLowerInvariant()
        if ($name -eq "openmeshwin.exe" -or $name -eq "openmeshwin.core.exe" -or $name -eq "openmesh-win-core.exe") {
            $targets.Add($p)
            continue
        }
        if ($name -eq "dotnet.exe") {
            $cmdText = if ($null -eq $p.CommandLine) { "" } else { [string]$p.CommandLine }
            if ($cmdText.ToLowerInvariant().Contains("openmeshwin.core.dll")) {
                $targets.Add($p)
            }
        }
    }
    foreach ($target in $targets) {
        try {
            Stop-Process -Id ([int]$target.ProcessId) -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

function Invoke-BuildPackageWithRetry {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $buildPackageScript -Configuration $Configuration -OutputDir $outputDir
        if ($LASTEXITCODE -eq 0) {
            return
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 800
            Stop-ConflictingProcesses
        }
    }
    throw "Build-Package.ps1 failed after retry."
}

Stop-ConflictingProcesses
Invoke-BuildPackageWithRetry

$zipPath = Join-Path $outputDir ("OpenMeshWin-" + $Configuration + ".zip")
if (-not (Test-Path $zipPath)) {
    throw "Package zip missing after build: $zipPath"
}

$toolchain = Resolve-WixToolchainType
if ([string]::IsNullOrWhiteSpace($toolchain)) {
    Write-Warning "WiX toolset not found. MSI generation skipped in this environment."
    Write-Host "P6 wix msi smoke checks passed (toolchain missing, package-only validation complete)."
    exit 0
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $buildMsiScript -Configuration $Configuration -Version $Version -OutputDir $outputDir -SkipBuildPackage
if ($LASTEXITCODE -ne 0) {
    throw "Build-P6-Wix-Msi.ps1 failed with exit code $LASTEXITCODE."
}

$msiPath = Join-Path $outputDir ("OpenMeshWin-" + $Version + ".msi")
if (-not (Test-Path $msiPath)) {
    throw "MSI output missing: $msiPath"
}

Write-Host ("Detected WiX toolchain: " + $toolchain)
Write-Host ("MSI artifact: " + $msiPath)
Write-Host "P6 wix msi smoke checks passed."
