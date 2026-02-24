param(
    [switch]$SkipBuild,
    [switch]$SkipGoCoreBuild,
    [switch]$SkipStopConflictingProcesses,
    [switch]$FailOnWarn,
    [switch]$WriteJsonReport,
    [switch]$RequireAdmin,
    [switch]$AutoElevate,
    [int]$AutoElevateTimeoutSeconds = 900,
    [switch]$RequireWintun,
    [switch]$ReleaseGate,
    [switch]$ShowLatest,
    [switch]$ShowLatestSummaryOnly,
    [int]$LatestMaxAgeMinutes = 0,
    [switch]$LatestRequireNoFail,
    [switch]$LatestFailOnWarn,
    [string[]]$LatestIgnoreWarnChecks = @(),
    [string[]]$LatestRequirePassChecks = @(),
    [switch]$LatestRequireTextJsonConsistent,
    [switch]$LatestRequireSameGeneratedAtUtc,
    [switch]$RefreshLatestOnStale,
    [switch]$RefreshLatestSkipBuild,
    [switch]$RefreshLatestSkipGoCoreBuild,
    [switch]$RunScmStrict,
    [string]$ScmStrictConfiguration = "Release",
    [string]$ScmStrictServiceName = "OpenMeshWinServiceP6",
    [string]$WintunPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$selfScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($selfScriptPath)) {
    $selfScriptPath = $MyInvocation.PSCommandPath
}
if ([string]::IsNullOrWhiteSpace($selfScriptPath)) {
    $selfScriptPath = $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($selfScriptPath)) {
    throw "Cannot resolve current script path."
}
$selfScriptPath = (Resolve-Path -LiteralPath $selfScriptPath).ProviderPath

$reportsDir = Join-Path $scriptRoot "reports"
$latestReportPath = Join-Path $reportsDir "p6-release-preflight-latest.txt"
$latestJsonReportPath = Join-Path $reportsDir "p6-release-preflight-latest.json"
$buildP1Script = Join-Path $scriptRoot "Build-P1-GoCore.ps1"
$solutionPath = Join-Path $repoRoot "openmesh-win\openmesh-win.sln"
$goCoreExePath = Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core\openmesh-win-core.exe"
$serviceProjectPath = Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\OpenMeshWin.Service.csproj"
$registerServiceScriptPath = Join-Path $repoRoot "openmesh-win\installer\Register-OpenMeshWin-Service.ps1"
$unregisterServiceScriptPath = Join-Path $repoRoot "openmesh-win\installer\Unregister-OpenMeshWin-Service.ps1"
$serviceScmStrictScriptPath = Join-Path $repoRoot "openmesh-win\tests\Run-P6-Service-SCM-Strict.ps1"
$wintunPathInput = $WintunPath
$wintunPathResolved = $WintunPath

if (-not [string]::IsNullOrWhiteSpace($WintunPath)) {
    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $WintunPath -ErrorAction Stop).ProviderPath
    }
    catch {
        if (-not [System.IO.Path]::IsPathRooted($WintunPath)) {
            $repoRelative = Join-Path $repoRoot $WintunPath
            if (Test-Path $repoRelative) {
                $resolved = (Resolve-Path -LiteralPath $repoRelative).ProviderPath
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        $wintunPathResolved = $resolved
        $WintunPath = $resolved
    }
}

if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

if ($ShowLatest) {
    $latestTextExists = Test-Path $latestReportPath
    $latestJsonExists = Test-Path $latestJsonReportPath

    if (-not $latestTextExists -and -not $latestJsonExists) {
        throw ("No latest preflight reports found under " + $reportsDir)
    }

    $latestAgeMinutes = -1
    $latestTextLines = @()
    $isStale = $false
    $effectiveFailCount = 0
    $effectiveWarnCount = 0
    $effectivePassCount = 0
    $textSummaryAvailable = $false
    $jsonSummaryAvailable = $false
    $textFailCount = 0
    $textWarnCount = 0
    $textPassCount = 0
    $jsonFailCount = 0
    $jsonWarnCount = 0
    $jsonPassCount = 0
    $textGeneratedAtUtc = ""
    $jsonGeneratedAtUtc = ""
    $textGeneratedAtUtcAvailable = $false
    $jsonGeneratedAtUtcAvailable = $false
    $latestJson = $null

    if ($latestTextExists) {
        $latestInfo = Get-Item -Path $latestReportPath
        $latestAgeMinutes = [int][Math]::Floor(((Get-Date) - $latestInfo.LastWriteTime).TotalMinutes)
        Write-Host ("Latest preflight report: " + $latestReportPath)
        Write-Host ("Latest report age: " + $latestAgeMinutes + " minutes")
        $latestTextLines = @(Get-Content -Path $latestReportPath)
        if (-not $ShowLatestSummaryOnly) {
            $latestTextLines | ForEach-Object { Write-Host $_ }
        }
        $textFailCount = ($latestTextLines | Where-Object { $_ -match '^\[FAIL\]' } | Measure-Object).Count
        $textWarnCount = ($latestTextLines | Where-Object { $_ -match '^\[WARN\]' } | Measure-Object).Count
        $textPassCount = ($latestTextLines | Where-Object { $_ -match '^\[PASS\]' } | Measure-Object).Count
        $textSummaryAvailable = $true
        $effectiveFailCount = $textFailCount
        $effectiveWarnCount = $textWarnCount
        $effectivePassCount = $textPassCount
        Write-Host ("Latest text summary: FAIL=" + $textFailCount + " WARN=" + $textWarnCount + " PASS=" + $textPassCount)
        $generatedAtLine = $latestTextLines | Where-Object { $_ -match '^GeneratedAtUtc:\s*' } | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($generatedAtLine)) {
            $textGeneratedAtUtc = ($generatedAtLine -replace '^GeneratedAtUtc:\s*', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($textGeneratedAtUtc)) {
                $textGeneratedAtUtcAvailable = $true
            }
        }
        $isStale = ($LatestMaxAgeMinutes -gt 0 -and $latestAgeMinutes -gt $LatestMaxAgeMinutes)
    } else {
        Write-Host ("Latest preflight report is missing: " + $latestReportPath)
    }

    if ($isStale -and $RefreshLatestOnStale) {
        Write-Host ("Latest preflight report is stale: age=" + $latestAgeMinutes + "m, allowed<=" + $LatestMaxAgeMinutes + "m. Refreshing latest preflight...")
        $refreshArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $selfScriptPath,
            "-WriteJsonReport",
            "-SkipStopConflictingProcesses"
        )
        if ($RefreshLatestSkipBuild) {
            $refreshArgs += "-SkipBuild"
        }
        if ($RefreshLatestSkipGoCoreBuild) {
            $refreshArgs += "-SkipGoCoreBuild"
        }

        & powershell @refreshArgs
        if ($LASTEXITCODE -ne 0) {
            throw ("RefreshLatestOnStale failed with exit code " + $LASTEXITCODE + ".")
        }

        if (-not (Test-Path $latestReportPath)) {
            throw ("RefreshLatestOnStale completed but latest report is missing: " + $latestReportPath)
        }

        $latestInfo = Get-Item -Path $latestReportPath
        $latestAgeMinutes = [int][Math]::Floor(((Get-Date) - $latestInfo.LastWriteTime).TotalMinutes)
        Write-Host ("Refreshed latest report age: " + $latestAgeMinutes + " minutes")
        $latestTextLines = @(Get-Content -Path $latestReportPath)
        if (-not $ShowLatestSummaryOnly) {
            $latestTextLines | ForEach-Object { Write-Host $_ }
        }
        $textFailCount = ($latestTextLines | Where-Object { $_ -match '^\[FAIL\]' } | Measure-Object).Count
        $textWarnCount = ($latestTextLines | Where-Object { $_ -match '^\[WARN\]' } | Measure-Object).Count
        $textPassCount = ($latestTextLines | Where-Object { $_ -match '^\[PASS\]' } | Measure-Object).Count
        $textSummaryAvailable = $true
        $effectiveFailCount = $textFailCount
        $effectiveWarnCount = $textWarnCount
        $effectivePassCount = $textPassCount
        Write-Host ("Refreshed text summary: FAIL=" + $textFailCount + " WARN=" + $textWarnCount + " PASS=" + $textPassCount)
        $generatedAtLine = $latestTextLines | Where-Object { $_ -match '^GeneratedAtUtc:\s*' } | Select-Object -First 1
        $textGeneratedAtUtc = ""
        $textGeneratedAtUtcAvailable = $false
        if (-not [string]::IsNullOrWhiteSpace($generatedAtLine)) {
            $textGeneratedAtUtc = ($generatedAtLine -replace '^GeneratedAtUtc:\s*', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($textGeneratedAtUtc)) {
                $textGeneratedAtUtcAvailable = $true
            }
        }

        if ($LatestMaxAgeMinutes -gt 0 -and $latestAgeMinutes -gt $LatestMaxAgeMinutes) {
            throw ("Latest preflight report is still stale after refresh: age=" + $latestAgeMinutes + "m, allowed<=" + $LatestMaxAgeMinutes + "m")
        }

        $latestJsonExists = Test-Path $latestJsonReportPath
    } elseif ($isStale) {
        throw ("Latest preflight report is stale: age=" + $latestAgeMinutes + "m, allowed<=" + $LatestMaxAgeMinutes + "m")
    }

    if ($latestJsonExists) {
        try {
            $latestJson = Get-Content -Path $latestJsonReportPath -Raw | ConvertFrom-Json
            if ($null -ne $latestJson -and $null -ne $latestJson.Summary) {
                $jsonFailCount = [int]$latestJson.Summary.Fail
                $jsonWarnCount = [int]$latestJson.Summary.Warn
                $jsonPassCount = [int]$latestJson.Summary.Pass
                $jsonSummaryAvailable = $true
                $effectiveFailCount = $jsonFailCount
                $effectiveWarnCount = $jsonWarnCount
                $effectivePassCount = $jsonPassCount
                if ($null -ne $latestJson.GeneratedAtUtc -and -not [string]::IsNullOrWhiteSpace([string]$latestJson.GeneratedAtUtc)) {
                    $jsonGeneratedAtUtc = [string]$latestJson.GeneratedAtUtc
                    $jsonGeneratedAtUtcAvailable = $true
                }
                Write-Host ("Latest preflight json report: " + $latestJsonReportPath)
                Write-Host ("Latest summary: FAIL=" + $effectiveFailCount + " WARN=" + $effectiveWarnCount + " PASS=" + $effectivePassCount)
            } else {
                Write-Host ("Latest preflight json report exists but summary is unavailable: " + $latestJsonReportPath)
            }
        }
        catch {
            Write-Host ("Latest preflight json report parse failed: " + $latestJsonReportPath)
        }
    } else {
        Write-Host ("Latest preflight json report is missing: " + $latestJsonReportPath)
    }

    if ($LatestIgnoreWarnChecks.Count -gt 0) {
        $ignoreSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($warnCheck in $LatestIgnoreWarnChecks) {
            if (-not [string]::IsNullOrWhiteSpace($warnCheck)) {
                $warnCheckParts = [string]$warnCheck -split '[,;]'
                foreach ($warnCheckPart in $warnCheckParts) {
                    if (-not [string]::IsNullOrWhiteSpace($warnCheckPart)) {
                        [void]$ignoreSet.Add($warnCheckPart.Trim())
                    }
                }
            }
        }

        if ($ignoreSet.Count -eq 0) {
            throw "LatestIgnoreWarnChecks is set but no valid check names were provided."
        }

        $effectiveWarnSource = "none"
        if ($jsonSummaryAvailable -and $null -ne $latestJson -and $null -ne $latestJson.Results) {
            $jsonWarnChecks = @($latestJson.Results | Where-Object { $_.Level -eq "WARN" } | ForEach-Object { [string]$_.Check })
            $jsonIgnoredWarnCount = ($jsonWarnChecks | Where-Object { $ignoreSet.Contains($_) } | Measure-Object).Count
            $jsonEffectiveWarnCount = $jsonWarnCount - $jsonIgnoredWarnCount
            if ($jsonEffectiveWarnCount -lt 0) { $jsonEffectiveWarnCount = 0 }
            $effectiveWarnCount = $jsonEffectiveWarnCount
            $effectiveWarnSource = "json-results"
        } elseif ($textSummaryAvailable) {
            $textWarnChecks = @(
                $latestTextLines |
                Where-Object { $_ -match '^\[WARN\]\s+' } |
                ForEach-Object {
                    if ($_ -match '^\[WARN\]\s+(.+?)\s+-') { $matches[1] } else { "" }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { [string]$_.Trim() }
            )
            $textIgnoredWarnCount = ($textWarnChecks | Where-Object { $ignoreSet.Contains($_) } | Measure-Object).Count
            $textEffectiveWarnCount = $textWarnCount - $textIgnoredWarnCount
            if ($textEffectiveWarnCount -lt 0) { $textEffectiveWarnCount = 0 }
            $effectiveWarnCount = $textEffectiveWarnCount
            $effectiveWarnSource = "text-lines"
        } else {
            throw "Latest warn summary is unavailable, cannot apply LatestIgnoreWarnChecks."
        }

        $ignoreListDisplay = [string]::Join(", ", @($ignoreSet))
        Write-Host ("Latest warn ignore checks: " + $ignoreListDisplay + "; effective WARN=" + $effectiveWarnCount + " (source=" + $effectiveWarnSource + ")")
    }

    if ($LatestRequirePassChecks.Count -gt 0) {
        $requiredPassSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($requiredCheck in $LatestRequirePassChecks) {
            if (-not [string]::IsNullOrWhiteSpace($requiredCheck)) {
                $requiredCheckParts = [string]$requiredCheck -split '[,;]'
                foreach ($requiredCheckPart in $requiredCheckParts) {
                    if (-not [string]::IsNullOrWhiteSpace($requiredCheckPart)) {
                        [void]$requiredPassSet.Add($requiredCheckPart.Trim())
                    }
                }
            }
        }

        if ($requiredPassSet.Count -eq 0) {
            throw "LatestRequirePassChecks is set but no valid check names were provided."
        }

        $requiredPassSource = "none"
        $failedRequiredPassChecks = New-Object System.Collections.Generic.List[string]
        $resultMap = @{}

        if ($jsonSummaryAvailable -and $null -ne $latestJson -and $null -ne $latestJson.Results) {
            foreach ($result in $latestJson.Results) {
                if ($null -ne $result -and $null -ne $result.Check) {
                    $checkName = [string]$result.Check
                    if (-not [string]::IsNullOrWhiteSpace($checkName)) {
                        $resultMap[$checkName.Trim()] = [string]$result.Level
                    }
                }
            }
            $requiredPassSource = "json-results"
        } elseif ($textSummaryAvailable) {
            foreach ($line in $latestTextLines) {
                if ($line -match '^\[(PASS|WARN|FAIL)\]\s+(.+?)\s+-') {
                    $level = [string]$matches[1]
                    $checkName = [string]$matches[2]
                    if (-not [string]::IsNullOrWhiteSpace($checkName)) {
                        $resultMap[$checkName.Trim()] = $level
                    }
                }
            }
            $requiredPassSource = "text-lines"
        } else {
            throw "Latest results are unavailable, cannot apply LatestRequirePassChecks."
        }

        foreach ($requiredCheckName in $requiredPassSet) {
            if (-not $resultMap.ContainsKey($requiredCheckName)) {
                $failedRequiredPassChecks.Add(($requiredCheckName + "=missing"))
                continue
            }
            $requiredCheckLevel = [string]$resultMap[$requiredCheckName]
            if (-not $requiredCheckLevel.Equals("PASS", [System.StringComparison]::OrdinalIgnoreCase)) {
                $failedRequiredPassChecks.Add(($requiredCheckName + "=" + $requiredCheckLevel))
            }
        }

        if ($failedRequiredPassChecks.Count -gt 0) {
            throw ("Latest required PASS checks failed (" + $requiredPassSource + "): " + [string]::Join(", ", $failedRequiredPassChecks.ToArray()))
        }

        $requiredPassDisplay = [string]::Join(", ", @($requiredPassSet))
        Write-Host ("Latest required PASS checks satisfied: " + $requiredPassDisplay + " (source=" + $requiredPassSource + ")")
    }

    if ($LatestRequireTextJsonConsistent) {
        if (-not $textSummaryAvailable) {
            throw "Latest text summary is unavailable, cannot verify consistency."
        }
        if (-not $jsonSummaryAvailable) {
            throw "Latest json summary is unavailable, cannot verify consistency."
        }
        if ($textFailCount -ne $jsonFailCount -or $textWarnCount -ne $jsonWarnCount -or $textPassCount -ne $jsonPassCount) {
            throw ("Latest text/json summary mismatch: text(F=" + $textFailCount + ",W=" + $textWarnCount + ",P=" + $textPassCount + ") vs json(F=" + $jsonFailCount + ",W=" + $jsonWarnCount + ",P=" + $jsonPassCount + ").")
        }
    }

    if ($LatestRequireSameGeneratedAtUtc) {
        if (-not $textGeneratedAtUtcAvailable) {
            throw "Latest text report GeneratedAtUtc is unavailable, cannot verify same-run consistency."
        }
        if (-not $jsonGeneratedAtUtcAvailable) {
            throw "Latest json report GeneratedAtUtc is unavailable, cannot verify same-run consistency."
        }
        $textGeneratedAt = $null
        $jsonGeneratedAt = $null
        try {
            $textGeneratedAt = [datetimeoffset]$textGeneratedAtUtc
        }
        catch {
            throw ("Latest text report GeneratedAtUtc parse failed: " + $textGeneratedAtUtc)
        }
        try {
            $jsonGeneratedAt = [datetimeoffset]$jsonGeneratedAtUtc
        }
        catch {
            throw ("Latest json report GeneratedAtUtc parse failed: " + $jsonGeneratedAtUtc)
        }
        $deltaSeconds = [Math]::Abs(($textGeneratedAt.ToUniversalTime() - $jsonGeneratedAt.ToUniversalTime()).TotalSeconds)
        if ($deltaSeconds -gt 1.0) {
            throw ("Latest text/json GeneratedAtUtc mismatch: text=" + $textGeneratedAtUtc + ", json=" + $jsonGeneratedAtUtc + ", deltaSeconds=" + [Math]::Round($deltaSeconds, 3))
        }
    }

    if ($LatestRequireNoFail -and $effectiveFailCount -gt 0) {
        throw ("Latest summary gate failed: FAIL=" + $effectiveFailCount + ".")
    }
    if ($LatestFailOnWarn -and $effectiveWarnCount -gt 0) {
        throw ("Latest summary gate failed: WARN=" + $effectiveWarnCount + ".")
    }
    exit 0
}

$results = New-Object System.Collections.Generic.List[psobject]

if ($ReleaseGate) {
    # One-shot release gate: strict + admin + wintun + JSON artifact.
    $FailOnWarn = $true
    $WriteJsonReport = $true
    $RequireAdmin = $true
    $RequireWintun = $true
}

if ($AutoElevateTimeoutSeconds -lt 0) {
    throw "AutoElevateTimeoutSeconds must be >= 0."
}

if ($LatestMaxAgeMinutes -lt 0) {
    throw "LatestMaxAgeMinutes must be >= 0."
}

if ($ShowLatestSummaryOnly -and -not $ShowLatest) {
    throw "ShowLatestSummaryOnly requires -ShowLatest."
}

if (($LatestRequireNoFail -or $LatestFailOnWarn) -and -not $ShowLatest) {
    throw "LatestRequireNoFail/LatestFailOnWarn require -ShowLatest."
}

if ($LatestIgnoreWarnChecks.Count -gt 0 -and -not $ShowLatest) {
    throw "LatestIgnoreWarnChecks requires -ShowLatest."
}

if ($LatestRequirePassChecks.Count -gt 0 -and -not $ShowLatest) {
    throw "LatestRequirePassChecks requires -ShowLatest."
}

if ($LatestRequireTextJsonConsistent -and -not $ShowLatest) {
    throw "LatestRequireTextJsonConsistent requires -ShowLatest."
}

if ($LatestRequireSameGeneratedAtUtc -and -not $ShowLatest) {
    throw "LatestRequireSameGeneratedAtUtc requires -ShowLatest."
}

if ($RefreshLatestOnStale -and -not $ShowLatest) {
    throw "RefreshLatestOnStale requires -ShowLatest."
}

if ($RefreshLatestOnStale -and $LatestMaxAgeMinutes -le 0) {
    throw "RefreshLatestOnStale requires -LatestMaxAgeMinutes > 0."
}

if (($RefreshLatestSkipBuild -or $RefreshLatestSkipGoCoreBuild) -and -not $RefreshLatestOnStale) {
    throw "RefreshLatestSkipBuild/RefreshLatestSkipGoCoreBuild require -RefreshLatestOnStale."
}

function Add-Result([string]$level, [string]$check, [string]$detail) {
    $results.Add([pscustomobject]@{
            Level = $level
            Check = $check
            Detail = $detail
        })
}

function Get-LatestPreflightReportPath {
    if (-not (Test-Path $reportsDir)) {
        return $null
    }
    $item = Get-ChildItem -Path $reportsDir -Filter "p6-release-preflight-*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $item) {
        return $null
    }
    return $item.FullName
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
        if ($name -eq "openmeshwin.service.exe") {
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

function Resolve-ServiceBinaryPath {
    $candidates = @(
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Debug\net10.0-windows\OpenMeshWin.Service.exe"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Debug\net10.0-windows\OpenMeshWin.Service.dll"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Release\net10.0-windows\OpenMeshWin.Service.exe"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Release\net10.0-windows\OpenMeshWin.Service.dll"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Debug\net10.0\OpenMeshWin.Service.exe"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Debug\net10.0\OpenMeshWin.Service.dll"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Release\net10.0\OpenMeshWin.Service.exe"),
        (Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\bin\Release\net10.0\OpenMeshWin.Service.dll")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Resolve-GoExePath {
    $envGoExe = $env:OPENMESH_GO_EXE
    if (-not [string]::IsNullOrWhiteSpace($envGoExe) -and (Test-Path $envGoExe)) {
        return (Resolve-Path $envGoExe).Path
    }

    $cmd = Get-Command go -ErrorAction SilentlyContinue
    if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source) -and (Test-Path $cmd.Source)) {
        return (Resolve-Path $cmd.Source).Path
    }

    $candidates = @(
        (Join-Path $repoRoot ".tools\go\bin\go.exe"),
        "C:\Program Files\Go\bin\go.exe",
        "C:\Program Files (x86)\Go\bin\go.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Go\bin\go.exe"),
        (Join-Path $env:USERPROFILE "scoop\apps\go\current\bin\go.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Resolve-SignToolPath {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source) -and (Test-Path $cmd.Source)) {
        return (Resolve-Path $cmd.Source).Path
    }
    $candidates = @(
        "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ElevationArgs {
    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add("-NoProfile")
    $argsList.Add("-ExecutionPolicy")
    $argsList.Add("Bypass")
    $argsList.Add("-File")
    $argsList.Add($selfScriptPath)

    if ($SkipBuild) { $argsList.Add("-SkipBuild") }
    if ($SkipGoCoreBuild) { $argsList.Add("-SkipGoCoreBuild") }
    if ($SkipStopConflictingProcesses) { $argsList.Add("-SkipStopConflictingProcesses") }
    if ($FailOnWarn) { $argsList.Add("-FailOnWarn") }
    if ($WriteJsonReport) { $argsList.Add("-WriteJsonReport") }
    if ($RequireAdmin) { $argsList.Add("-RequireAdmin") }
    if ($AutoElevateTimeoutSeconds -ne 900) {
        $argsList.Add("-AutoElevateTimeoutSeconds")
        $argsList.Add([string]$AutoElevateTimeoutSeconds)
    }
    if ($RequireWintun) { $argsList.Add("-RequireWintun") }
    if ($ReleaseGate) { $argsList.Add("-ReleaseGate") }
    if ($ShowLatest) { $argsList.Add("-ShowLatest") }
    if ($ShowLatestSummaryOnly) { $argsList.Add("-ShowLatestSummaryOnly") }
    if ($LatestRequireNoFail) { $argsList.Add("-LatestRequireNoFail") }
    if ($LatestFailOnWarn) { $argsList.Add("-LatestFailOnWarn") }
    if ($LatestIgnoreWarnChecks.Count -gt 0) {
        $argsList.Add("-LatestIgnoreWarnChecks")
        foreach ($warnCheck in $LatestIgnoreWarnChecks) {
            if (-not [string]::IsNullOrWhiteSpace($warnCheck)) {
                $argsList.Add($warnCheck)
            }
        }
    }
    if ($LatestRequirePassChecks.Count -gt 0) {
        $argsList.Add("-LatestRequirePassChecks")
        foreach ($requiredCheck in $LatestRequirePassChecks) {
            if (-not [string]::IsNullOrWhiteSpace($requiredCheck)) {
                $argsList.Add($requiredCheck)
            }
        }
    }
    if ($LatestRequireTextJsonConsistent) { $argsList.Add("-LatestRequireTextJsonConsistent") }
    if ($LatestRequireSameGeneratedAtUtc) { $argsList.Add("-LatestRequireSameGeneratedAtUtc") }
    if ($LatestMaxAgeMinutes -ne 0) {
        $argsList.Add("-LatestMaxAgeMinutes")
        $argsList.Add([string]$LatestMaxAgeMinutes)
    }
    if ($RefreshLatestOnStale) { $argsList.Add("-RefreshLatestOnStale") }
    if ($RefreshLatestSkipBuild) { $argsList.Add("-RefreshLatestSkipBuild") }
    if ($RefreshLatestSkipGoCoreBuild) { $argsList.Add("-RefreshLatestSkipGoCoreBuild") }
    if ($RunScmStrict) { $argsList.Add("-RunScmStrict") }
    if (-not [string]::IsNullOrWhiteSpace($ScmStrictConfiguration)) {
        $argsList.Add("-ScmStrictConfiguration")
        $argsList.Add($ScmStrictConfiguration)
    }
    if (-not [string]::IsNullOrWhiteSpace($ScmStrictServiceName)) {
        $argsList.Add("-ScmStrictServiceName")
        $argsList.Add($ScmStrictServiceName)
    }
    if (-not [string]::IsNullOrWhiteSpace($WintunPath)) {
        $argsList.Add("-WintunPath")
        $argsList.Add($WintunPath)
    }

    return $argsList.ToArray()
}

if ($AutoElevate -and -not (Test-IsAdministrator)) {
    $beforeReport = Get-LatestPreflightReportPath
    Write-Host "Current shell is not elevated. Relaunching with UAC elevation..."
    try {
        $elevated = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList (Get-ElevationArgs) -WorkingDirectory $repoRoot -PassThru
    }
    catch {
        throw ("UAC elevation was cancelled or failed: " + $_.Exception.Message)
    }
    if ($null -eq $elevated) {
        throw "Failed to start elevated preflight process."
    }
    Write-Host ("Elevated preflight process started. pid=" + $elevated.Id + ", timeoutSeconds=" + $AutoElevateTimeoutSeconds)

    if ($AutoElevateTimeoutSeconds -eq 0) {
        $elevated.WaitForExit()
    } else {
        $deadline = (Get-Date).AddSeconds($AutoElevateTimeoutSeconds)
        $nextHeartbeat = (Get-Date).AddSeconds(15)
        while ($true) {
            $elevated.Refresh()
            if ($elevated.HasExited) {
                break
            }
            $now = Get-Date
            if ($now -ge $deadline) {
                try {
                    Stop-Process -Id $elevated.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
                throw ("Elevated preflight timed out after " + $AutoElevateTimeoutSeconds + " seconds. Open an Administrator PowerShell and run preflight directly.")
            }
            if ($now -ge $nextHeartbeat) {
                $remainSeconds = [int][Math]::Ceiling(($deadline - $now).TotalSeconds)
                Write-Host ("Waiting for elevated preflight to complete... remaining " + $remainSeconds + "s")
                $nextHeartbeat = $now.AddSeconds(15)
            }
            Start-Sleep -Seconds 2
        }
    }

    if ($elevated.ExitCode -ne 0) {
        $afterReport = Get-LatestPreflightReportPath
        if ($null -ne $afterReport -and $afterReport -ne $beforeReport) {
            Write-Host ("Latest preflight report: " + $afterReport)
            Get-Content -Path $afterReport | ForEach-Object { Write-Host $_ }
        }
        throw ("Elevated preflight failed with exit code " + $elevated.ExitCode + ".")
    }

    $afterReport = Get-LatestPreflightReportPath
    if ($null -ne $afterReport -and $afterReport -ne $beforeReport) {
        $reportLines = Get-Content -Path $afterReport
        $failCount = ($reportLines | Where-Object { $_ -match '^\[FAIL\]' } | Measure-Object).Count
        $warnCount = ($reportLines | Where-Object { $_ -match '^\[WARN\]' } | Measure-Object).Count
        $passCount = ($reportLines | Where-Object { $_ -match '^\[PASS\]' } | Measure-Object).Count
        Write-Host ("Elevated preflight completed successfully. Report: " + $afterReport)
        Write-Host ("Elevated preflight summary: FAIL=" + $failCount + " WARN=" + $warnCount + " PASS=" + $passCount)
    } else {
        Write-Host "Elevated preflight completed successfully."
    }
    exit 0
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses
}

$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $dotnetCmd) {
    Add-Result "FAIL" "dotnet" "dotnet CLI not found in PATH."
} else {
    Add-Result "PASS" "dotnet" ("dotnet found: " + [string]$dotnetCmd.Source)
}

$goExe = Resolve-GoExePath
if ($null -eq $goExe) {
    Add-Result "FAIL" "go" "Go toolchain not found."
} else {
    Add-Result "PASS" "go" ("go found: " + $goExe)
}

if (-not $SkipBuild -and (Test-Path $solutionPath)) {
    & dotnet build $solutionPath -v minimal | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Add-Result "PASS" "build_winforms" "dotnet build openmesh-win.sln succeeded."
    } else {
        Add-Result "FAIL" "build_winforms" ("dotnet build failed with exit code " + $LASTEXITCODE)
    }
} elseif ($SkipBuild) {
    Add-Result "WARN" "build_winforms" "Skipped by -SkipBuild."
}

if (-not $SkipGoCoreBuild) {
    $goExeArg = if ($null -eq $goExe) { "" } else { [string]$goExe }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildP1Script -GoExePath $goExeArg
    if ($LASTEXITCODE -eq 0) {
        Add-Result "PASS" "build_go_core" "Build-P1-GoCore.ps1 succeeded."
    } else {
        Add-Result "FAIL" "build_go_core" ("Build-P1-GoCore.ps1 failed with exit code " + $LASTEXITCODE)
    }
} else {
    Add-Result "WARN" "build_go_core" "Skipped by -SkipGoCoreBuild."
}

if (Test-Path $goCoreExePath) {
    Add-Result "PASS" "go_core_binary" ("openmesh-win-core.exe present: " + $goCoreExePath)
} else {
    Add-Result "FAIL" "go_core_binary" ("missing openmesh-win-core.exe: " + $goCoreExePath)
}

if (Test-Path $serviceProjectPath) {
    Add-Result "PASS" "service_project" ("openmesh-win-service project present: " + $serviceProjectPath)
} else {
    Add-Result "FAIL" "service_project" ("missing service project: " + $serviceProjectPath)
}

$serviceBinary = Resolve-ServiceBinaryPath
if ($null -ne $serviceBinary) {
    Add-Result "PASS" "service_binary" ("OpenMeshWin.Service binary present: " + $serviceBinary)
} else {
    Add-Result "FAIL" "service_binary" "OpenMeshWin.Service binary missing in bin/Debug or bin/Release output."
}

if (Test-Path $registerServiceScriptPath) {
    Add-Result "PASS" "service_register_script" ("service register script present: " + $registerServiceScriptPath)
} else {
    Add-Result "FAIL" "service_register_script" ("missing service register script: " + $registerServiceScriptPath)
}

if (Test-Path $unregisterServiceScriptPath) {
    Add-Result "PASS" "service_unregister_script" ("service unregister script present: " + $unregisterServiceScriptPath)
} else {
    Add-Result "FAIL" "service_unregister_script" ("missing service unregister script: " + $unregisterServiceScriptPath)
}

if (Test-Path $serviceScmStrictScriptPath) {
    Add-Result "PASS" "service_scm_strict_script" ("service SCM strict script present: " + $serviceScmStrictScriptPath)
} else {
    Add-Result "FAIL" "service_scm_strict_script" ("missing service SCM strict script: " + $serviceScmStrictScriptPath)
}

if ($RunScmStrict) {
    if (Test-Path $serviceScmStrictScriptPath) {
        $scmArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $serviceScmStrictScriptPath,
            "-Configuration", $ScmStrictConfiguration,
            "-ServiceName", $ScmStrictServiceName
        )
        if ($SkipStopConflictingProcesses) {
            $scmArgs += "-SkipStopConflictingProcesses"
        }

        & powershell @scmArgs | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Add-Result "PASS" "service_scm_strict_run" ("Run-P6-Service-SCM-Strict.ps1 succeeded. service=" + $ScmStrictServiceName)
        } else {
            Add-Result "FAIL" "service_scm_strict_run" ("Run-P6-Service-SCM-Strict.ps1 failed with exit code " + $LASTEXITCODE + ". service=" + $ScmStrictServiceName)
        }
    } else {
        Add-Result "FAIL" "service_scm_strict_run" "Cannot run strict SCM check because script is missing."
    }
}

$scCommand = Get-Command sc.exe -ErrorAction SilentlyContinue
if ($null -ne $scCommand -and -not [string]::IsNullOrWhiteSpace($scCommand.Source)) {
    Add-Result "PASS" "scm_tool" ("sc.exe found: " + [string]$scCommand.Source)
} else {
    Add-Result "WARN" "scm_tool" "sc.exe not found in PATH."
}

if (Test-IsAdministrator) {
    Add-Result "PASS" "admin_privilege" "Current shell is elevated for SCM actions."
} elseif ($RequireAdmin) {
    Add-Result "FAIL" "admin_privilege" "Current shell is not elevated but -RequireAdmin was set."
} else {
    Add-Result "WARN" "admin_privilege" "Current shell is not elevated; SCM lifecycle checks need admin shell."
}

$wintunCandidates = New-Object System.Collections.Generic.List[string]
function Add-WintunCandidate([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }
    if (-not $wintunCandidates.Contains($path)) {
        $wintunCandidates.Add($path)
    }
}

$envWintunPath = [Environment]::GetEnvironmentVariable("OPENMESH_WIN_WINTUN_DLL")
$explicitWintunProvided = -not [string]::IsNullOrWhiteSpace($wintunPathInput)
$explicitWintunExists = $false

if ($explicitWintunProvided) {
    $explicitWintunExists = Test-Path $WintunPath
    if ($explicitWintunExists) {
        Add-WintunCandidate $WintunPath
    } elseif ($RequireWintun) {
        Add-Result "FAIL" "wintun_path" ("WintunPath not found: input=" + $wintunPathInput + ", resolved=" + $wintunPathResolved)
    } else {
        Add-Result "WARN" "wintun_path" ("WintunPath not found: input=" + $wintunPathInput + ", resolved=" + $wintunPathResolved)
    }
}
if (-not [string]::IsNullOrWhiteSpace($envWintunPath)) {
    Add-WintunCandidate $envWintunPath
}

Add-WintunCandidate (Join-Path $repoRoot "openmesh-win\deps\wintun.dll")
Add-WintunCandidate (Join-Path $repoRoot "openmesh-win\bin\Debug\net10.0-windows\wintun.dll")
Add-WintunCandidate (Join-Path ${env:ProgramFiles} "WireGuard\wintun.dll")
Add-WintunCandidate (Join-Path ${env:ProgramFiles(x86)} "WireGuard\wintun.dll")
Add-WintunCandidate "C:\Windows\System32\wintun.dll"
Add-WintunCandidate "C:\Windows\SysWOW64\wintun.dll"

$wintunFound = $wintunCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -ne $wintunFound) {
    Add-Result "PASS" "wintun" ("wintun.dll found: " + $wintunFound)
} else {
    $wintunDetail = "wintun.dll not found. searched: " + ([string]::Join("; ", $wintunCandidates.ToArray()))
    if ($RequireWintun) {
        Add-Result "FAIL" "wintun" $wintunDetail
    } else {
        Add-Result "WARN" "wintun" $wintunDetail
    }
}

$wixCommand = Get-Command wix -ErrorAction SilentlyContinue
$candleCommand = Get-Command candle.exe -ErrorAction SilentlyContinue
$lightCommand = Get-Command light.exe -ErrorAction SilentlyContinue
if ($null -ne $wixCommand) {
    Add-Result "PASS" "wix" ("WiX v4 detected: " + [string]$wixCommand.Source)
} elseif ($null -ne $candleCommand -and $null -ne $lightCommand) {
    Add-Result "PASS" "wix" ("WiX v3 detected: candle=" + [string]$candleCommand.Source + ", light=" + [string]$lightCommand.Source)
} else {
    Add-Result "WARN" "wix" "WiX toolset not found (MSI pipeline not ready)."
}

$signTool = Resolve-SignToolPath
if ($null -eq $signTool) {
    Add-Result "WARN" "signtool" "signtool.exe not found."
} else {
    Add-Result "PASS" "signtool" ("signtool found: " + $signTool)
}

$codeSigningOid = "1.3.6.1.5.5.7.3.3"
$now = Get-Date
$certs = @()
try {
    $certs += Get-ChildItem -Path Cert:\CurrentUser\My -ErrorAction SilentlyContinue
    $certs += Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue
}
catch {
}
$validCodeSigningCert = $certs | Where-Object {
    $ekuMatched = $false
    foreach ($eku in $_.EnhancedKeyUsageList) {
        $ekuOidValue = ""
        $ekuDisplayValue = ""
        if ($null -ne $eku) {
            if ($null -ne $eku.PSObject.Properties["Oid"] -and $null -ne $eku.Oid -and $null -ne $eku.Oid.PSObject.Properties["Value"]) {
                $ekuOidValue = [string]$eku.Oid.Value
            }
            if ($null -ne $eku.PSObject.Properties["Value"]) {
                $ekuDisplayValue = [string]$eku.Value
            } elseif ([string]::IsNullOrWhiteSpace($ekuDisplayValue)) {
                $ekuDisplayValue = [string]$eku
            }
        }
        if (
            $ekuOidValue -eq $codeSigningOid -or
            $ekuDisplayValue -like "*Code Signing*" -or
            $ekuDisplayValue -like ("*" + $codeSigningOid + "*")
        ) {
            $ekuMatched = $true
            break
        }
    }
    $_.HasPrivateKey -and
    $_.NotAfter -gt $now -and
    $ekuMatched
} | Select-Object -First 1

if ($null -ne $validCodeSigningCert) {
    Add-Result "PASS" "codesign_cert" ("code-sign cert found: " + $validCodeSigningCert.Subject)
} else {
    Add-Result "WARN" "codesign_cert" "No valid code-sign certificate with private key found."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p6-release-preflight-" + $timestamp + ".txt")
$jsonReportPath = Join-Path $reportsDir ("p6-release-preflight-" + $timestamp + ".json")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P6 Release Preflight")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("")
foreach ($r in $results) {
    $lines.Add("[" + $r.Level + "] " + $r.Check + " - " + $r.Detail)
}
$lines | Set-Content -Path $reportPath -Encoding UTF8
Copy-Item -Path $reportPath -Destination $latestReportPath -Force

$failCount = ($results | Where-Object { $_.Level -eq "FAIL" } | Measure-Object).Count
$warnCount = ($results | Where-Object { $_.Level -eq "WARN" } | Measure-Object).Count
$passCount = ($results | Where-Object { $_.Level -eq "PASS" } | Measure-Object).Count

if ($WriteJsonReport) {
    $jsonReport = [pscustomobject]@{
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        RepoRoot = $repoRoot
        Parameters = [pscustomobject]@{
            SkipBuild = [bool]$SkipBuild
            SkipGoCoreBuild = [bool]$SkipGoCoreBuild
            SkipStopConflictingProcesses = [bool]$SkipStopConflictingProcesses
            ReleaseGate = [bool]$ReleaseGate
            ShowLatest = [bool]$ShowLatest
            ShowLatestSummaryOnly = [bool]$ShowLatestSummaryOnly
            LatestMaxAgeMinutes = [int]$LatestMaxAgeMinutes
            LatestRequireNoFail = [bool]$LatestRequireNoFail
            LatestFailOnWarn = [bool]$LatestFailOnWarn
            LatestIgnoreWarnChecks = $LatestIgnoreWarnChecks
            LatestRequirePassChecks = $LatestRequirePassChecks
            LatestRequireTextJsonConsistent = [bool]$LatestRequireTextJsonConsistent
            LatestRequireSameGeneratedAtUtc = [bool]$LatestRequireSameGeneratedAtUtc
            RefreshLatestOnStale = [bool]$RefreshLatestOnStale
            RefreshLatestSkipBuild = [bool]$RefreshLatestSkipBuild
            RefreshLatestSkipGoCoreBuild = [bool]$RefreshLatestSkipGoCoreBuild
            RunScmStrict = [bool]$RunScmStrict
            ScmStrictConfiguration = $ScmStrictConfiguration
            ScmStrictServiceName = $ScmStrictServiceName
            FailOnWarn = [bool]$FailOnWarn
            RequireAdmin = [bool]$RequireAdmin
            AutoElevate = [bool]$AutoElevate
            AutoElevateTimeoutSeconds = [int]$AutoElevateTimeoutSeconds
            RequireWintun = [bool]$RequireWintun
            WintunPath = $WintunPath
            WintunPathInput = $wintunPathInput
            WintunPathResolved = $wintunPathResolved
        }
        Summary = [pscustomobject]@{
            Fail = [int]$failCount
            Warn = [int]$warnCount
            Pass = [int]$passCount
        }
        Results = $results
    }

    $jsonReport | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonReportPath -Encoding UTF8
    Copy-Item -Path $jsonReportPath -Destination $latestJsonReportPath -Force
}

Write-Host ("P6 preflight report written: " + $reportPath)
Write-Host ("P6 preflight latest report: " + $latestReportPath)
Write-Host ("Summary: FAIL=" + $failCount + " WARN=" + $warnCount)
if ($WriteJsonReport) {
    Write-Host ("P6 preflight json report written: " + $jsonReportPath)
    Write-Host ("P6 preflight latest json report: " + $latestJsonReportPath)
}

if ($failCount -gt 0) {
    throw "P6 release preflight failed."
}

if ($FailOnWarn -and $warnCount -gt 0) {
    throw ("P6 release preflight strict mode failed: WARN=" + $warnCount)
}

Write-Host "P6 release preflight checks passed."

