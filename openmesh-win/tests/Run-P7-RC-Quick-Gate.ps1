param(
    [switch]$SkipBuild,
    [switch]$SkipGoCoreBuild,
    [switch]$SkipStopConflictingProcesses,
    [int]$LatestMaxAgeMinutes = 30,
    [switch]$LatestFailOnWarn,
    [switch]$LatestGatesSmokeShowDetails
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
$latestGatesSmokeScript = Join-Path $scriptRoot "Run-P6-Release-Preflight-Latest-Gates-Smoke.ps1"
$reportsDir = Join-Path $scriptRoot "reports"
$snapshotPath = Join-Path $reportsDir "p7-rc-quick-gate-latest-gate-snapshot.json"

if (-not (Test-Path $preflightScript)) {
    throw ("Missing script: " + $preflightScript)
}
if (-not (Test-Path $latestGatesSmokeScript)) {
    throw ("Missing script: " + $latestGatesSmokeScript)
}
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

function Invoke-Step([string]$id, [string]$title, [string]$scriptPath, [string[]]$ScriptArgs) {
    $startUtc = (Get-Date).ToUniversalTime().ToString("o")
    $argDisplay = [string]::Join(" ", @($ScriptArgs))
    Write-Host ("[STEP] " + $id + " - " + $title)
    if (-not [string]::IsNullOrWhiteSpace($argDisplay)) {
        Write-Host ("        args: " + $argDisplay)
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ScriptArgs | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    $endUtc = (Get-Date).ToUniversalTime().ToString("o")

    return [pscustomobject]@{
        Id = $id
        Title = $title
        ScriptPath = $scriptPath
        Args = $ScriptArgs
        ExitCode = [int]$exitCode
        Passed = [bool]($exitCode -eq 0)
        StartedAtUtc = $startUtc
        EndedAtUtc = $endUtc
    }
}

function Get-LatestReport([string]$pattern) {
    $item = Get-ChildItem -Path $reportsDir -Filter $pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $item) {
        return ""
    }
    return $item.FullName
}

$steps = New-Object System.Collections.Generic.List[psobject]
$stopEarly = $false

$refreshArgs = @(
    "-WriteJsonReport"
)
if ($SkipBuild) { $refreshArgs += "-SkipBuild" }
if ($SkipGoCoreBuild) { $refreshArgs += "-SkipGoCoreBuild" }
if ($SkipStopConflictingProcesses) { $refreshArgs += "-SkipStopConflictingProcesses" }

$steps.Add((Invoke-Step -id "refresh_latest" -title "Refresh latest preflight report/json" -scriptPath $preflightScript -ScriptArgs $refreshArgs))
if (-not $steps[$steps.Count - 1].Passed) {
    $stopEarly = $true
}

if (-not $stopEarly) {
    $smokeArgs = @()
    if ($LatestGatesSmokeShowDetails) { $smokeArgs += "-ShowDetails" }
    $steps.Add((Invoke-Step -id "latest_gates_smoke" -title "Run latest gates smoke regression" -scriptPath $latestGatesSmokeScript -ScriptArgs $smokeArgs))
    if (-not $steps[$steps.Count - 1].Passed) {
        $stopEarly = $true
    }
}

if (-not $stopEarly) {
    $latestGateArgs = @(
        "-ShowLatest",
        "-ShowLatestSummaryOnly",
        "-ShowLatestGateSnapshot",
        "-LatestGateSnapshotPath", $snapshotPath,
        "-LatestRequireNoFail",
        "-LatestRequireTextJsonConsistent",
        "-LatestRequireSameGeneratedAtUtc",
        "-LatestMaxAgeMinutes", [string]$LatestMaxAgeMinutes
    )
    if ($LatestFailOnWarn) { $latestGateArgs += "-LatestFailOnWarn" }
    $steps.Add((Invoke-Step -id "latest_gate_check" -title "Gate latest summary consistency and freshness" -scriptPath $preflightScript -ScriptArgs $latestGateArgs))
}

$failedCount = ($steps | Where-Object { -not $_.Passed } | Measure-Object).Count
$passedCount = ($steps | Where-Object { $_.Passed } | Measure-Object).Count

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p7-rc-quick-gate-" + $timestamp + ".txt")
$jsonReportPath = Join-Path $reportsDir ("p7-rc-quick-gate-" + $timestamp + ".json")

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P7 RC Quick Gate")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("SnapshotPath: " + $snapshotPath)
$lines.Add("")
foreach ($step in $steps) {
    $level = if ($step.Passed) { "PASS" } else { "FAIL" }
    $lines.Add("[" + $level + "] " + $step.Id + " exit=" + $step.ExitCode + " script=" + $step.ScriptPath)
}
$lines.Add("")
$lines.Add("LatestPreflight: " + (Get-LatestReport -pattern "p6-release-preflight-*.txt"))
$lines.Add("LatestPreflightJson: " + (Get-LatestReport -pattern "p6-release-preflight-*.json"))
$lines.Add("LatestGatesSmoke: " + (Get-LatestReport -pattern "p6-release-preflight-latest-gates-smoke-*.txt"))
$lines.Add("")
$lines.Add("Summary: FAIL=" + $failedCount + " PASS=" + $passedCount)
$lines | Set-Content -Path $reportPath -Encoding UTF8

$jsonReport = [pscustomobject]@{
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    RepoRoot = $repoRoot
    SnapshotPath = $snapshotPath
    Parameters = [pscustomobject]@{
        SkipBuild = [bool]$SkipBuild
        SkipGoCoreBuild = [bool]$SkipGoCoreBuild
        SkipStopConflictingProcesses = [bool]$SkipStopConflictingProcesses
        LatestMaxAgeMinutes = [int]$LatestMaxAgeMinutes
        LatestFailOnWarn = [bool]$LatestFailOnWarn
        LatestGatesSmokeShowDetails = [bool]$LatestGatesSmokeShowDetails
    }
    Summary = [pscustomobject]@{
        Fail = [int]$failedCount
        Pass = [int]$passedCount
    }
    Steps = $steps
    Artifacts = [pscustomobject]@{
        LatestPreflight = (Get-LatestReport -pattern "p6-release-preflight-*.txt")
        LatestPreflightJson = (Get-LatestReport -pattern "p6-release-preflight-*.json")
        LatestGatesSmoke = (Get-LatestReport -pattern "p6-release-preflight-latest-gates-smoke-*.txt")
    }
}
$jsonReport | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReportPath -Encoding UTF8

Write-Host ("P7 RC quick gate report written: " + $reportPath)
Write-Host ("P7 RC quick gate json report written: " + $jsonReportPath)
Write-Host ("Summary: FAIL=" + $failedCount + " PASS=" + $passedCount)

if ($failedCount -gt 0) {
    throw "P7 RC quick gate failed."
}

Write-Host "P7 RC quick gate passed."
