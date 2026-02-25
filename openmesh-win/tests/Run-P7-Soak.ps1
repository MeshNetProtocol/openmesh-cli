param(
    [int]$DurationMinutes = 1440,
    [int]$IntervalSeconds = 300,
    [int]$LatestMaxAgeMinutes = 30
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

if ($DurationMinutes -le 0) { throw "DurationMinutes must be > 0." }
if ($IntervalSeconds -le 0) { throw "IntervalSeconds must be > 0." }
if ($LatestMaxAgeMinutes -lt 0) { throw "LatestMaxAgeMinutes must be >= 0." }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$readyCheckScript = Join-Path $scriptRoot "Run-P7-RC-Ready-Check.ps1"
$reportsDir = Join-Path $scriptRoot "reports"

if (-not (Test-Path $readyCheckScript)) {
    throw ("Missing script: " + $readyCheckScript)
}
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

$started = Get-Date
$deadline = $started.AddMinutes($DurationMinutes)
$results = New-Object System.Collections.Generic.List[psobject]
$iteration = 0

while ((Get-Date) -lt $deadline) {
    $iteration++
    $now = Get-Date
    Write-Host ("[SOAK] iteration=" + $iteration + " time=" + $now.ToString("yyyy-MM-dd HH:mm:ss"))

    & powershell -NoProfile -ExecutionPolicy Bypass -File $readyCheckScript -LatestMaxAgeMinutes $LatestMaxAgeMinutes -ShowLatestSummaryOnly | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    $results.Add([pscustomobject]@{
            Iteration = [int]$iteration
            TimeUtc = $now.ToUniversalTime().ToString("o")
            ExitCode = [int]$exitCode
            Passed = [bool]($exitCode -eq 0)
        })

    if ($exitCode -ne 0) {
        break
    }

    if ((Get-Date).AddSeconds($IntervalSeconds) -gt $deadline) {
        break
    }
    Start-Sleep -Seconds $IntervalSeconds
}

$failCount = ($results | Where-Object { -not $_.Passed } | Measure-Object).Count
$passCount = ($results | Where-Object { $_.Passed } | Measure-Object).Count
$ended = Get-Date

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p7-soak-" + $timestamp + ".txt")
$jsonReportPath = Join-Path $reportsDir ("p7-soak-" + $timestamp + ".json")

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P7 Soak")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("DurationMinutes: " + $DurationMinutes)
$lines.Add("IntervalSeconds: " + $IntervalSeconds)
$lines.Add("LatestMaxAgeMinutes: " + $LatestMaxAgeMinutes)
$lines.Add("StartedAtUtc: " + $started.ToUniversalTime().ToString("o"))
$lines.Add("EndedAtUtc: " + $ended.ToUniversalTime().ToString("o"))
$lines.Add("")
foreach ($r in $results) {
    $level = if ($r.Passed) { "PASS" } else { "FAIL" }
    $lines.Add("[" + $level + "] iter=" + $r.Iteration + " exit=" + $r.ExitCode + " time=" + $r.TimeUtc)
}
$lines.Add("")
$lines.Add("Summary: FAIL=" + $failCount + " PASS=" + $passCount)
$lines | Set-Content -Path $reportPath -Encoding UTF8

$json = [pscustomobject]@{
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    RepoRoot = $repoRoot
    Parameters = [pscustomobject]@{
        DurationMinutes = [int]$DurationMinutes
        IntervalSeconds = [int]$IntervalSeconds
        LatestMaxAgeMinutes = [int]$LatestMaxAgeMinutes
    }
    Window = [pscustomobject]@{
        StartedAtUtc = $started.ToUniversalTime().ToString("o")
        EndedAtUtc = $ended.ToUniversalTime().ToString("o")
    }
    Summary = [pscustomobject]@{
        Fail = [int]$failCount
        Pass = [int]$passCount
    }
    Iterations = $results
}
$json | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReportPath -Encoding UTF8

Write-Host ("P7 soak report written: " + $reportPath)
Write-Host ("P7 soak json report written: " + $jsonReportPath)
Write-Host ("Summary: FAIL=" + $failCount + " PASS=" + $passCount)

if ($failCount -gt 0) {
    throw "P7 soak failed."
}

Write-Host "P7 soak passed."
