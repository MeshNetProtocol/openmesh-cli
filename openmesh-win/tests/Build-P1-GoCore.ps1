param(
    [string]$OutputPath = "",
    [string]$GoExePath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path
$goCliLibRoot = Join-Path $repoRoot "go-cli-lib"
$goCoreModuleRoot = Join-Path $goCliLibRoot "cmd\openmesh-win-core"

function Resolve-GoExePath([string]$explicitPath) {
    if (-not [string]::IsNullOrWhiteSpace($explicitPath) -and (Test-Path $explicitPath)) {
        return (Resolve-Path $explicitPath).Path
    }

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

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $goCoreModuleRoot "openmesh-win-core.exe"
}

$resolvedGoExe = Resolve-GoExePath -explicitPath $GoExePath
if ($null -eq $resolvedGoExe) {
    throw (
        "Go toolchain not found. Install Go from https://go.dev/dl/ and rerun. " +
        "You can also pass -GoExePath <path-to-go.exe> or set OPENMESH_GO_EXE."
    )
}

Write-Host "Building go core with: $resolvedGoExe"
& $resolvedGoExe -C $goCoreModuleRoot mod tidy
if ($LASTEXITCODE -ne 0) {
    throw "go mod tidy failed with exit code $LASTEXITCODE."
}

& $resolvedGoExe -C $goCoreModuleRoot build -o $OutputPath .
if ($LASTEXITCODE -ne 0) {
    throw "go build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $OutputPath)) {
    throw "Build finished but output missing: $OutputPath"
}

Write-Host "Go core build succeeded: $OutputPath"
