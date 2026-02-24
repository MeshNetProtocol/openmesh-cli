param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0-p6r3",
    [string]$ProductName = "OpenMeshWin",
    [string]$Manufacturer = "OpenMesh",
    [string]$UpgradeCode = "F2B44A4B-893A-4B8D-ABAE-2C5CECB60C2A"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$installerRoot = Join-Path $repoRoot "openmesh-win\installer"
$outputDir = Join-Path $installerRoot "output"
$reportsDir = Join-Path $scriptRoot "reports"
$buildMsiScript = Join-Path $installerRoot "Build-P6-Wix-Msi.ps1"

if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

function Resolve-WixToolchainType {
    $wix = Get-Command wix -ErrorAction SilentlyContinue
    if ($null -ne $wix -and -not [string]::IsNullOrWhiteSpace($wix.Source) -and (Test-Path $wix.Source)) {
        return "wix4"
    }
    $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
    $light = Get-Command light.exe -ErrorAction SilentlyContinue
    if ($null -ne $candle -and $null -ne $light -and (Test-Path $candle.Source) -and (Test-Path $light.Source)) {
        return "wix3"
    }
    return ""
}

function Normalize-MsiVersion([string]$rawVersion) {
    $matches = [System.Text.RegularExpressions.Regex]::Matches($rawVersion, "\d+")
    $parts = New-Object System.Collections.Generic.List[int]
    foreach ($m in $matches) {
        if ($parts.Count -ge 3) { break }
        $v = [int]$m.Value
        if ($v -lt 0) { $v = 0 }
        if ($v -gt 65535) { $v = 65535 }
        $parts.Add($v)
    }
    while ($parts.Count -lt 3) {
        $parts.Add(0)
    }
    return ("{0}.{1}.{2}" -f $parts[0], $parts[1], $parts[2])
}

function Get-MsiScalar([object]$db, [string]$sql) {
    try {
        $view = $db.OpenView($sql)
        $view.Execute() | Out-Null
        $record = $view.Fetch()
        if ($null -eq $record) {
            return $null
        }
        return $record.StringData(1)
    }
    catch {
        throw "MSI SQL failed: $sql ; $($_.Exception.Message)"
    }
}

function Get-MsiInt([object]$db, [string]$sql) {
    $raw = Get-MsiScalar -db $db -sql $sql
    if ($null -eq $raw) {
        return 0
    }
    return [int]$raw
}

function Get-MsiRowCount([object]$db, [string]$sql) {
    try {
        $view = $db.OpenView($sql)
        $view.Execute() | Out-Null
        $count = 0
        while ($true) {
            $record = $view.Fetch()
            if ($null -eq $record) {
                break
            }
            $count++
        }
        return $count
    }
    catch {
        throw "MSI SQL failed: $sql ; $($_.Exception.Message)"
    }
}

$toolchain = Resolve-WixToolchainType
if ([string]::IsNullOrWhiteSpace($toolchain)) {
    throw "WiX toolset not found. Install WiX first, then rerun."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $buildMsiScript -Configuration $Configuration -Version $Version -ProductName $ProductName -Manufacturer $Manufacturer -UpgradeCode $UpgradeCode
if ($LASTEXITCODE -ne 0) {
    throw "Build-P6-Wix-Msi.ps1 failed with exit code $LASTEXITCODE."
}

$msiPath = Join-Path $outputDir ("OpenMeshWin-" + $Version + ".msi")
if (-not (Test-Path $msiPath)) {
    throw "MSI output missing: $msiPath"
}

$msiItem = Get-Item -Path $msiPath
if ($msiItem.Length -le 0) {
    throw "MSI file size is invalid: $($msiItem.Length)"
}

$expectedMsiVersion = Normalize-MsiVersion $Version

$installer = New-Object -ComObject WindowsInstaller.Installer
$db = $null
try {
    $db = $installer.OpenDatabase($msiPath, 0)
    $productNameActual = [string](Get-MsiScalar -db $db -sql "SELECT Value FROM Property WHERE Property='ProductName'")
    $manufacturerActual = [string](Get-MsiScalar -db $db -sql "SELECT Value FROM Property WHERE Property='Manufacturer'")
    $productVersionActual = [string](Get-MsiScalar -db $db -sql "SELECT Value FROM Property WHERE Property='ProductVersion'")
    $upgradeCodeActual = [string](Get-MsiScalar -db $db -sql "SELECT Value FROM Property WHERE Property='UpgradeCode'")
    $fileCount = Get-MsiRowCount -db $db -sql 'SELECT `File` FROM `File`'
    $payloadCount = Get-MsiRowCount -db $db -sql 'SELECT `File` FROM `File` WHERE `File`=''filPayloadZip'''
}
finally {
    if ($null -ne $db) {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($db)
    }
    if ($null -ne $installer) {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
    }
}

if ($productNameActual -ne $ProductName) {
    throw "MSI ProductName mismatch. expected='$ProductName' actual='$productNameActual'"
}
if ($manufacturerActual -ne $Manufacturer) {
    throw "MSI Manufacturer mismatch. expected='$Manufacturer' actual='$manufacturerActual'"
}
if ($productVersionActual -ne $expectedMsiVersion) {
    throw "MSI ProductVersion mismatch. expected='$expectedMsiVersion' actual='$productVersionActual'"
}
$normalizeGuid = {
    param([string]$g)
    $raw = if ($null -eq $g) { "" } else { [string]$g }
    $x = $raw.Trim().Trim("{", "}").ToUpperInvariant()
    return $x
}
$expectedUpgradeCode = & $normalizeGuid $UpgradeCode
$actualUpgradeCode = & $normalizeGuid $upgradeCodeActual
if ($actualUpgradeCode -ne $expectedUpgradeCode) {
    throw "MSI UpgradeCode mismatch. expected='$UpgradeCode' actual='$upgradeCodeActual'"
}
if ($fileCount -lt 1) {
    throw "MSI File table is empty."
}
if ($payloadCount -lt 1) {
    throw "MSI payload file row missing (filPayloadZip)."
}

$hash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $reportsDir ("p6-wix-msi-validate-" + $timestamp + ".txt")
$reportLines = @(
    "OpenMeshWin P6 WiX MSI Validation"
    "GeneratedAtUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "WiXToolchain: $toolchain"
    "MsiPath: $msiPath"
    "MsiSizeBytes: $($msiItem.Length)"
    "MsiSha256: $hash"
    "ProductName: $productNameActual"
    "Manufacturer: $manufacturerActual"
    "ProductVersion: $productVersionActual"
    "UpgradeCode: $upgradeCodeActual"
    "FileTableCount: $fileCount"
    "PayloadRowCount: $payloadCount"
)
$reportLines | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ("P6 wix msi validation report written: " + $reportPath)
Write-Host "P6 wix msi validation checks passed."
