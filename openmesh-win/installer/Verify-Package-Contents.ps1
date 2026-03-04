param(
    [string]$ZipPath = "",
    [switch]$RequireWintun,
    [switch]$RequireSelfContained,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $ZipPath = Join-Path $scriptRoot "output\OpenMeshWin-Release.zip"
}

if (-not (Test-Path $ZipPath)) {
    throw "Zip package not found: $ZipPath"
}

$zipFullPath = (Resolve-Path $ZipPath).Path
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipFullPath)
try {
    $entrySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $zip.Entries) {
        $normalized = ($entry.FullName -replace "\\", "/").TrimStart("/")
        [void]$entrySet.Add($normalized)
    }
}
finally {
    $zip.Dispose()
}

function Test-Entry([System.Collections.Generic.HashSet[string]]$set, [string]$path) {
    return $set.Contains(($path -replace "\\", "/").TrimStart("/"))
}

$required = New-Object System.Collections.Generic.List[string]
$required.Add("app/OpenMeshWin.exe")
$required.Add("app/OpenMeshWin.dll")
$required.Add("app/OpenMeshWin.deps.json")
$required.Add("app/OpenMeshWin.runtimeconfig.json")
$required.Add("app/libs/openmesh_core.dll")
$required.Add("app/libs/libwinpthread-1.dll")
$required.Add("core/OpenMeshWin.Core.exe")
$required.Add("core/OpenMeshWin.Core.dll")
$required.Add("core/openmesh_core.dll")
$required.Add("core/libwinpthread-1.dll")
$required.Add("service/OpenMeshWin.Service.exe")
$required.Add("service/OpenMeshWin.Service.dll")
$required.Add("Install-OpenMeshWin.ps1")
$required.Add("Uninstall-OpenMeshWin.ps1")
$required.Add("Register-OpenMeshWin-Service.ps1")
$required.Add("Unregister-OpenMeshWin-Service.ps1")

if ($RequireWintun) {
    $required.Add("app/deps/wintun.dll")
    $required.Add("core/wintun.dll")
    $required.Add("service/wintun.dll")
}

if ($RequireSelfContained) {
    $required.Add("app/hostfxr.dll")
    $required.Add("app/coreclr.dll")
}

$results = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[string]
foreach ($item in $required) {
    $ok = Test-Entry -set $entrySet -path $item
    $results.Add([pscustomobject]@{
        Path = $item
        Present = $ok
    })
    if (-not $ok) {
        $missing.Add($item)
    }
}

Write-Host ("Package: " + $zipFullPath)
Write-Host ("RequireWintun: " + $RequireWintun.IsPresent)
Write-Host ("RequireSelfContained: " + $RequireSelfContained.IsPresent)
foreach ($r in $results) {
    if ($r.Present) {
        Write-Host ("PASS " + $r.Path) -ForegroundColor Green
    } else {
        Write-Host ("FAIL " + $r.Path) -ForegroundColor Red
    }
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportDir = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDir)) {
        New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
    }
    $report = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("s")
        ZipPath = $zipFullPath
        RequireWintun = $RequireWintun.IsPresent
        RequireSelfContained = $RequireSelfContained.IsPresent
        Missing = $missing
        Results = $results
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportPath -Encoding UTF8
    Write-Host ("Report: " + (Resolve-Path $ReportPath).Path)
}

if ($missing.Count -gt 0) {
    throw ("Package validation failed, missing " + $missing.Count + " entries.")
}

Write-Host "Package validation passed."
