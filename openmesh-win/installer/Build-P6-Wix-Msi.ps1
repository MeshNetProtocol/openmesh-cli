param(
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0",
    [string]$OutputDir = "",
    [string]$ProductName = "OpenMeshWin",
    [string]$Manufacturer = "OpenMesh",
    [string]$UpgradeCode = "F2B44A4B-893A-4B8D-ABAE-2C5CECB60C2A",
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
$tempRoot = Join-Path $scriptRoot "staging\wix"
$packageZip = Join-Path $OutputDir ("OpenMeshWin-" + $Configuration + ".zip")

function Resolve-WixToolchain {
    $wix = Get-Command wix -ErrorAction SilentlyContinue
    if ($null -ne $wix -and -not [string]::IsNullOrWhiteSpace($wix.Source) -and (Test-Path $wix.Source)) {
        return [pscustomobject]@{
            Type = "wix4"
            WixPath = (Resolve-Path $wix.Source).Path
            CandlePath = $null
            LightPath = $null
        }
    }

    $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
    $light = Get-Command light.exe -ErrorAction SilentlyContinue
    if ($null -ne $candle -and $null -ne $light -and (Test-Path $candle.Source) -and (Test-Path $light.Source)) {
        return [pscustomobject]@{
            Type = "wix3"
            WixPath = $null
            CandlePath = (Resolve-Path $candle.Source).Path
            LightPath = (Resolve-Path $light.Source).Path
        }
    }

    return $null
}

function Normalize-MsiVersion([string]$rawVersion) {
    $matches = [System.Text.RegularExpressions.Regex]::Matches($rawVersion, "\d+")
    $parts = New-Object System.Collections.Generic.List[int]
    foreach ($m in $matches) {
        if ($parts.Count -ge 3) {
            break
        }
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

if (-not $SkipBuildPackage) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildPackageScript -Configuration $Configuration -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "Build-Package.ps1 failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path $packageZip)) {
    throw "Package zip missing: $packageZip"
}

$wixToolchain = Resolve-WixToolchain
if ($null -eq $wixToolchain) {
    throw "WiX toolset not found. Install WiX v4 (wix) or WiX v3 (candle/light)."
}

$msiVersion = Normalize-MsiVersion $Version
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force
}
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$wxsPath = Join-Path $tempRoot "OpenMeshWin.Package.wxs"
$msiPath = Join-Path $OutputDir ("OpenMeshWin-" + $Version + ".msi")
if (Test-Path $msiPath) {
    Remove-Item -Path $msiPath -Force
}

$escapedPayload = [System.Security.SecurityElement]::Escape($packageZip)
$escapedProductName = [System.Security.SecurityElement]::Escape($ProductName)
$escapedManufacturer = [System.Security.SecurityElement]::Escape($Manufacturer)

if ($wixToolchain.Type -eq "wix4") {
    $wxs = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="$escapedProductName" Manufacturer="$escapedManufacturer" Version="$msiVersion" UpgradeCode="$UpgradeCode" Language="1033">
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="$escapedProductName">
        <Directory Id="PAYLOADFOLDER" Name="payload">
          <Component Id="cmpPayloadZip" Guid="*">
            <File Id="filPayloadZip" Source="$escapedPayload" KeyPath="yes" />
          </Component>
        </Directory>
      </Directory>
    </StandardDirectory>
    <Feature Id="MainFeature" Title="$escapedProductName" Level="1">
      <ComponentRef Id="cmpPayloadZip" />
    </Feature>
  </Package>
</Wix>
"@
    $wxs | Set-Content -Path $wxsPath -Encoding UTF8

    & $wixToolchain.WixPath build $wxsPath -arch x64 -o $msiPath
    if ($LASTEXITCODE -ne 0) {
        throw "wix build failed with exit code $LASTEXITCODE."
    }
} else {
    $wxs = @"
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="$escapedProductName" Language="1033" Version="$msiVersion" Manufacturer="$escapedManufacturer" UpgradeCode="$UpgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="$escapedProductName">
          <Directory Id="PAYLOADFOLDER" Name="payload">
            <Component Id="cmpPayloadZip" Guid="*">
              <File Id="filPayloadZip" Source="$escapedPayload" KeyPath="yes" />
            </Component>
          </Directory>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="MainFeature" Title="$escapedProductName" Level="1">
      <ComponentRef Id="cmpPayloadZip" />
    </Feature>
  </Product>
</Wix>
"@
    $wxs | Set-Content -Path $wxsPath -Encoding UTF8

    $wixObj = Join-Path $tempRoot "OpenMeshWin.Package.wixobj"
    & $wixToolchain.CandlePath -nologo -out $wixObj $wxsPath
    if ($LASTEXITCODE -ne 0) {
        throw "candle.exe failed with exit code $LASTEXITCODE."
    }
    & $wixToolchain.LightPath -nologo -out $msiPath $wixObj
    if ($LASTEXITCODE -ne 0) {
        throw "light.exe failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path $msiPath)) {
    throw "MSI output missing: $msiPath"
}

Write-Host ("WiX toolchain: " + $wixToolchain.Type)
Write-Host ("MSI generated: " + $msiPath)
