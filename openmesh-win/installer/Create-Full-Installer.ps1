param(
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0",
    [switch]$FrameworkDependent,
    [switch]$SkipCopyWintun,
    [switch]$SkipVerifyPackage,
    [string]$VerifyReportPath = "",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$WintunSourcePath = ""
)

$ErrorActionPreference = "Stop"
$installerRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($installerRoot)) { $installerRoot = Get-Location }
$repoRoot = (Resolve-Path (Join-Path $installerRoot "..\..")).Path

Write-Host "--- OpenMeshWin Unified Installer Build Started ---" -ForegroundColor Cyan

# Build latest embedded go core first, then package everything via P6 pipeline.
$goCoreBuild = Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core-embedded\Build-Core-Windows.ps1"
$buildP6 = Join-Path $installerRoot "Build-P6-Wix-Msi.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass -File $goCoreBuild
if ($LASTEXITCODE -ne 0) {
    throw "Build-Core-Windows.ps1 failed with exit code $LASTEXITCODE."
}

$p6Args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $buildP6,
    "-Configuration", $Configuration,
    "-Version", $Version,
    "-RuntimeIdentifier", $RuntimeIdentifier,
    "-RequireWintun"
)

if ($FrameworkDependent) {
    $p6Args += "-FrameworkDependent"
}
if ($SkipCopyWintun) {
    $p6Args += "-SkipCopyWintun"
}
if ($SkipVerifyPackage) {
    $p6Args += "-SkipVerifyPackage"
}
if (-not [string]::IsNullOrWhiteSpace($VerifyReportPath)) {
    $p6Args += @("-VerifyReportPath", $VerifyReportPath)
}
if (-not [string]::IsNullOrWhiteSpace($WintunSourcePath)) {
    $p6Args += @("-WintunSourcePath", $WintunSourcePath)
}

& powershell @p6Args
if ($LASTEXITCODE -ne 0) {
    throw "Build-P6-Wix-Msi.ps1 failed with exit code $LASTEXITCODE."
}

Write-Host "Unified MSI pipeline completed." -ForegroundColor Green
