param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0",
    [string]$OutputDir = "",
    [string]$ProductName = "OpenMeshWin",
    [string]$Manufacturer = "OpenMesh",
    [string]$UpgradeCode = "F2B44A4B-893A-4B8D-ABAE-2C5CECB60C2A",
    [switch]$RequireWintun,
    [switch]$AutoCopyWintun,
    [switch]$SkipCopyWintun,
    [switch]$FrameworkDependent,
    [switch]$SkipVerifyPackage,
    [string]$VerifyReportPath = "",
    [switch]$CleanOutput,
    [string]$RuntimeIdentifier = "win-x64",
    [string]$WintunSourcePath = "",
    [switch]$SkipBuildPackage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $scriptRoot "output"
}

$buildPackageScript = Join-Path $scriptRoot "Build-Package.ps1"
$packageRoot = Join-Path $scriptRoot "staging\package"
$tempRoot = Join-Path $scriptRoot "staging\wix"

function Clear-OutputArtifacts([string]$outputDir) {
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        return
    }

    $patterns = @(
        "OpenMeshWin-*",
        "package-verify*.json",
        "msi*.log"
    )
    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $outputDir -File -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
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
    while ($parts.Count -lt 3) { $parts.Add(0) }
    return ("{0}.{1}.{2}" -f $parts[0], $parts[1], $parts[2])
}

function Escape-Xml([string]$text) {
    if ($null -eq $text) { return "" }
    return [System.Security.SecurityElement]::Escape($text)
}

function New-ComponentId([int]$index) { return ("cmp{0}" -f $index.ToString("00000")) }
function New-FileId([int]$index) { return ("fil{0}" -f $index.ToString("00000")) }

function Resolve-Wix4Path {
    $wix = Get-Command wix -ErrorAction SilentlyContinue
    if ($null -eq $wix -or [string]::IsNullOrWhiteSpace($wix.Source) -or -not (Test-Path $wix.Source)) {
        throw "WiX v4+ not found. Install with: dotnet tool install --global wix"
    }
    return (Resolve-Path $wix.Source).Path
}

function Ensure-WixUiExtension([string]$wixPath) {
    $listOutput = & $wixPath extension list -g 2>&1
    if ($LASTEXITCODE -eq 0 -and (($listOutput -join "`n") -match "WixToolset\.UI\.wixext")) {
        return
    }
    $versionOutput = & $wixPath --version 2>&1
    $m = [System.Text.RegularExpressions.Regex]::Match(($versionOutput -join "`n"), "\d+\.\d+\.\d+")
    $uiRef = "WixToolset.UI.wixext"
    if ($m.Success) {
        $uiRef = ("WixToolset.UI.wixext/" + $m.Value)
    }
    & $wixPath extension add -g $uiRef
    if ($LASTEXITCODE -ne 0) {
        throw ("Failed to add WiX UI extension (" + $uiRef + ").")
    }
}

function Get-RelativePathNormalized([string]$basePath, [string]$fullPath) {
    $base = [System.IO.Path]::GetFullPath($basePath)
    if (-not $base.EndsWith("\")) { $base += "\" }
    $target = [System.IO.Path]::GetFullPath($fullPath)
    $baseUri = New-Object System.Uri($base)
    $targetUri = New-Object System.Uri($target)
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    $relative = [System.Uri]::UnescapeDataString($relative)
    return ($relative -replace "\\", "/")
}

function Get-DirectoryIdMap([string[]]$relativeDirs) {
    $map = @{}
    $map[""] = "INSTALLFOLDER"
    $counter = 1
    foreach ($dir in ($relativeDirs | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $normalized = ($dir -replace "\\", "/").Trim("/")
        $parts = $normalized.Split("/")
        $current = ""
        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            if ([string]::IsNullOrWhiteSpace($current)) {
                $current = $part
            } else {
                $current = $current + "/" + $part
            }
            if (-not $map.ContainsKey($current)) {
                $map[$current] = ("DIR{0}" -f $counter.ToString("0000"))
                $counter++
            }
        }
    }
    return $map
}

function Get-ParentRelativeDirectory([string]$relativePath) {
    $norm = ($relativePath -replace "\\", "/").Trim("/")
    $idx = $norm.LastIndexOf("/")
    if ($idx -lt 0) { return "" }
    return $norm.Substring(0, $idx)
}

function Render-DirectoryTree([hashtable]$dirIdMap) {
    $children = @{}
    foreach ($k in $dirIdMap.Keys) {
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        $parent = ""
        $name = $k
        $idx = $k.LastIndexOf("/")
        if ($idx -ge 0) {
            $parent = $k.Substring(0, $idx)
            $name = $k.Substring($idx + 1)
        }
        if (-not $children.ContainsKey($parent)) {
            $children[$parent] = New-Object System.Collections.Generic.List[string]
        }
        $children[$parent].Add($k)
    }

    $sb = New-Object System.Text.StringBuilder

    function Write-Node([string]$parentKey, [int]$level) {
        if (-not $children.ContainsKey($parentKey)) { return }
        $indent = ("  " * $level)
        $sorted = $children[$parentKey] | Sort-Object
        foreach ($childKey in $sorted) {
            $id = $dirIdMap[$childKey]
            $name = $childKey.Substring($childKey.LastIndexOf("/") + 1)
            [void]$sb.AppendLine(($indent + "<Directory Id=`"" + (Escape-Xml $id) + "`" Name=`"" + (Escape-Xml $name) + "`">"))
            Write-Node -parentKey $childKey -level ($level + 1)
            [void]$sb.AppendLine(($indent + "</Directory>"))
        }
    }

    Write-Node -parentKey "" -level 3
    return $sb.ToString()
}

if ($CleanOutput) {
    Clear-OutputArtifacts -outputDir $OutputDir
}

if (-not $SkipBuildPackage) {
    $buildPackageArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $buildPackageScript,
        "-Configuration", $Configuration,
        "-OutputDir", $OutputDir
    )
    if ($RequireWintun) { $buildPackageArgs += "-RequireWintun" }
    if ($AutoCopyWintun -or -not $SkipCopyWintun) { $buildPackageArgs += "-AutoCopyWintun" }
    if ($SkipCopyWintun) { $buildPackageArgs += "-SkipCopyWintun" }
    if ($FrameworkDependent) { $buildPackageArgs += "-FrameworkDependent" }
    if (-not $SkipVerifyPackage) { $buildPackageArgs += "-VerifyPackage" }
    if (-not [string]::IsNullOrWhiteSpace($VerifyReportPath)) { $buildPackageArgs += @("-VerifyReportPath", $VerifyReportPath) }
    if (-not [string]::IsNullOrWhiteSpace($RuntimeIdentifier)) { $buildPackageArgs += @("-RuntimeIdentifier", $RuntimeIdentifier) }
    if (-not [string]::IsNullOrWhiteSpace($WintunSourcePath)) { $buildPackageArgs += @("-WintunSourcePath", $WintunSourcePath) }

    & powershell @buildPackageArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build-Package.ps1 failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path $packageRoot)) {
    throw "Package staging directory missing: $packageRoot"
}

$files = Get-ChildItem -Path $packageRoot -File -Recurse | Sort-Object FullName
if ($files.Count -eq 0) {
    throw "No files found in package staging directory: $packageRoot"
}

$relativeDirs = @()
foreach ($f in $files) {
    $rel = Get-RelativePathNormalized -basePath $packageRoot -fullPath $f.FullName
    $dir = Get-ParentRelativeDirectory -relativePath $rel
    $relativeDirs += $dir
}
$dirIdMap = Get-DirectoryIdMap -relativeDirs $relativeDirs
$directoryTreeXml = Render-DirectoryTree -dirIdMap $dirIdMap

$componentSb = New-Object System.Text.StringBuilder
$index = 1
$shortcutWritten = $false
foreach ($f in $files) {
    $rel = Get-RelativePathNormalized -basePath $packageRoot -fullPath $f.FullName
    $relNorm = ($rel -replace "\\", "/")
    $dir = Get-ParentRelativeDirectory -relativePath $relNorm
    $dirId = $dirIdMap[$dir]
    $cmpId = New-ComponentId -index $index
    $fileId = New-FileId -index $index

    [void]$componentSb.AppendLine(('      <Component Id="{0}" Directory="{1}" Guid="*">' -f $cmpId, $dirId))
    [void]$componentSb.AppendLine(('        <File Id="{0}" Source="{1}" KeyPath="yes">' -f $fileId, (Escape-Xml $f.FullName)))

    if (-not $shortcutWritten -and $relNorm -ieq "app/OpenMeshWin.exe") {
        [void]$componentSb.AppendLine('          <Shortcut Id="StartMenuShortcut" Directory="ProgramMenuFolder" Name="OpenMeshWin" WorkingDirectory="INSTALLFOLDER" Advertise="no" Icon="AppIcon" />')
        [void]$componentSb.AppendLine('          <Shortcut Id="DesktopShortcut" Directory="DesktopFolder" Name="OpenMeshWin" WorkingDirectory="INSTALLFOLDER" Advertise="no" Icon="AppIcon" />')
        $shortcutWritten = $true
    }

    [void]$componentSb.AppendLine("        </File>")
    [void]$componentSb.AppendLine("      </Component>")
    $index++
}

$msiVersion = Normalize-MsiVersion $Version
$wixPath = Resolve-Wix4Path
Ensure-WixUiExtension -wixPath $wixPath

New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
if (Test-Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$wxsPath = Join-Path $tempRoot "OpenMeshWin.InstallFiles.wxs"
$msiPath = Join-Path $OutputDir ("OpenMeshWin-" + $Version + ".msi")
if (Test-Path $msiPath) { Remove-Item -Path $msiPath -Force }

$escapedProductName = Escape-Xml $ProductName
$escapedManufacturer = Escape-Xml $Manufacturer
$iconSource = Join-Path $packageRoot "app\assets\meshflux\logo.ico"
if (-not (Test-Path $iconSource)) {
    $iconSource = Join-Path $scriptRoot "..\assets\meshflux\logo.ico"
}
if (-not (Test-Path $iconSource)) {
    throw "App icon file not found for MSI branding."
}
$iconSource = (Resolve-Path $iconSource).Path
$escapedIconSource = Escape-Xml $iconSource

$wxs = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"
     xmlns:ui="http://wixtoolset.org/schemas/v4/wxs/ui">
  <Package Name="$escapedProductName" Manufacturer="$escapedManufacturer" Version="$msiVersion" UpgradeCode="$UpgradeCode" Language="1033">
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <Icon Id="AppIcon" SourceFile="$escapedIconSource" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="$escapedProductName" />
    </StandardDirectory>
    <StandardDirectory Id="ProgramMenuFolder" />
    <StandardDirectory Id="DesktopFolder" />

    <ui:WixUI Id="WixUI_InstallDir" InstallDirectory="INSTALLFOLDER" />

    <Feature Id="MainFeature" Title="$escapedProductName" Level="1">
      <ComponentGroupRef Id="MainComponents" />
    </Feature>
  </Package>

  <Fragment>
    <DirectoryRef Id="INSTALLFOLDER">
$directoryTreeXml    </DirectoryRef>
  </Fragment>

  <Fragment>
    <ComponentGroup Id="MainComponents">
$($componentSb.ToString())    </ComponentGroup>
  </Fragment>
</Wix>
"@

$wxs | Set-Content -Path $wxsPath -Encoding UTF8

& $wixPath build $wxsPath -arch x64 -ext WixToolset.UI.wixext -o $msiPath
if ($LASTEXITCODE -ne 0) {
    throw "wix build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $msiPath)) {
    throw "MSI output missing: $msiPath"
}

Write-Host "WiX toolchain: wix"
Write-Host ("MSI generated: " + $msiPath)
Write-Host ("Installed file count: " + $files.Count)
