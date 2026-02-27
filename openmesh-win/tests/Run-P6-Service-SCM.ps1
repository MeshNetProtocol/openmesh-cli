param(
    [string]$Configuration = "Release",
    [string]$ServiceName = "OpenMeshWinServiceP6",
    [switch]$SkipStopConflictingProcesses,
    [switch]$RequireAdmin,
    [switch]$AutoElevate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$installerRoot = Join-Path $repoRoot "openmesh-win\installer"
$reportsDir = Join-Path $scriptRoot "reports"
$installScript = Join-Path $installerRoot "Install-OpenMeshWin.ps1"
$uninstallScript = Join-Path $installerRoot "Uninstall-OpenMeshWin.ps1"
$registerScript = Join-Path $installerRoot "Register-OpenMeshWin-Service.ps1"
$unregisterScript = Join-Path $installerRoot "Unregister-OpenMeshWin-Service.ps1"
$installDir = Join-Path $env:ProgramData "OpenMeshWin-P6-Service-SCM"
$selfScriptPath = $MyInvocation.MyCommand.Path

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

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-ConflictingProcesses {
    $names = @("OpenMeshWin.Service", "OpenMeshWin", "OpenMeshWin.Core")
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Format-CommandOutput([object[]]$lines, [int]$maxLines = 8) {
    if ($null -eq $lines -or $lines.Count -eq 0) {
        return ""
    }

    $textLines = $lines | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($textLines.Count -eq 0) {
        return ""
    }

    $tail = $textLines | Select-Object -Last $maxLines
    return ($tail -join " | ")
}

function Invoke-ElevatedSelf {
    param(
        [string]$ScriptPath,
        [string]$Cfg,
        [string]$SvcName,
        [bool]$SkipStop,
        [bool]$Require
    )

    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add("-NoProfile")
    $argsList.Add("-ExecutionPolicy")
    $argsList.Add("Bypass")
    $argsList.Add("-File")
    $argsList.Add($ScriptPath)
    $argsList.Add("-Configuration")
    $argsList.Add($Cfg)
    $argsList.Add("-ServiceName")
    $argsList.Add($SvcName)
    if ($SkipStop) {
        $argsList.Add("-SkipStopConflictingProcesses")
    }
    if ($Require) {
        $argsList.Add("-RequireAdmin")
    }

    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argsList.ToArray() -Verb RunAs -Wait -PassThru
    }
    catch {
        throw "UAC elevation launch failed: $($_.Exception.Message)"
    }
    return [int]$proc.ExitCode
}

foreach ($path in @($installScript, $uninstallScript, $registerScript, $unregisterScript)) {
    if (Test-Path $path) {
        Add-Result "PASS" "script_present" ("Found: " + $path)
    } else {
        Add-Result "FAIL" "script_present" ("Missing: " + $path)
    }
}

$isAdmin = Test-IsAdministrator
if ((-not $isAdmin) -and $AutoElevate) {
    Write-Host "Current shell is not elevated. Relaunching with UAC elevation..."
    $elevatedExitCode = Invoke-ElevatedSelf `
        -ScriptPath $selfScriptPath `
        -Cfg $Configuration `
        -SvcName $ServiceName `
        -SkipStop $SkipStopConflictingProcesses.IsPresent `
        -Require $RequireAdmin.IsPresent
    exit $elevatedExitCode
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses
}

if ($isAdmin) {
    Add-Result "PASS" "admin_privilege" "Current shell is elevated; SCM lifecycle checks enabled."
} elseif ($RequireAdmin) {
    Add-Result "FAIL" "admin_privilege" "Current shell is not elevated but -RequireAdmin was set."
} else {
    Add-Result "WARN" "admin_privilege" "Current shell is not elevated; SCM lifecycle checks skipped."
}

if ($isAdmin) {
    try {
        if (Test-Path $installDir) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -InstallDir $installDir -SkipRegistry -ServiceName $ServiceName | Out-Null
        }
    }
    catch {
    }

    $installExitCode = 0
    $installOutput = @()
    try {
        $installOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript `
            -InstallDir $installDir `
            -Configuration $Configuration `
            -SkipRegistry `
            -EnableService `
            -StartService `
            -ServiceStartupType Manual `
            -ServiceName $ServiceName 2>&1
        $installExitCode = $LASTEXITCODE
    }
    catch {
        $installOutput += $_
        $installExitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
    }
    $installOutputTail = Format-CommandOutput -lines $installOutput
    if ($installExitCode -eq 0) {
        Add-Result "PASS" "install_with_service" "Install-OpenMeshWin.ps1 completed with service registration."
    } else {
        $detail = "Install-OpenMeshWin.ps1 failed with exit code " + $installExitCode
        if (-not [string]::IsNullOrWhiteSpace($installOutputTail)) {
            $detail += "; output=" + $installOutputTail
        }
        Add-Result "FAIL" "install_with_service" $detail
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Add-Result "FAIL" "service_exists" ("Service missing after install: " + $ServiceName)
    } else {
        Add-Result "PASS" "service_exists" ("Service present: " + $ServiceName + ", status=" + $service.Status)
        if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Add-Result "PASS" "service_running" "Service is running."
        } else {
            Add-Result "FAIL" "service_running" ("Service is not running: " + $service.Status)
        }
    }

    $svcCim = Get-CimInstance Win32_Service -Filter ("Name='" + $ServiceName + "'") -ErrorAction SilentlyContinue
    if ($null -ne $svcCim) {
        $pathName = [string]$svcCim.PathName
        if ($pathName.ToLowerInvariant().Contains(($installDir.ToLowerInvariant() + "\service"))) {
            Add-Result "PASS" "service_path" ("Service path bound to install dir: " + $pathName)
        } else {
            Add-Result "FAIL" "service_path" ("Unexpected service path: " + $pathName)
        }
    } else {
        Add-Result "FAIL" "service_path" "Cannot query Win32_Service path."
    }

    $uninstallExitCode = 0
    $uninstallOutput = @()
    try {
        $uninstallOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -InstallDir $installDir -SkipRegistry -ServiceName $ServiceName 2>&1
        $uninstallExitCode = $LASTEXITCODE
    }
    catch {
        $uninstallOutput += $_
        $uninstallExitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
    }
    $uninstallOutputTail = Format-CommandOutput -lines $uninstallOutput
    if ($uninstallExitCode -eq 0) {
        Add-Result "PASS" "uninstall_with_service" "Uninstall-OpenMeshWin.ps1 completed."
    } else {
        $detail = "Uninstall-OpenMeshWin.ps1 failed with exit code " + $uninstallExitCode
        if (-not [string]::IsNullOrWhiteSpace($uninstallOutputTail)) {
            $detail += "; output=" + $uninstallOutputTail
        }
        Add-Result "FAIL" "uninstall_with_service" $detail
    }

    if ($null -eq (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        Add-Result "PASS" "service_removed" ("Service removed: " + $ServiceName)
    } else {
        Add-Result "FAIL" "service_removed" ("Service still exists: " + $ServiceName)
    }

    if (-not (Test-Path $installDir)) {
        Add-Result "PASS" "install_dir_removed" ("Install dir removed: " + $installDir)
    } else {
        Add-Result "FAIL" "install_dir_removed" ("Install dir still exists: " + $installDir)
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$reportPath = Join-Path $reportsDir ("p6-service-scm-" + $timestamp + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("OpenMeshWin P6 Service SCM")
$lines.Add("GeneratedAtUtc: " + (Get-Date).ToUniversalTime().ToString("o"))
$lines.Add("RepoRoot: " + $repoRoot)
$lines.Add("InstallDir: " + $installDir)
$lines.Add("ServiceName: " + $ServiceName)
$lines.Add("RequireAdmin: " + $RequireAdmin.IsPresent)
$lines.Add("AutoElevate: " + $AutoElevate.IsPresent)
$lines.Add("")
foreach ($r in $results) {
    $lines.Add("[" + $r.Level + "] " + $r.Check + " - " + $r.Detail)
}
$lines | Set-Content -Path $reportPath -Encoding UTF8

$failCount = ($results | Where-Object { $_.Level -eq "FAIL" } | Measure-Object).Count
$warnCount = ($results | Where-Object { $_.Level -eq "WARN" } | Measure-Object).Count

Write-Host ("P6 service SCM report written: " + $reportPath)
Write-Host ("Summary: FAIL=" + $failCount + " WARN=" + $warnCount)

if ($failCount -gt 0) {
    throw "P6 service SCM checks failed."
}

if ($warnCount -gt 0) {
    Write-Host "P6 service SCM checks passed with warnings."
} else {
    Write-Host "P6 service SCM checks passed."
}
