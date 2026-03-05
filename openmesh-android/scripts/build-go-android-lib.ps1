param(
    [string]$GoCliLibDir = "..\go-cli-lib",
    [string]$OutputLibsDir = ".\libs",
    [string]$FrameworkName = "OpenMeshGo",
    [string]$GoTags = "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_clash_api,with_conntrack",
    [int]$AndroidApi = 21,
    [string]$ExtraGoFlags = "-ldflags=-checklinkname=0"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$androidRoot = Resolve-Path (Join-Path $scriptDir "..")
$goCliLibPath = Resolve-Path (Join-Path $androidRoot $GoCliLibDir)
$libsPath = Join-Path $androidRoot $OutputLibsDir
$androidBuildDir = Join-Path $goCliLibPath "lib\android"
$aarPath = Join-Path $androidBuildDir ("{0}.aar" -f $FrameworkName)
$sourcesJarPath = Join-Path $androidBuildDir ("{0}-sources.jar" -f $FrameworkName)

$sdkRootCandidates = @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    (Join-Path $env:LOCALAPPDATA "Android\sdk")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$pkgs = @(
    "github.com/sagernet/sing-box/experimental/libbox",
    "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
)

Write-Host "== OpenMesh Android Go library build =="
Write-Host "go-cli-lib: $goCliLibPath"
Write-Host "android libs: $libsPath"

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "go command not found. Please install Go first."
}

$goBin = (go env GOPATH)
if (-not $goBin) {
    throw "Failed to read GOPATH from go env."
}
$gomobile = Join-Path $goBin "bin\gomobile.exe"
$gobind = Join-Path $goBin "bin\gobind.exe"

if (-not (Test-Path $gomobile) -or -not (Test-Path $gobind)) {
    Write-Host "Installing gomobile/gobind (sagernet fork)..."
    go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11
    go install github.com/sagernet/gomobile/cmd/gobind@v0.1.11
}

if (-not (Test-Path $gomobile)) {
    throw "gomobile executable not found after installation attempt: $gomobile"
}

Write-Host "Initializing gomobile toolchain..."
& $gomobile init

$sdkRoot = $null
$ndkRoot = $null
foreach ($candidate in $sdkRootCandidates) {
    if (-not (Test-Path $candidate)) { continue }
    $sdkRoot = $candidate

    $ndkDir = Join-Path $candidate "ndk"
    if (Test-Path $ndkDir) {
        $ndkCandidate = Get-ChildItem -Directory -Path $ndkDir -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($ndkCandidate) {
            $ndkRoot = $ndkCandidate.FullName
            break
        }
    }

    $bundleNdk = Join-Path $candidate "ndk-bundle"
    if (Test-Path $bundleNdk) {
        $ndkRoot = $bundleNdk
        break
    }
}

if (-not $sdkRoot -or -not $ndkRoot) {
    throw @"
Android SDK/NDK not found.
- Checked ANDROID_SDK_ROOT / ANDROID_HOME / %LOCALAPPDATA%\\Android\\sdk
- Please install Android NDK (for example with sdkmanager):
  sdkmanager ""ndk;27.2.12479018"" ""platforms;android-34"" ""build-tools;34.0.0""
Then rerun this script.
"@
}

$env:ANDROID_SDK_ROOT = $sdkRoot
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = $sdkRoot }
# Force javac to use UTF-8 so generated JavaDoc from Go comments won't fail on Windows locale.
if (-not $env:JAVA_TOOL_OPTIONS) {
    $env:JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8"
} elseif ($env:JAVA_TOOL_OPTIONS -notmatch "file\.encoding") {
    $env:JAVA_TOOL_OPTIONS = ($env:JAVA_TOOL_OPTIONS + " -Dfile.encoding=UTF-8").Trim()
}

New-Item -ItemType Directory -Force -Path $androidBuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $libsPath | Out-Null

Push-Location $goCliLibPath
try {
    $env:GOFLAGS = ("-mod=mod " + $ExtraGoFlags).Trim()
    Write-Host "Running gomobile bind..."
    & $gomobile bind -target=android "-androidapi=$AndroidApi" "-tags=$GoTags" -o $aarPath @pkgs
} finally {
    Pop-Location
}

if (-not (Test-Path $aarPath)) {
    throw "AAR not generated: $aarPath"
}

Copy-Item -Force $aarPath (Join-Path $libsPath (Split-Path $aarPath -Leaf))
if (Test-Path $sourcesJarPath) {
    Copy-Item -Force $sourcesJarPath (Join-Path $libsPath (Split-Path $sourcesJarPath -Leaf))
}

Write-Host "Build done."
Write-Host "AAR: $aarPath"
Write-Host "Copied to: $libsPath"
