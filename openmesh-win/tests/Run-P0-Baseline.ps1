param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$phase8Script = Join-Path $scriptRoot "Run-Phase8-Checks.ps1"
$reportsDir = Join-Path $scriptRoot "reports"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir "p0-baseline-$timestamp.txt"

if (-not (Test-Path $phase8Script)) {
    throw "Phase8 baseline script missing: $phase8Script"
}

New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null

$gitCommit = (& git -C $repoRoot rev-parse --short HEAD 2>$null)
if ([string]::IsNullOrWhiteSpace($gitCommit)) {
    $gitCommit = "unknown"
}

$capturedOutput = New-Object System.Collections.Generic.List[string]
$passed = $false

try {
    $capturedOutput.Add("Running: $phase8Script -Configuration $Configuration")

    $phase8Args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $phase8Script,
        "-Configuration", $Configuration
    )
    if ($SkipStopConflictingProcesses) {
        $phase8Args += "-SkipStopConflictingProcesses"
    }

    & powershell @phase8Args 2>&1 | ForEach-Object {
        $line = "$_"
        $capturedOutput.Add($line)
        Write-Host $line
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Phase8 script exited with code $LASTEXITCODE."
    }

    $passed = $true
    Write-Host "P0 baseline checks passed."
}
finally {
    $status = if ($passed) { "PASS" } else { "FAIL" }
    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add("OpenMesh Windows P0 Baseline Report")
    $reportLines.Add("timestamp_utc=$((Get-Date).ToUniversalTime().ToString('o'))")
    $reportLines.Add("git_commit=$gitCommit")
    $reportLines.Add("status=$status")
    $reportLines.Add("")
    $reportLines.Add("output:")
    foreach ($line in $capturedOutput) {
        $reportLines.Add($line)
    }

    Set-Content -Path $reportPath -Value $reportLines -Encoding UTF8
    Write-Host "Baseline report written: $reportPath"
}
