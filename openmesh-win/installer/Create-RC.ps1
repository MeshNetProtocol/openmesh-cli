param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0-rc1"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $scriptRoot "output"
$buildPackageScript = Join-Path $scriptRoot "Build-Package.ps1"

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $buildPackageScript -Configuration $Configuration -OutputDir $outputDir

$zipPath = Join-Path $outputDir "OpenMeshWin-$Configuration.zip"
if (-not (Test-Path $zipPath)) {
    throw "Package zip missing: $zipPath"
}

$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
$manifestPath = Join-Path $outputDir "OpenMeshWin-$Version-manifest.json"
$manifest = [ordered]@{
    version = $Version
    buildConfiguration = $Configuration
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    packageFile = [System.IO.Path]::GetFileName($zipPath)
    sha256 = $hash
}

$manifest | ConvertTo-Json | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "RC package ready."
Write-Host "Package: $zipPath"
Write-Host "Manifest: $manifestPath"
