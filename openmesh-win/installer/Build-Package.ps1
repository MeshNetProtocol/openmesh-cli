param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\output"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

$uiProject = Join-Path $repoRoot "openmesh-win\OpenMeshWin.csproj"
$coreProject = Join-Path $repoRoot "openmesh-win\core\OpenMeshWin.Core\OpenMeshWin.Core.csproj"
$stagingRoot = Join-Path $scriptRoot "staging"
$packageRoot = Join-Path $stagingRoot "package"
$publishApp = Join-Path $packageRoot "app"
$publishCore = Join-Path $packageRoot "core"

if (Test-Path $stagingRoot) {
    Remove-Item -Path $stagingRoot -Recurse -Force
}

New-Item -Path $publishApp -ItemType Directory -Force | Out-Null
New-Item -Path $publishCore -ItemType Directory -Force | Out-Null
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

& dotnet publish $uiProject -c $Configuration -o $publishApp
& dotnet publish $coreProject -c $Configuration -o $publishCore

Copy-Item -Path (Join-Path $scriptRoot "Install-OpenMeshWin.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Uninstall-OpenMeshWin.ps1") -Destination $packageRoot -Force

$archivePath = Join-Path $OutputDir "OpenMeshWin-$Configuration.zip"
if (Test-Path $archivePath) {
    Remove-Item -Path $archivePath -Force
}

$compressed = $false
for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
        Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $archivePath -ErrorAction Stop
        $compressed = $true
        break
    }
    catch {
        if ($attempt -ge 2) {
            throw
        }
        Start-Sleep -Milliseconds 800
    }
}
if (-not $compressed) {
    throw "Compress-Archive failed."
}
Write-Host "Package generated: $archivePath"
