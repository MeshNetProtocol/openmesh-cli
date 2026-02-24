param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\output",
    [switch]$RequireWintun,
    [switch]$AutoCopyWintun,
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

function Resolve-WintunPath([string]$explicitPath, [string]$repoRoot) {
    if (-not [string]::IsNullOrWhiteSpace($explicitPath)) {
        if (Test-Path $explicitPath) {
            return (Resolve-Path $explicitPath).Path
        }
        throw "Configured wintun source path not found: $explicitPath"
    }

    $candidates = @(
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

$resolvedWintunPath = Resolve-WintunPath -explicitPath $WintunSourcePath -repoRoot $repoRoot
if ($RequireWintun -and [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
    throw "wintun.dll is required but was not found. Provide -WintunSourcePath or install wintun."
}

if (Test-Path $stagingRoot) {
    Remove-Item -Path $stagingRoot -Recurse -Force
}

New-Item -Path $publishApp -ItemType Directory -Force | Out-Null
New-Item -Path $publishCore -ItemType Directory -Force | Out-Null
New-Item -Path $publishService -ItemType Directory -Force | Out-Null
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

& dotnet publish $uiProject -c $Configuration -o $publishApp
& dotnet publish $coreProject -c $Configuration -o $publishCore
& dotnet publish $serviceProject -c $Configuration -o $publishService

if ($AutoCopyWintun -and -not [string]::IsNullOrWhiteSpace($resolvedWintunPath)) {
    Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $publishCore "wintun.dll") -Force
    Copy-Item -Path $resolvedWintunPath -Destination (Join-Path $publishService "wintun.dll") -Force
}

Copy-Item -Path (Join-Path $scriptRoot "Install-OpenMeshWin.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Uninstall-OpenMeshWin.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Register-OpenMeshWin-Service.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $scriptRoot "Unregister-OpenMeshWin-Service.ps1") -Destination $packageRoot -Force

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
Write-Host "RequireWintun: $($RequireWintun.IsPresent)"
Write-Host "AutoCopyWintun: $($AutoCopyWintun.IsPresent)"
Write-Host "WintunPath: $(if ([string]::IsNullOrWhiteSpace($resolvedWintunPath)) { '(not found)' } else { $resolvedWintunPath })"
