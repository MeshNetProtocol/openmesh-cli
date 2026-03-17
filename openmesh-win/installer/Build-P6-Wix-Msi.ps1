param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0",
    [string]$OutputDir = "",
    [string]$ProductName = "meshflux",
    [string]$Manufacturer = "OpenMesh",
    [string]$UpgradeCode = "F2B44A4B-893A-4B8D-ABAE-2C5CECB60C2A",
    [string]$BundleUpgradeCode = "6F2E2A93-7D33-4FB2-B05F-7B76509EF67F",
    [switch]$RequireWintun,
    [switch]$AutoCopyWintun,
    [switch]$SkipCopyWintun,
    [switch]$FrameworkDependent,
    [switch]$UseBuildOutputForApp,
    [switch]$SkipVerifyPackage,
    [string]$VerifyReportPath = "",
    [switch]$CleanOutput,
    [string]$RuntimeIdentifier = "win-x64",
    [string]$WintunSourcePath = "",
    [switch]$SkipBuildPackage,
    [switch]$SkipBuildBundle,
    [switch]$BuildBundle,
    [string]$DotnetDesktopRuntimeInstallerPath = "",
    [string]$DotnetDesktopRuntimeDownloadUrl = "https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe",
    [string]$DotnetDesktopRuntimeMinVersion = "10.0.0"
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
$buildStatePath = Join-Path $scriptRoot ".build-state.json"
$packageManifestPath = Join-Path $packageRoot "build-manifest.json"

function Get-FileSha256([string]$path) {
    if (-not (Test-Path $path)) {
        throw "File not found for hashing: $path"
    }
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Clear-OutputArtifacts([string]$outputDir) {
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        return
    }

    Get-ChildItem -Path $outputDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
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

function Read-BuildState([string]$statePath) {
    if (-not (Test-Path $statePath)) { return $null }
    try {
        $raw = Get-Content -Raw -Path $statePath -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Write-BuildState([string]$statePath, [string]$msiVersion) {
    $state = [pscustomobject]@{
        LastMsiVersion = $msiVersion
        UpdatedAt = (Get-Date).ToString("s")
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
}

function Get-NextBuildVersion([string]$requestedVersion, [string]$statePath) {
    $requested = Normalize-MsiVersion $requestedVersion
    $reqParts = $requested.Split(".") | ForEach-Object { [int]$_ }

    $state = Read-BuildState $statePath
    if ($null -eq $state -or [string]::IsNullOrWhiteSpace($state.LastMsiVersion)) {
        Write-BuildState -statePath $statePath -msiVersion $requested
        return $requested
    }

    $last = Normalize-MsiVersion ([string]$state.LastMsiVersion)
    $lastParts = $last.Split(".") | ForEach-Object { [int]$_ }

    if ($lastParts[0] -eq $reqParts[0] -and $lastParts[1] -eq $reqParts[1]) {
        $nextPatch = [Math]::Min($lastParts[2] + 1, 65535)
        $next = ("{0}.{1}.{2}" -f $lastParts[0], $lastParts[1], $nextPatch)
        Write-BuildState -statePath $statePath -msiVersion $next
        return $next
    }

    Write-BuildState -statePath $statePath -msiVersion $requested
    return $requested
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

function Ensure-WixExtension([string]$wixPath, [string]$extensionId) {
    $listOutput = & $wixPath extension list -g 2>&1
    if ($LASTEXITCODE -eq 0) {
        $lines = ($listOutput -join "`n") -split "`r?`n"
        $match = $lines | Where-Object { $_ -match ("^" + [Regex]::Escape($extensionId) + "\\b") } | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($match)) {
            if ($match -notmatch "\\(damaged\\)") {
                return
            }
            & $wixPath extension remove -g $extensionId | Out-Null
        }
    }

    $versionOutput = & $wixPath --version 2>&1
    $m = [System.Text.RegularExpressions.Regex]::Match(($versionOutput -join "`n"), "\d+\.\d+\.\d+")
    $ref = $extensionId
    if ($m.Success) {
        $ref = ($extensionId + "/" + $m.Value)
    }

    & $wixPath extension add -g $ref
    if ($LASTEXITCODE -ne 0) {
        throw ("Failed to add WiX extension (" + $ref + ").")
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

# Always clear output to avoid stale MSIs/zips causing confusion.
Clear-OutputArtifacts -outputDir $OutputDir

# Auto-increment patch version across runs (state is kept outside installer/output).
$Version = Get-NextBuildVersion -requestedVersion $Version -statePath $buildStatePath

if (-not $SkipBuildPackage) {
    $buildPackageArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $buildPackageScript,
        "-Configuration", $Configuration,
        "-OutputDir", $OutputDir,
        "-ProductName", $ProductName,
        "-SkipZip"
    )
    if ($RequireWintun) { $buildPackageArgs += "-RequireWintun" }
    if ($AutoCopyWintun -or -not $SkipCopyWintun) { $buildPackageArgs += "-AutoCopyWintun" }
    if ($SkipCopyWintun) { $buildPackageArgs += "-SkipCopyWintun" }
    if ($FrameworkDependent) { $buildPackageArgs += "-FrameworkDependent" }
    if ($UseBuildOutputForApp) { $buildPackageArgs += "-UseBuildOutputForApp" }
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

if (-not (Test-Path $packageManifestPath)) {
    throw "Package build manifest missing: $packageManifestPath"
}

$packageManifest = Get-Content -Raw -Path $packageManifestPath | ConvertFrom-Json -ErrorAction Stop
$stagedAppCoreDll = Join-Path $packageRoot "app\libs\openmesh_core.dll"
$stagedCoreCoreDll = Join-Path $packageRoot "core\openmesh_core.dll"
$stagedAppPthreadDll = Join-Path $packageRoot "app\libs\libwinpthread-1.dll"
$stagedCorePthreadDll = Join-Path $packageRoot "core\libwinpthread-1.dll"
$stagedAppExe = Join-Path $packageRoot "app\meshflux.exe"
$stagedAppDll = Join-Path $packageRoot "app\meshflux.dll"
$stagedCoreExe = Join-Path $packageRoot "core\OpenMeshWin.Core.exe"
$stagedCoreDll = Join-Path $packageRoot "core\OpenMeshWin.Core.dll"

$expectedCoreHash = [string]$packageManifest.Native.OpenMeshCoreSha256
$expectedPthreadHash = [string]$packageManifest.Native.LibwinpthreadSha256
if ([string]::IsNullOrWhiteSpace($expectedCoreHash) -or [string]::IsNullOrWhiteSpace($expectedPthreadHash)) {
    throw "Package build manifest is missing required native DLL hashes."
}

$expectedAppExeHash = [string]$packageManifest.App.MeshfluxExe.Sha256
$expectedAppDllHash = [string]$packageManifest.App.MeshfluxDll.Sha256
$expectedCoreExeHash = [string]$packageManifest.Core.OpenMeshWinCoreExe.Sha256
$expectedCoreDllHash = [string]$packageManifest.Core.OpenMeshWinCoreDll.Sha256

if ([string]::IsNullOrWhiteSpace($expectedAppExeHash) -or
    [string]::IsNullOrWhiteSpace($expectedAppDllHash) -or
    [string]::IsNullOrWhiteSpace($expectedCoreExeHash) -or
    [string]::IsNullOrWhiteSpace($expectedCoreDllHash)) {
    throw "Package build manifest is missing required managed binary hashes."
}

$actualAppCoreHash = Get-FileSha256 $stagedAppCoreDll
$actualCoreCoreHash = Get-FileSha256 $stagedCoreCoreDll
$actualAppPthreadHash = Get-FileSha256 $stagedAppPthreadDll
$actualCorePthreadHash = Get-FileSha256 $stagedCorePthreadDll

if ($expectedCoreHash -ne $actualAppCoreHash -or $expectedCoreHash -ne $actualCoreCoreHash) {
    throw "Staged openmesh_core.dll hash mismatch before MSI build. expected=$expectedCoreHash app=$actualAppCoreHash core=$actualCoreCoreHash"
}
if ($expectedPthreadHash -ne $actualAppPthreadHash -or $expectedPthreadHash -ne $actualCorePthreadHash) {
    throw "Staged libwinpthread-1.dll hash mismatch before MSI build. expected=$expectedPthreadHash app=$actualAppPthreadHash core=$actualCorePthreadHash"
}

$actualAppExeHash = Get-FileSha256 $stagedAppExe
$actualAppDllHash = Get-FileSha256 $stagedAppDll
$actualCoreExeHash = Get-FileSha256 $stagedCoreExe
$actualCoreDllHash = Get-FileSha256 $stagedCoreDll

if ($expectedAppExeHash -ne $actualAppExeHash) {
    throw "Staged meshflux.exe hash mismatch before MSI build. expected=$expectedAppExeHash actual=$actualAppExeHash"
}
if ($expectedAppDllHash -ne $actualAppDllHash) {
    throw "Staged meshflux.dll hash mismatch before MSI build. expected=$expectedAppDllHash actual=$actualAppDllHash"
}
if ($expectedCoreExeHash -ne $actualCoreExeHash) {
    throw "Staged OpenMeshWin.Core.exe hash mismatch before MSI build. expected=$expectedCoreExeHash actual=$actualCoreExeHash"
}
if ($expectedCoreDllHash -ne $actualCoreDllHash) {
    throw "Staged OpenMeshWin.Core.dll hash mismatch before MSI build. expected=$expectedCoreDllHash actual=$actualCoreDllHash"
}

if ($packageManifest.Native.PSObject.Properties.Name -contains "WintunSha256") {
    $expectedWintunHash = [string]$packageManifest.Native.WintunSha256
    $stagedAppWintunDll = Join-Path $packageRoot "app\deps\wintun\wintun.dll"
    $stagedCoreWintunDll = Join-Path $packageRoot "core\wintun.dll"
    $actualAppWintunHash = Get-FileSha256 $stagedAppWintunDll
    $actualCoreWintunHash = Get-FileSha256 $stagedCoreWintunDll
    if ($expectedWintunHash -ne $actualAppWintunHash -or $expectedWintunHash -ne $actualCoreWintunHash) {
        throw "Staged wintun.dll hash mismatch before MSI build. expected=$expectedWintunHash app=$actualAppWintunHash core=$actualCoreWintunHash"
    }
}

Write-Host ("Native DLL source: " + $packageManifest.Native.OpenMeshCoreSourcePath)
Write-Host ("Native DLL hash:   " + $expectedCoreHash)
Write-Host ("App DLL hash:      " + $expectedAppDllHash)

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

    if (-not $shortcutWritten -and $relNorm -ieq "app/meshflux.exe") {
        [void]$componentSb.AppendLine(('          <Shortcut Id="StartMenuShortcut" Directory="ProgramMenuFolder" Name="{0}" WorkingDirectory="INSTALLFOLDER" Advertise="no" Icon="AppIcon" />' -f (Escape-Xml $ProductName)))
        [void]$componentSb.AppendLine(('          <Shortcut Id="DesktopShortcut" Directory="DesktopFolder" Name="{0}" WorkingDirectory="INSTALLFOLDER" Advertise="no" Icon="AppIcon" />' -f (Escape-Xml $ProductName)))
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

$artifactPrefix = ($ProductName -replace "[^A-Za-z0-9._-]", "")
if ([string]::IsNullOrWhiteSpace($artifactPrefix)) { $artifactPrefix = "meshflux" }

$wxsPath = Join-Path $tempRoot "OpenMeshWin.InstallFiles.wxs"
$msiPath = Join-Path $OutputDir ($artifactPrefix + "-" + $Version + ".msi")
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
  <Package Name="$escapedProductName" Manufacturer="$escapedManufacturer" Version="$msiVersion" UpgradeCode="$UpgradeCode" Language="1033" ShortNames="no">
    <!-- MajorUpgrade handles the underlying removal logic: automatically removes previous version before installing new one -->
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    
    <MediaTemplate EmbedCab="yes" />
    <Icon Id="AppIcon" SourceFile="$escapedIconSource" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />

    <!-- Detect previous versions to show "Update" context in UI -->
    <Property Id="PREVIOUSFOUND" Secure="yes" />
    <Upgrade Id="$UpgradeCode">
      <UpgradeVersion Minimum="0.0.0" Maximum="99.9.9" Property="PREVIOUSFOUND" IncludeMinimum="yes" IncludeMaximum="yes" OnlyDetect="yes" />
    </Upgrade>

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="$escapedProductName" />
    </StandardDirectory>
    <StandardDirectory Id="ProgramMenuFolder" />
    <StandardDirectory Id="DesktopFolder" />

    <ui:WixUI Id="WixUI_InstallDir" InstallDirectory="INSTALLFOLDER" />
    
    <!-- UI Customization: If PREVIOUSFOUND is set, we change the welcome text -->
    <SetProperty Id="WIXUI_WELCOME_TITLE" Value="Welcome to the $escapedProductName Upgrade Wizard" After="AppSearch" Condition="PREVIOUSFOUND" />
    <SetProperty Id="WIXUI_WELCOME_DESCRIPTION" Value="The installer will update your existing version of $escapedProductName to $msiVersion." After="AppSearch" Condition="PREVIOUSFOUND" />

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

$wixObjDir = Join-Path $tempRoot "obj"
New-Item -Path $wixObjDir -ItemType Directory -Force | Out-Null

& $wixPath build $wxsPath -arch x64 -ext WixToolset.UI.wixext -pdbtype none -intermediateFolder $wixObjDir -o $msiPath
if ($LASTEXITCODE -ne 0) {
    throw "wix build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $msiPath)) {
    throw "MSI output missing: $msiPath"
}

Write-Host "WiX toolchain: wix"
Write-Host ("MSI generated: " + $msiPath)
Write-Host ("Installed file count: " + $files.Count)
Write-Host ("Build state: " + $buildStatePath)

$shouldBuildBundle = $BuildBundle.IsPresent -and -not $SkipBuildBundle.IsPresent
if ($shouldBuildBundle) {
    # Bundle build uses Burn + helper searches (Util).
    Ensure-WixExtension -wixPath $wixPath -extensionId "WixToolset.Util.wixext"
    Ensure-WixExtension -wixPath $wixPath -extensionId "WixToolset.BootstrapperApplications.wixext"

    $bundleWxsPath = Join-Path $tempRoot "OpenMeshWin.Bundle.wxs"
    $bundlePath = Join-Path $OutputDir ($artifactPrefix + "-" + $Version + ".exe")
    if (Test-Path $bundlePath) { Remove-Item -Path $bundlePath -Force }

    $escapedMsiPath = Escape-Xml ((Resolve-Path $msiPath).Path)
    $escapedDotnetUrl = Escape-Xml $DotnetDesktopRuntimeDownloadUrl
    $escapedMinVersion = Escape-Xml (Normalize-MsiVersion $DotnetDesktopRuntimeMinVersion)
    $escapedDotnetInstallerPath = ""

    if ($FrameworkDependent.IsPresent) {
        $dotnetInstallerPath = ""
        if (-not [string]::IsNullOrWhiteSpace($DotnetDesktopRuntimeInstallerPath)) {
            if (-not (Test-Path $DotnetDesktopRuntimeInstallerPath)) {
                throw "DotnetDesktopRuntimeInstallerPath not found: $DotnetDesktopRuntimeInstallerPath"
            }
            $dotnetInstallerPath = (Resolve-Path $DotnetDesktopRuntimeInstallerPath).Path
        }
        else {
            $cacheDir = Join-Path $scriptRoot ".cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $dotnetInstallerPath = Join-Path $cacheDir "windowsdesktop-runtime-win-x64.exe"
            if (-not (Test-Path $dotnetInstallerPath)) {
                Write-Host ("Downloading .NET Desktop Runtime installer: " + $DotnetDesktopRuntimeDownloadUrl)
                Invoke-WebRequest -Uri $DotnetDesktopRuntimeDownloadUrl -OutFile $dotnetInstallerPath -UseBasicParsing
            }
            $dotnetInstallerPath = (Resolve-Path $dotnetInstallerPath).Path
        }

        $escapedDotnetInstallerPath = Escape-Xml $dotnetInstallerPath
    }

    # WixPrereqBootstrapperApplication is shipped as an embedded wixlib inside the extension DLL.
    # Extract it into the staging folder and link it via -lib so the BA is available at link time.
    $baWixlibPath = Join-Path $tempRoot "WixToolset.BootstrapperApplications.bas.wixlib"
    $baExtensionDll = Get-ChildItem -Path (Join-Path $env:USERPROFILE ".wix\\extensions\\WixToolset.BootstrapperApplications.wixext") -Recurse -Force -Filter "WixToolset.BootstrapperApplications.wixext.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $baExtensionDll -or -not (Test-Path $baExtensionDll.FullName)) {
        throw "BootstrapperApplications extension DLL not found in user cache."
    }
    $baAsm = [System.Reflection.Assembly]::LoadFile($baExtensionDll.FullName)
    $baStream = $baAsm.GetManifestResourceStream("WixToolset.BootstrapperApplications.bas.wixlib")
    if ($null -eq $baStream) {
        throw "Embedded bootstrapper wixlib not found in extension assembly."
    }
    try {
        $fs = [System.IO.File]::Open($baWixlibPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try { $baStream.CopyTo($fs) } finally { $fs.Dispose() }
    }
    finally {
        $baStream.Dispose()
    }

    $dotnetChainXml = ""
    if ($FrameworkDependent.IsPresent) {
        $dotnetChainXml = @"
      <ExePackage Id="DotNetDesktopRuntime10"
                  DisplayName="Microsoft .NET 10 Desktop Runtime (x64)"
                  SourceFile="$escapedDotnetInstallerPath"
                  Cache="keep"
                  PerMachine="yes"
                  Vital="yes"
                  Permanent="yes"
                  InstallArguments="/install /quiet /norestart"
                  RepairArguments="/repair /quiet /norestart"
                  UninstallArguments="/uninstall /quiet /norestart"
                  DetectCondition="(DOTNET_DESKTOP_KEY = 1 AND DOTNET_HOSTFXR_VER &gt;= v$escapedMinVersion) OR (DOTNET_DESKTOP_KEY_WOW = 1 AND DOTNET_HOSTFXR_VER_WOW &gt;= v$escapedMinVersion)" />

"@
    }

    $bundleWxs = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"
     xmlns:util="http://wixtoolset.org/schemas/v4/wxs/util">
  <Bundle Name="$escapedProductName"
          Manufacturer="$escapedManufacturer"
          Version="$msiVersion"
          UpgradeCode="$BundleUpgradeCode"
          IconSourceFile="$escapedIconSource">
    <BootstrapperApplicationRef Id="WixPrereqBootstrapperApplication.Primary_X64" />

    <Chain>
$dotnetChainXml      <MsiPackage Id="OpenMeshWinMsi"
                  SourceFile="$escapedMsiPath"
                  DisplayName="$escapedProductName"
                  Vital="yes" />
    </Chain>
  </Bundle>

  <Fragment>
    <util:RegistrySearch Root="HKLM" Key="SOFTWARE\dotnet\Setup\InstalledVersions\x64\hostfxr" Value="Version" Variable="DOTNET_HOSTFXR_VER" />
    <util:RegistrySearch Root="HKLM" Key="SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App" Result="exists" Variable="DOTNET_DESKTOP_KEY" />
    <util:RegistrySearch Root="HKLM" Key="SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\hostfxr" Value="Version" Variable="DOTNET_HOSTFXR_VER_WOW" />
    <util:RegistrySearch Root="HKLM" Key="SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App" Result="exists" Variable="DOTNET_DESKTOP_KEY_WOW" />
  </Fragment>
</Wix>
"@

    $bundleWxs | Set-Content -Path $bundleWxsPath -Encoding UTF8

    & $wixPath build $bundleWxsPath -arch x64 -lib $baWixlibPath -ext WixToolset.Util.wixext -o $bundlePath
    if ($LASTEXITCODE -ne 0) {
        throw "wix bundle build failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path $bundlePath)) {
        throw "Bundle output missing: $bundlePath"
    }

    Write-Host ("Bundle generated: " + $bundlePath)
}

# Keep installer/output clean: by default only the final MSI is needed.
$keepSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path $msiPath) { [void]$keepSet.Add((Resolve-Path $msiPath).Path) }
if ($shouldBuildBundle -and (Test-Path $bundlePath)) { [void]$keepSet.Add((Resolve-Path $bundlePath).Path) }

Get-ChildItem -Path $OutputDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        if ($_.PSIsContainer) {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        if (-not $keepSet.Contains($_.FullName)) {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Best-effort cleanup, do not fail build due to cleanup.
    }
}
