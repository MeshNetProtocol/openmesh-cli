param(
    [string]$PreflightScriptPath = "",
    [switch]$ShowDetails
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($PreflightScriptPath)) {
    $PreflightScriptPath = Join-Path $scriptRoot "Run-P6-Release-Preflight.ps1"
}
$PreflightScriptPath = (Resolve-Path -LiteralPath $PreflightScriptPath).ProviderPath

$reportsDir = Join-Path $scriptRoot "reports"
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

$cases = @(
    [pscustomobject]@{
        Id = "show_latest_basic"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly")
    },
    [pscustomobject]@{
        Id = "warn_allowlist_pass"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestAllowedWarnChecks", "build_winforms,build_go_core,admin_privilege")
    },
    [pscustomobject]@{
        Id = "warn_forbidden_fail"
        ExpectExit = 1
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestForbiddenWarnChecks", "build_winforms")
    },
    [pscustomobject]@{
        Id = "require_checks_present_pass"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestRequireChecksPresent", "dotnet,go")
    },
    [pscustomobject]@{
        Id = "require_checks_present_fail"
        ExpectExit = 1
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestRequireChecksPresent", "not_a_real_check")
    },
    [pscustomobject]@{
        Id = "require_checks_absent_pass"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestRequireChecksAbsent", "not_a_real_check")
    },
    [pscustomobject]@{
        Id = "require_checks_absent_fail"
        ExpectExit = 1
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestRequireChecksAbsent", "dotnet")
    },
    [pscustomobject]@{
        Id = "require_levels_pass"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestRequireCheckLevels", "dotnet=PASS,go=PASS,admin_privilege=WARN")
    },
    [pscustomobject]@{
        Id = "expected_counts_pass"
        ExpectExit = 0
        Args = @("-ShowLatest", "-ShowLatestSummaryOnly", "-LatestExpectedFailCount", "0", "-LatestExpectedWarnCount", "3", "-LatestExpectedPassCount", "13")
    }
)

$results = New-Object System.Collections.Generic.List[psobject]

foreach ($case in $cases) {
    $invokeArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PreflightScriptPath
    ) + $case.Args

    $stdoutPath = Join-Path $reportsDir ("tmp-" + $case.Id + "-" + [Guid]::NewGuid().ToString("N") + ".stdout.txt")
    $stderrPath = Join-Path $reportsDir ("tmp-" + $case.Id + "-" + [Guid]::NewGuid().ToString("N") + ".stderr.txt")
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $invokeArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $actualExit = [int]$proc.ExitCode
    $output = New-Object System.Collections.Generic.List[string]
    if (Test-Path $stdoutPath) {
        (Get-Content -Path $stdoutPath) | ForEach-Object { [void]$output.Add([string]$_) }
        Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $stderrPath) {
        (Get-Content -Path $stderrPath) | ForEach-Object { [void]$output.Add([string]$_) }
        Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
    }
    $passed = ($actualExit -eq $case.ExpectExit)

    $results.Add([pscustomobject]@{
            Id = $case.Id
            ExpectExit = [int]$case.ExpectExit
            ActualExit = [int]$actualExit
            Passed = [bool]$passed
            Args = $case.Args
            Output = (@($output) | ForEach-Object { [string]$_ })
        })

    if ($ShowDetails) {
        Write-Host ("[" + ($(if ($passed) { "PASS" } else { "FAIL" })) + "] " + $case.Id + " expectExit=" + $case.ExpectExit + " actualExit=" + $actualExit)
        (@($output) | ForEach-Object { [string]$_ }) | ForEach-Object { Write-Host ("  " + $_) }
    }
}

$failCount = ($results | Where-Object { -not $_.Passed } | Measure-Object).Count
$passCount = ($results | Where-Object { $_.Passed } | Measure-Object).Count

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p6-release-preflight-latest-gates-smoke-" + $timestamp + ".txt")
$jsonReportPath = Join-Path $reportsDir ("p6-release-preflight-latest-gates-smoke-" + $timestamp + ".json")

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P6 Release Preflight Latest Gates Smoke")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("PreflightScriptPath: " + $PreflightScriptPath)
$lines.Add("")
foreach ($r in $results) {
    $level = if ($r.Passed) { "PASS" } else { "FAIL" }
    $lines.Add("[" + $level + "] " + $r.Id + " expectExit=" + $r.ExpectExit + " actualExit=" + $r.ActualExit)
}
$lines.Add("")
$lines.Add("Summary: FAIL=" + $failCount + " PASS=" + $passCount)
$lines | Set-Content -Path $reportPath -Encoding UTF8

$jsonReport = [pscustomobject]@{
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    RepoRoot = $repoRoot
    PreflightScriptPath = $PreflightScriptPath
    Summary = [pscustomobject]@{
        Fail = [int]$failCount
        Pass = [int]$passCount
    }
    Results = $results
}
$jsonReport | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReportPath -Encoding UTF8

Write-Host ("P6 latest gates smoke report written: " + $reportPath)
Write-Host ("P6 latest gates smoke json report written: " + $jsonReportPath)
Write-Host ("Summary: FAIL=" + $failCount + " PASS=" + $passCount)

if ($failCount -gt 0) {
    throw "P6 latest gates smoke failed."
}

Write-Host "P6 latest gates smoke passed."
