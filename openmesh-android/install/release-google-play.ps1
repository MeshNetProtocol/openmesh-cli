# Build Go library (optional)
# Using script from scripts/build-go-android-lib.ps1

# Release Signing Configuration
# Create a file named 'signing.properties' in the project root with the following content:
# RELEASE_STORE_FILE=path/to/your/keystore.jks
# RELEASE_STORE_PASSWORD=your_keystore_password
# RELEASE_KEY_ALIAS=your_key_alias
# RELEASE_KEY_PASSWORD=your_key_password

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Resolve to project root (D:\worker\openmesh-cli\openmesh-android)
$androidRoot = Resolve-Path (Join-Path $scriptDir "..")
$signingPropsPath = Join-Path $androidRoot "signing.properties"

Write-Host "== OpenMesh Android Google Play Release Build ==" -ForegroundColor Cyan

# 1. Check for signing properties
if (-not (Test-Path $signingPropsPath)) {
    Write-Host "[WARNING] signing.properties not found at $signingPropsPath" -ForegroundColor Yellow
    Write-Host "Please create it with the following fields:"
    Write-Host "RELEASE_STORE_FILE=..."
    Write-Host "RELEASE_STORE_PASSWORD=..."
    Write-Host "RELEASE_KEY_ALIAS=..."
    Write-Host "RELEASE_KEY_PASSWORD=..."
    
    $choice = Read-Host "Do you want to continue without signing? (y/n)"
    if ($choice -ne 'y') {
        exit
    }
} else {
    Write-Host "[INFO] Using signing configuration from $signingPropsPath" -ForegroundColor Green
}

# 2. Build Go Library
$buildGo = Read-Host "Do you want to rebuild the Go library first? (y/n)"
if ($buildGo -eq 'y') {
    # It is located in the scripts/ folder, sibling to install/
    $goBuildScript = Join-Path $androidRoot "scripts\build-go-android-lib.ps1"
    if (-not (Test-Path $goBuildScript)) {
        Write-Host "[ERROR] Could not find $goBuildScript" -ForegroundColor Red
        exit
    }
    Write-Host "[INFO] Rebuilding Go library..." -ForegroundColor Gray
    & $goBuildScript
}

# 3. Clean and Build Bundle (AAB) & APK
Write-Host "[INFO] Cleaning and building App Bundle (AAB) and APK..." -ForegroundColor Gray
Push-Location $androidRoot
try {
    # Define ONLY properties in gradleArgs, tasks will be passed explicitly
    $gradleArgs = @()
    
    if (Test-Path $signingPropsPath) {
        $props = ConvertFrom-StringData (Get-Content $signingPropsPath -Raw)
        foreach ($key in $props.Keys) {
            $value = $props[$key]
            # Handle backslashes in Windows paths for Gradle
            if ($key -eq "RELEASE_STORE_FILE") {
                # Resolve to absolute path to be extremely safe
                $keystorePath = Join-Path $androidRoot $value
                if (Test-Path $keystorePath) {
                    $value = (Resolve-Path $keystorePath).Path.Replace('\', '/')
                }
            }
            # Add plain properties
            $gradleArgs += "-P$key=$value"
        }
    }

    # 1. Clean and Build App Bundle (AAB)
    Write-Host "[INFO] Building App Bundle (AAB)..." -ForegroundColor Gray
    .\gradlew.bat clean bundleRelease @gradleArgs --stacktrace
    if ($LASTEXITCODE -ne 0) { throw "Bundle build failed." }

    # 2. Build APK (without clean, to reuse compilation)
    Write-Host "[INFO] Building APK..." -ForegroundColor Gray
    .\gradlew.bat assembleRelease @gradleArgs --stacktrace
    if ($LASTEXITCODE -ne 0) { throw "APK build failed." }
}
catch {
    Write-Host "`n[ERROR] Build failed!" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Exit Code: $LASTEXITCODE" -ForegroundColor Red
    }
    if ((Get-Location).Path -eq $androidRoot) { Pop-Location }
    exit 1
}
finally {
    if ((Get-Location).Path -eq $androidRoot) {
        Pop-Location
    }
}

# 4. Success Info
$bundleSource = Join-Path $androidRoot "app\build\outputs\bundle\release\app-release.aab"
$apkDir = Join-Path $androidRoot "app\build\outputs\apk\release"
$apkSource = Get-ChildItem $apkDir -Filter "*.apk" | Select-Object -First 1

# Final check and copy to install directory
Write-Host "`n== Build Complete! ==" -ForegroundColor Green

if (Test-Path $bundleSource) {
    Copy-Item -Path $bundleSource -Destination $scriptDir -Force
    $bundleDest = Join-Path $scriptDir "app-release.aab"
    Write-Host "Release App Bundle (AAB) copied to: $bundleDest" -ForegroundColor Cyan
}

if ($apkSource) {
    Copy-Item -Path $apkSource.FullName -Destination $scriptDir -Force
    $apkDest = Join-Path $scriptDir $apkSource.Name
    Write-Host "Release APK copied to: $apkDest" -ForegroundColor Cyan
}

Write-Host "`nYou can find the release files in this directory: $scriptDir"
Write-Host "You can upload the AAB to the Google Play Console."
