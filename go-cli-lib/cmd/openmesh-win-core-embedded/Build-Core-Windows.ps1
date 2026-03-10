param(
    [string]$Architecture = "amd64",
    [string]$WintunVersion = "0.14.1"
)

$ErrorActionPreference = "Stop"
$env:CGO_ENABLED = "1"

# Check for GCC (required for cgo)
if (!(Get-Command gcc -ErrorAction SilentlyContinue)) {
    Write-Host "🔍 GCC not in PATH, searching in common locations..." -ForegroundColor Cyan
    $extraPaths = @(
        "C:\msys64\ucrt64\bin",
        "C:\msys64\mingw64\bin",
        "D:\worker\tools\w64devkit\w64devkit\bin"
    )
    foreach ($p in $extraPaths) {
        if (Test-Path (Join-Path $p "gcc.exe")) {
            $env:PATH = "$p;" + $env:PATH
            Write-Host "✅ Found GCC in $p. Added to temporary PATH." -ForegroundColor Green
            break
        }
    }
}

if (!(Get-Command gcc -ErrorAction SilentlyContinue)) {
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Red
    Write-Host "❌ ERROR: C Compiler (gcc) not found!" -ForegroundColor Red
    Write-Host "Building openmesh_core.dll requires GCC (MinGW-w64) for CGO support." -ForegroundColor White
    Write-Host "Please install it via one of these methods:" -ForegroundColor White
    Write-Host " 1. MSYS2: 'pacman -S mingw-w64-x86_64-gcc'" -ForegroundColor Yellow
    Write-Host " 2. Chocolatey: 'choco install mingw'" -ForegroundColor Yellow
    Write-Host " 3. Scoop: 'scoop install gcc'" -ForegroundColor Yellow
    Write-Host "After installation, ensure 'gcc.exe' is in your PATH." -ForegroundColor White
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Red
    throw "Build prerequisites not met: GCC missing."
}

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
    # Use the stable link for latest version (0.14.1) as versioned links may be broken
    $wintunUrl = "https://www.wintun.net/builds/wintun.zip"
    $tempZip = Join-Path $env:TEMP "wintun.zip"
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
        }
        else {
            throw "Could not find $Architecture\wintun.dll in the downloaded archive."
        }
    }
    finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    }
}
else {
    $size = (Get-Item $wintunDllPath).Length
    Write-Host "✅ wintun.dll already present ($($size) bytes). Skipping download." -ForegroundColor Gray
}

# 3. Build the Core DLL
Write-Host "🚀 Building openmesh_core.dll (self-contained with embedded drivers)..." -ForegroundColor Cyan
# Ensure we are in the correct directory for relative embed paths to work
Push-Location $scriptRoot
try {
    # Using -ldflags to strip symbols and reduce size. Added tags for full feature support.
    $tags = "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_clash_api,tfogo_checklinkname0"
    go build -tags "$tags" -buildmode=c-shared -ldflags="-s -w -checklinkname=0" -o openmesh_core.dll . 
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✨ Build successful: openmesh_core.dll and .h generated." -ForegroundColor Green
        
        # 4. Copy to Windows Project directory
        $winProjectLibs = Join-Path $scriptRoot "..\..\..\openmesh-win\libs"
        if (Test-Path $winProjectLibs) {
            Write-Host "📦 Copying artifacts to $winProjectLibs..." -ForegroundColor Cyan
            Copy-Item "openmesh_core.dll" $winProjectLibs -Force
            Copy-Item "openmesh_core.h" $winProjectLibs -Force
            Write-Host "✅ Sync complete." -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Windows libs directory not found at $winProjectLibs. Skipping sync." -ForegroundColor Yellow
        }

        Get-Item openmesh_core.dll | Select-Object Name, Length, LastWriteTime
    }
    else {
        throw "Go build failed. Please ensure GCC (MinGW) is installed and in your PATH."
    }
}
finally {
    Pop-Location
}
