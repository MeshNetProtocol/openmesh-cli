$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootBuildScript = Join-Path $scriptDir "..\..\build_dll.bat"
$rootBuildScript = [System.IO.Path]::GetFullPath($rootBuildScript)

if (-not (Test-Path $rootBuildScript)) {
    throw "Unified build script not found: $rootBuildScript"
}

Write-Host "[INFO] Delegating to $rootBuildScript"
& cmd /c "`"$rootBuildScript`""
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "Unified build failed with exit code $exitCode"
}

Write-Host "[SUCCESS] Unified build completed."
