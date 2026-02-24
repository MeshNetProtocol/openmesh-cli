param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$installerRoot = Join-Path $repoRoot "openmesh-win\installer"
$reportsDir = Join-Path $scriptRoot "reports"
$buildPackageScript = Join-Path $installerRoot "Build-Package.ps1"
$outputDir = Join-Path $env:TEMP ("openmesh-win-p6-wintun-output-" + [Guid]::NewGuid().ToString("N"))
$expandDir = Join-Path $env:TEMP ("openmesh-win-p6-wintun-expand-" + [Guid]::NewGuid().ToString("N"))
$fakeWintun = Join-Path $env:TEMP ("openmesh-win-fake-wintun-" + [Guid]::NewGuid().ToString("N") + ".dll")
$missingWintun = Join-Path $env:TEMP ("openmesh-win-missing-wintun-" + [Guid]::NewGuid().ToString("N") + ".dll")

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

function Invoke-ScriptCapture([string]$filePath, [string[]]$argumentsList) {
    $output = @()
    $exitCode = 0
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $filePath @argumentsList 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output += $_
        $exitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | ForEach-Object { [string]$_ })
    }
}

Set-Content -Path $fakeWintun -Value "fake-wintun" -Encoding ASCII

$case1 = Invoke-ScriptCapture -filePath $buildPackageScript -argumentsList @(
    "-Configuration", $Configuration,
    "-OutputDir", $outputDir,
    "-RequireWintun",
    "-WintunSourcePath", $missingWintun
)
if ($case1.ExitCode -ne 0 -and (($case1.Output -join "`n") -match "Configured wintun source path not found")) {
    Add-Result "PASS" "require_missing_wintun" "Missing explicit wintun path is rejected."
} else {
    Add-Result "FAIL" "require_missing_wintun" ("Expected missing wintun rejection. exit=" + $case1.ExitCode + "; output=" + (($case1.Output | Select-Object -Last 6) -join " | "))
}

$case2 = Invoke-ScriptCapture -filePath $buildPackageScript -argumentsList @(
    "-Configuration", $Configuration,
    "-OutputDir", $outputDir,
    "-RequireWintun",
    "-AutoCopyWintun",
    "-WintunSourcePath", $fakeWintun
)
if ($case2.ExitCode -eq 0) {
    Add-Result "PASS" "require_copy_wintun" "Package build succeeded with explicit wintun source."
} else {
    Add-Result "FAIL" "require_copy_wintun" ("Package build failed. exit=" + $case2.ExitCode + "; output=" + (($case2.Output | Select-Object -Last 6) -join " | "))
}

$archivePath = Join-Path $outputDir ("OpenMeshWin-" + $Configuration + ".zip")
if (-not (Test-Path $archivePath)) {
    Add-Result "FAIL" "package_zip" ("Package zip missing: " + $archivePath)
} else {
    Add-Result "PASS" "package_zip" ("Package zip present: " + $archivePath)
    if (Test-Path $expandDir) {
        Remove-Item -Path $expandDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $expandDir -ItemType Directory -Force | Out-Null
    Expand-Archive -Path $archivePath -DestinationPath $expandDir -Force
    $packagedCoreWintun = Join-Path $expandDir "core\wintun.dll"
    $packagedServiceWintun = Join-Path $expandDir "service\wintun.dll"
    if ((Test-Path $packagedCoreWintun) -and (Test-Path $packagedServiceWintun)) {
        Add-Result "PASS" "wintun_copied" "wintun.dll copied into package core/service directories."
    } else {
        Add-Result "FAIL" "wintun_copied" ("wintun copy missing in package. core=" + (Test-Path $packagedCoreWintun) + ", service=" + (Test-Path $packagedServiceWintun))
    }
}

if (Test-Path $fakeWintun) {
    Remove-Item -Path $fakeWintun -Force -ErrorAction SilentlyContinue
}
if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path $expandDir) {
    Remove-Item -Path $expandDir -Recurse -Force -ErrorAction SilentlyContinue
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p6-wintun-guard-" + $timestamp + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P6 Wintun Dependency Guard")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("")
foreach ($r in $results) {
    $lines.Add("[" + $r.Level + "] " + $r.Check + " - " + $r.Detail)
}
$lines | Set-Content -Path $reportPath -Encoding UTF8

$failCount = ($results | Where-Object { $_.Level -eq "FAIL" } | Measure-Object).Count
$warnCount = ($results | Where-Object { $_.Level -eq "WARN" } | Measure-Object).Count

Write-Host ("P6 wintun guard report written: " + $reportPath)
Write-Host ("Summary: FAIL=" + $failCount + " WARN=" + $warnCount)

if ($failCount -gt 0) {
    throw "P6 wintun guard checks failed."
}

Write-Host "P6 wintun guard checks passed."
