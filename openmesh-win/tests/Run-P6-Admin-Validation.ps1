param(
    [string]$Configuration = "Release",
    [string]$ServiceName = "OpenMeshWinServiceP6",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$reportsDir = Join-Path $scriptRoot "reports"
$scmScript = Join-Path $scriptRoot "Run-P6-Service-SCM.ps1"
$preflightScript = Join-Path $scriptRoot "Run-P6-Release-Preflight.ps1"

if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Step([string]$title, [scriptblock]$action) {
    Write-Host ""
    Write-Host ("===== " + $title + " =====")
    & $action
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

if (-not (Test-IsAdministrator)) {
    throw "This script must run in an elevated Administrator PowerShell."
}

$overallFailed = $false
$errorMessages = New-Object System.Collections.Generic.List[string]

try {
    Invoke-Step "P6 Service SCM (RequireAdmin)" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $scmScript -Configuration $Configuration -ServiceName $ServiceName -RequireAdmin
        if ($LASTEXITCODE -ne 0) {
            throw "Run-P6-Service-SCM.ps1 failed with exit code $LASTEXITCODE."
        }
    }
}
catch {
    $overallFailed = $true
    $errorMessages.Add([string]$_.Exception.Message)
}

try {
    Invoke-Step "P6 Release Preflight" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightScript
        if ($LASTEXITCODE -ne 0) {
            throw "Run-P6-Release-Preflight.ps1 failed with exit code $LASTEXITCODE."
        }
    }
}
catch {
    $overallFailed = $true
    $errorMessages.Add([string]$_.Exception.Message)
}

$latestScm = Get-LatestReport -pattern "p6-service-scm-*.txt"
$latestPreflight = Get-LatestReport -pattern "p6-release-preflight-*.txt"

Write-Host ""
Write-Host "===== Latest Reports ====="
if (-not [string]::IsNullOrWhiteSpace($latestScm)) {
    Write-Host ("SCM: " + $latestScm)
}
if (-not [string]::IsNullOrWhiteSpace($latestPreflight)) {
    Write-Host ("Preflight: " + $latestPreflight)
}

if ($overallFailed) {
    Write-Host ""
    Write-Host "===== Result: FAILED ====="
    foreach ($msg in $errorMessages) {
        Write-Host ("- " + $msg)
    }
    if (-not $NoPause) {
        [void](Read-Host "Press Enter to exit")
    }
    exit 1
}

Write-Host ""
Write-Host "===== Result: PASSED ====="
if (-not $NoPause) {
    [void](Read-Host "Press Enter to exit")
}
