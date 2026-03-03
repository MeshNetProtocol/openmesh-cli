param(
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$installerRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($installerRoot)) { $installerRoot = Get-Location }
$repoRoot = (Resolve-Path (Join-Path $installerRoot "..\..")).Path

Write-Host "--- Professional Installer Build Started ---" -ForegroundColor Cyan

# 1. Build the Go Core (Self-Contained)
Write-Host "1. Building Go Core (openmesh_core.dll)..." -ForegroundColor Cyan
Push-Location (Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core-embedded")
try {
    ./Build-Core-Windows.ps1
}
catch {
    Write-Host "❌ Core build failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}

# 2. Publish the C# App (Self-Contained Single File)
Write-Host "2. Publishing C# App (Self-Contained)..." -ForegroundColor Cyan
$stagingDir = Join-Path $installerRoot "staging\app"
$uiProject = Join-Path $repoRoot "openmesh-win\OpenMeshWin.csproj"

if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

dotnet publish $uiProject `
    -c $Configuration `
    -r win-x64 `
    --self-contained `
    -o $stagingDir `
    --nologo `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:PublishReadyToRun=true

# 3. Build the MSI with WiX
Write-Host "3. Generating MSI Installer (WiX)..." -ForegroundColor Cyan
$msiOutput = Join-Path $installerRoot "output\OpenMeshWin-$Version-$Configuration.msi"
if (!(Test-Path (Split-Path $msiOutput))) { New-Item -ItemType Directory -Path (Split-Path $msiOutput) -Force }

# Note: Using wix build from WiX v4+
# Adjusting wxs pointers to use the staging app directory
Set-Location $installerRoot
try {
    # Check if wix extension for UI is missing and add if needed
    # wix extension add WixToolset.UI.wixext
    # wix build OpenMeshWin.V2.wxs -ext WixToolset.UI.wixext -o $msiOutput
    
    # If the UI extension is difficult to get, we can do a standard build first
    wix build OpenMeshWin.V2.wxs -o $msiOutput -arch x64
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ COMPLETED: MSI generated at $msiOutput" -ForegroundColor Green
        ls $msiOutput | Select-Object Name, Length, LastWriteTime
    }
}
finally {
    Pop-Location
}
