param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\output",
    [string]$ProductName = "meshflux",
    [switch]$RequireWintun,
    [switch]$AutoCopyWintun,
    [switch]$SkipCopyWintun,
    [switch]$FrameworkDependent,
    [switch]$SkipZip,
    [switch]$VerifyPackage,
    [string]$VerifyReportPath = "",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$WintunSourcePath = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

$uiProject = Join-Path $repoRoot "openmesh-win\OpenMeshWin.csproj"
$coreProject = Join-Path $repoRoot "openmesh-win\core\OpenMeshWin.Core\OpenMeshWin.Core.csproj"
$serviceProject = Join-Path $repoRoot "openmesh-win\service\OpenMeshWin.Service\OpenMeshWin.Service.csproj"
$stagingRoot = Join-Path $scriptRoot "staging"
$packageRoot = Join-Path $stagingRoot "package"
$publishApp = Join-Path $packageRoot "app"
$publishCore = Join-Path $packageRoot "core"
$publishService = Join-Path $packageRoot "service"
$publishAppLibs = Join-Path $publishApp "libs"
$publishAppDeps = Join-Path $publishApp "deps"
$publishAppDepsWintun = Join-Path $publishAppDeps "wintun"
$verifyScript = Join-Path $scriptRoot "Verify-Package-Contents.ps1"

function Resolve-WintunPath([string]$explicitPath, [string]$repoRoot) {
    if (-not [string]::IsNullOrWhiteSpace($explicitPath)) {
        if (Test-Path $explicitPath) {
            return (Resolve-Path $explicitPath).Path
        }
        throw "Configured wintun source path not found: $explicitPath"
    }

    $candidates = @(
        (Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core-embedded\embeds\wintun.dll"),
        (Join-Path $repoRoot "openmesh-win\deps\wintun.dll"),
        "C:\Windows\System32\wintun.dll",
        "C:\Windows\SysWOW64\wintun.dll"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return ""
}

function Publish-Project([string]$projectPath, [string]$configuration, [string]$runtimeIdentifier, [string]$outputPath, [bool]$frameworkDependent) {
    $args = @(
        $projectPath,
        "-c", $configuration,
        "-r", $runtimeIdentifier,
        "-o", $outputPath,
        "--nologo"
    )
    if ($frameworkDependent) {
        $args += "--no-self-contained"
    }
    else {
        $args += "--self-contained"
    }
    $args += "/p:PublishSingleFile=false"
    $args += "/p:PublishReadyToRun=true"

    & dotnet publish @args
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $projectPath (exit=$LASTEXITCODE)."
    }
}

function Copy-RequiredNativeBinaries([string]$repoRoot, [string]$publishAppLibs, [string]$publishCore) {
    $coreDll = Join-Path $repoRoot "openmesh-win\libs\openmesh_core.dll"
    $coreHeader = Join-Path $repoRoot "openmesh-win\libs\openmesh_core.h"
    $pthreadDll = Join-Path $repoRoot "openmesh-win\libs\libwinpthread-1.dll"

    if (-not (Test-Path $coreDll)) {
        throw "Required file missing: $coreDll. Run go-cli-lib\\cmd\\openmesh-win-core-embedded\\Build-Core-Windows.ps1 first."
    }
    if (-not (Test-Path $pthreadDll)) {
        throw "Required file missing: $pthreadDll."
    }

    New-Item -Path $publishAppLibs -ItemType Directory -Force | Out-Null
    Copy-Item -Path $coreDll -Destination (Join-Path $publishAppLibs "openmesh_core.dll") -Force
    Copy-Item -Path $pthreadDll -Destination (Join-Path $publishAppLibs "libwinpthread-1.dll") -Force
    if (Test-Path $coreHeader) {
        Copy-Item -Path $coreHeader -Destination (Join-Path $publishAppLibs "openmesh_core.h") -Force
    }

    # Core runner uses DllImport("openmesh_core"), so keep native libs next to core executable.
    Copy-Item -Path $coreDll -Destination (Join-Path $publishCore "openmesh_core.dll") -Force
    Copy-Item -Path $pthreadDll -Destination (Join-Path $publishCore "libwinpthread-1.dll") -Force
}

$resolvedWintunPath = Resolve-WintunPath -explicitPath $WintunSourcePath -repoRoot $repoRoot
if ($RequireWintun -and [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
    throw "wintun.dll is required but was not found. Provide -WintunSourcePath or install wintun."
}

$copyWintunEnabled = -not $SkipCopyWintun
if ($AutoCopyWintun.IsPresent) {
    $copyWintunEnabled = $true
}

if (Test-Path $stagingRoot) {
    Remove-Item -Path $stagingRoot -Recurse -Force
}

New-Item -Path $publishApp -ItemType Directory -Force | Out-Null
New-Item -Path $publishCore -ItemType Directory -Force | Out-Null
New-Item -Path $publishService -ItemType Directory -Force | Out-Null
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

Publish-Project -projectPath $uiProject -configuration $Configuration -runtimeIdentifier $RuntimeIdentifier -outputPath $publishApp -frameworkDependent:$FrameworkDependent.IsPresent
Publish-Project -projectPath $coreProject -configuration $Configuration -runtimeIdentifier $RuntimeIdentifier -outputPath $publishCore -frameworkDependent:$FrameworkDependent.IsPresent
Publish-Project -projectPath $serviceProject -configuration $Configuration -runtimeIdentifier $RuntimeIdentifier -outputPath $publishService -frameworkDependent:$FrameworkDependent.IsPresent
Copy-RequiredNativeBinaries -repoRoot $repoRoot -publishAppLibs $publishAppLibs -publishCore $publishCore

if ($copyWintunEnabled -and -not [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
    Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $publishCore "wintun.dll") -Force
    Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $publishService "wintun.dll") -Force
    New-Item -Path $publishAppDepsWintun -ItemType Directory -Force | Out-Null
    Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $publishAppDepsWintun "wintun.dll") -Force
}

Copy-Item -Path (Join-Path $scriptRoot "Install-OpenMeshWin.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Uninstall-OpenMeshWin.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Register-OpenMeshWin-Service.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Unregister-OpenMeshWin-Service.ps1") -Destination $packageRoot -Force

$archivePath = ""
if (-not $SkipZip) {
    $archivePath = Join-Path $OutputDir ("$ProductName-$Configuration.zip")
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
    }

    $compressed = $false
    $maxAttempts = 8
    $delayMs = 600
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $archivePath -ErrorAction Stop
            $compressed = $true
            break
        }
        catch {
            if (Test-Path $archivePath) {
                Remove-Item -Path $archivePath -Force -ErrorAction SilentlyContinue
            }
            if ($attempt -ge $maxAttempts) {
                throw
            }
            Start-Sleep -Milliseconds $delayMs
            $delayMs = [Math]::Min($delayMs * 2, 8000)
        }
    }
    if (-not $compressed) {
        throw "Compress-Archive failed."
    }

    Write-Host "Package generated: $archivePath"
}
else {
    Write-Host ("Package staging directory: " + $packageRoot)
}
Write-Host "RequireWintun: $($RequireWintun.IsPresent)"
Write-Host "CopyWintun: $copyWintunEnabled"
Write-Host "FrameworkDependent: $($FrameworkDependent.IsPresent)"
Write-Host "SkipZip: $($SkipZip.IsPresent)"
Write-Host "RuntimeIdentifier: $RuntimeIdentifier"
Write-Host "WintunPath: $(if ([string]::IsNullOrWhiteSpace($resolvedWintunPath)) { '(not found)' } else { $resolvedWintunPath })"

if ($VerifyPackage) {
    $verifyArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $verifyScript
    )
    if (-not $SkipZip) {
        $verifyArgs += @("-ZipPath", $archivePath)
    }
    else {
        $verifyArgs += @("-PackageDir", $packageRoot)
    }
    if ($copyWintunEnabled) {
        $verifyArgs += "-RequireWintun"
    }
    if (-not $FrameworkDependent) {
        $verifyArgs += "-RequireSelfContained"
    }
    if (-not [string]::IsNullOrWhiteSpace($VerifyReportPath)) {
        $verifyArgs += @("-ReportPath", $VerifyReportPath)
    }

    & powershell @verifyArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Verify-Package-Contents.ps1 failed with exit code $LASTEXITCODE."
    }
}
