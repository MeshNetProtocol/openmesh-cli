param(
    [int]$LatestMaxAgeMinutes = 15,
    [switch]$ShowLatestSummaryOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

if ($LatestMaxAgeMinutes -lt 0) {
    throw "LatestMaxAgeMinutes must be >= 0."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$preflightScript = Join-Path $scriptRoot "Run-P6-Release-Preflight.ps1"
$reportsDir = Join-Path $scriptRoot "reports"
$snapshotPath = Join-Path $reportsDir "p7-rc-ready-check-latest-gate-snapshot.json"

if (-not (Test-Path $preflightScript)) {
    throw ("Missing script: " + $preflightScript)
}
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $preflightScript,
    "-ShowLatest",
    "-ShowLatestGateSnapshot",
    "-LatestGateSnapshotPath", $snapshotPath,
    "-LatestRequireNoFail",
    "-LatestFailOnWarn",
    "-LatestRequireTextJsonConsistent",
    "-LatestRequireSameGeneratedAtUtc",
    "-LatestMaxAgeMinutes", [string]$LatestMaxAgeMinutes
)
if ($ShowLatestSummaryOnly) {
    $args += "-ShowLatestSummaryOnly"
}

& powershell @args
if ($LASTEXITCODE -ne 0) {
    throw ("P7 RC ready latest gate failed with exit code " + $LASTEXITCODE + ".")
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p7-rc-ready-check-" + $timestamp + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P7 RC Ready Check")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("LatestMaxAgeMinutes: " + $LatestMaxAgeMinutes)
$lines.Add("SnapshotPath: " + $snapshotPath)
$lines.Add("Result: PASS")
$lines | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ("P7 RC ready check report written: " + $reportPath)
Write-Host ("P7 RC ready check snapshot: " + $snapshotPath)
Write-Host "P7 RC ready check passed."
