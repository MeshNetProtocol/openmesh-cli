param(
    [switch]$SkipBuild,
    [switch]$SkipGoCoreBuild,
    [switch]$SkipStopConflictingProcesses,
    [switch]$FailOnWarn,
    [switch]$WriteJsonReport,
    [switch]$RequireWintun,
    [string]$WintunPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$reportsDir = Join-Path $scriptRoot "reports"
$buildP1Script = Join-Path $scriptRoot "Build-P1-GoCore.ps1"
$solutionPath = Join-Path $repoRoot "openmesh-win\openmesh-win.sln"
$goCoreExePath = Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core\openmesh-win-core.exe"
$serviceProjectPath = Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\OpenMeshWin.Service.csproj"
$registerServiceScriptPath = Join-Path $repoRoot "openmesh-win\installer\Register-OpenMeshWin-Service.ps1"
$unregisterServiceScriptPath = Join-Path $repoRoot "openmesh-win\installer\Unregister-OpenMeshWin-Service.ps1"
$serviceScmStrictScriptPath = Join-Path $repoRoot "openmesh-win\tests\Run-P6-Service-SCM-Strict.ps1"

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

$scCommand = Get-Command sc.exe -ErrorAction SilentlyContinue
if ($null -ne $scCommand -and -not [string]::IsNullOrWhiteSpace($scCommand.Source)) {
    Add-Result "PASS" "scm_tool" ("sc.exe found: " + [string]$scCommand.Source)
} else {
    Add-Result "WARN" "scm_tool" "sc.exe not found in PATH."
}

if (Test-IsAdministrator) {
    Add-Result "PASS" "admin_privilege" "Current shell is elevated for SCM actions."
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
$explicitWintunProvided = -not [string]::IsNullOrWhiteSpace($WintunPath)
$explicitWintunExists = $false

if ($explicitWintunProvided) {
    $explicitWintunExists = Test-Path $WintunPath
    if ($explicitWintunExists) {
        Add-WintunCandidate $WintunPath
    } elseif ($RequireWintun) {
        Add-Result "FAIL" "wintun_path" ("WintunPath not found: " + $WintunPath)
    } else {
        Add-Result "WARN" "wintun_path" ("WintunPath not found: " + $WintunPath)
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
            $ekuDisplayValue -like "*代码签名*" -or
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
            FailOnWarn = [bool]$FailOnWarn
            RequireWintun = [bool]$RequireWintun
            WintunPath = $WintunPath
        }
        Summary = [pscustomobject]@{
            Fail = [int]$failCount
            Warn = [int]$warnCount
            Pass = [int]$passCount
        }
        Results = $results
    }

    $jsonReport | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonReportPath -Encoding UTF8
}

Write-Host ("P6 preflight report written: " + $reportPath)
Write-Host ("Summary: FAIL=" + $failCount + " WARN=" + $warnCount)
if ($WriteJsonReport) {
    Write-Host ("P6 preflight json report written: " + $jsonReportPath)
}

if ($failCount -gt 0) {
    throw "P6 release preflight failed."
}

if ($FailOnWarn -and $warnCount -gt 0) {
    throw ("P6 release preflight strict mode failed: WARN=" + $warnCount)
}

Write-Host "P6 release preflight checks passed."
