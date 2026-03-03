param(
    [string]$Architecture = "amd64",
    [string]$WintunVersion = "0.14.1"
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptRoot)) { $scriptRoot = Get-Location }

# 1. Prepare Embeds Directory
$embedsDir = Join-Path $scriptRoot "embeds"
if (!(Test-Path $embedsDir)) {
    New-Item -ItemType Directory -Path $embedsDir -Force | Out-Null
    Write-Host "Created embeds directory."
}

# 2. Check for wintun.dll, download if missing
$wintunDllPath = Join-Path $embedsDir "wintun.dll"
if (!(Test-Path $wintunDllPath)) {
    Write-Host "🔍 wintun.dll missing in embeds, fetching from wintun.net..." -ForegroundColor Cyan
    $wintunUrl = "https://www.wintun.net/builds/wintun-$WintunVersion.zip"
    $tempZip = Join-Path $env:TEMP "wintun-$WintunVersion.zip"
    $tempDir = Join-Path $env:TEMP "wintun-extract"

    try {
        Invoke-WebRequest -Uri $wintunUrl -OutFile $tempZip -UserAgent "Mozilla/5.0"
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        # We need the amd64 version for Windows x64
        $sourceDll = Join-Path $tempDir "wintun\bin\$Architecture\wintun.dll"
        if (Test-Path $sourceDll) {
            Copy-Item $sourceDll $wintunDllPath -Force
            Write-Host "✅ Successfully retrieved wintun.dll ($Architecture) v$WintunVersion." -ForegroundColor Green
        } else {
            throw "Could not find $Architecture\wintun.dll in the downloaded archive."
        }
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    }
} else {
    $size = (Get-Item $wintunDllPath).Length
    Write-Host "✅ wintun.dll already present ($($size) bytes). Skipping download." -ForegroundColor Gray
}

# 3. Build the Core DLL
Write-Host "🚀 Building openmesh_core.dll (self-contained with embedded drivers)..." -ForegroundColor Cyan
# Ensure we are in the correct directory for relative embed paths to work
Push-Location $scriptRoot
try {
    # Using -ldflags to strip symbols and reduce size
    go build -buildmode=c-shared -ldflags="-s -w" -o openmesh_core.dll . 
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✨ Build successful: openmesh_core.dll and .h generated." -ForegroundColor Green
        
        # 4. Copy to Windows Project directory
        $winProjectLibs = Join-Path $scriptRoot "..\..\..\openmesh-win\libs"
        if (Test-Path $winProjectLibs) {
            Write-Host "📦 Copying artifacts to $winProjectLibs..." -ForegroundColor Cyan
            Copy-Item "openmesh_core.dll" $winProjectLibs -Force
            Copy-Item "openmesh_core.h" $winProjectLibs -Force
            Write-Host "✅ Sync complete." -ForegroundColor Green
        } else {
            Write-Host "⚠️ Windows libs directory not found at $winProjectLibs. Skipping sync." -ForegroundColor Yellow
        }

        Get-Item openmesh_core.dll | Select-Object Name, Length, LastWriteTime
    }
} finally {
    Pop-Location
}
