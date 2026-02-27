param(
    [string]$GoCoreExePath = "",
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path
$buildScript = Join-Path $repoRoot "openmesh-win\tests\Build-P1-GoCore.ps1"

function Resolve-GoCorePath([string]$explicitPath) {
    if (-not [string]::IsNullOrWhiteSpace($explicitPath) -and (Test-Path $explicitPath)) {
        return (Resolve-Path $explicitPath).Path
    }
    $envPath = $env:OPENMESH_WIN_GO_CORE_EXE
    if (-not [string]::IsNullOrWhiteSpace($envPath) -and (Test-Path $envPath)) {
        return (Resolve-Path $envPath).Path
    }
    $candidates = @(
        (Join-Path $repoRoot "go-cli-lib\cmd\openmesh-win-core\openmesh-win-core.exe"),
        (Join-Path $repoRoot "go-cli-lib\bin\openmesh-win-core.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Stop-ConflictingProcesses {
    $targets = New-Object System.Collections.Generic.List[object]
    $processes = Get-CimInstance Win32_Process
    foreach ($p in $processes) {
        $nameText = if ($null -eq $p.Name) { "" } else { [string]$p.Name }
        $name = $nameText.ToLowerInvariant()
        if ($name -eq "openmeshwin.exe" -or $name -eq "openmeshwin.core.exe" -or $name -eq "openmesh-win-core.exe") {
            $targets.Add($p)
            continue
        }
        if ($name -eq "dotnet.exe") {
            $cmdText = if ($null -eq $p.CommandLine) { "" } else { [string]$p.CommandLine }
            if ($cmdText.ToLowerInvariant().Contains("openmeshwin.core.dll")) {
                $targets.Add($p)
            }
        }
    }
    if ($targets.Count -eq 0) {
        Write-Host "No conflicting OpenMesh processes found."
        return
    }
    Write-Host ("Stopping {0} conflicting process(es)..." -f $targets.Count)
    foreach ($target in $targets) {
        try {
            Stop-Process -Id ([int]$target.ProcessId) -Force -ErrorAction Stop
            Write-Host ("Stopped PID={0} Name={1}" -f $target.ProcessId, $target.Name)
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -like "*Cannot find a process*") {
                continue
            }
            Write-Warning ("Failed to stop PID={0} Name={1}: {2}" -f $target.ProcessId, $target.Name, $msg)
        }
    }
    Start-Sleep -Milliseconds 500
}

function Invoke-Core([hashtable]$payload) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'openmesh-win-core', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(2500)
    try {
        $writer = [System.IO.StreamWriter]::new($pipe, [System.Text.UTF8Encoding]::new($false), 1024, $true)
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8, $false, 1024, $true)
        $writer.WriteLine(($payload | ConvertTo-Json -Compress))
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { throw "empty response" }
        return ($line | ConvertFrom-Json)
    }
    finally {
        $pipe.Dispose()
    }
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Sanitize-ProviderId([string]$providerId) {
    $safe = $providerId.Trim().ToLowerInvariant()
    $safe = $safe.Replace(" ", "-").Replace("/", "-").Replace("\", "-")
    return $safe
}

function New-UpgradeMarketJson([string]$providerId, [double]$pricePerGb, [string]$packageHash) {
    $providerIdValue = if ($null -eq $providerId) { "" } else { $providerId }
    $hashValue = if ($null -eq $packageHash) { "" } else { $packageHash }
    $safeProviderId = $providerIdValue.Replace('"', '\"')
    $safeHash = $hashValue.Replace('"', '\"')
    $priceText = $pricePerGb.ToString("0.000000", [System.Globalization.CultureInfo]::InvariantCulture)
@"
{
  "providers": [
    {
      "id": "$safeProviderId",
      "name": "Upgrade Test Provider",
      "region": "upgrade-test",
      "pricePerGb": $priceText,
      "packageHash": "$safeHash",
      "description": "provider upgrade smoke test payload"
    }
  ]
}
"@
}

function Start-GoCoreAndWait([string]$exePath) {
    $proc = Start-Process -FilePath $exePath -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 40; $i++) {
        if ($proc.HasExited) {
            throw "go core exited early with code $($proc.ExitCode)"
        }
        try {
            $pong = Invoke-Core @{ action = "ping" }
            if ($pong.ok) {
                return $proc
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 200
    }
    throw "go core pipe did not become ready in time"
}

function Get-FreeTcpPort {
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcp.Start()
    $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
    $tcp.Stop()
    return $port
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript
if ($LASTEXITCODE -ne 0) {
    throw "Build-P1-GoCore.ps1 failed with exit code $LASTEXITCODE"
}

$resolvedGoCore = Resolve-GoCorePath -explicitPath $GoCoreExePath
if ($null -eq $resolvedGoCore) {
    throw "Cannot find openmesh-win-core.exe after build."
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses
}

$proc = $null
$tempImportPath = $null
try {
    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $marketResp = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketResp.ok) -message ("provider_market_list failed: " + [string]$marketResp.message)
    Assert-True -condition ($marketResp.providers.Count -gt 0) -message "provider_market_list should return at least one provider"

    $providerId = [string]$marketResp.providers[0].id
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace($providerId)) -message "provider id is empty"

    $unknownInstallResp = Invoke-Core @{
        action = "provider_install"
        providerId = "unknown-provider-id"
    }
    Assert-True -condition (-not [bool]$unknownInstallResp.ok) -message "provider_install for unknown provider should fail"

    $installResp = Invoke-Core @{
        action = "provider_install"
        providerId = $providerId
    }
    Assert-True -condition ([bool]$installResp.ok) -message ("provider_install failed: " + [string]$installResp.message)
    Assert-True -condition ($installResp.installedProviderIds -contains $providerId) -message "installedProviderIds should contain installed provider"
    $expectedProfileSuffix = ("provider-" + (Sanitize-ProviderId $providerId) + ".json")
    Assert-True -condition ([string]$installResp.profilePath -like ("*" + $expectedProfileSuffix)) -message ("provider_install should activate provider profile, got profilePath=" + [string]$installResp.profilePath)

    $marketAfterInstall = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterInstall.ok) -message ("provider_market_list after install failed: " + [string]$marketAfterInstall.message)
    Assert-True -condition ($marketAfterInstall.installedProviderIds -contains $providerId) -message "provider should remain installed in market list"

    $originalHash = [string](@($marketAfterInstall.providers | Where-Object { $_.id -eq $providerId } | Select-Object -First 1).packageHash)
    if ([string]::IsNullOrWhiteSpace($originalHash)) {
        $originalHash = "pkg-" + (Sanitize-ProviderId $providerId) + "-v1"
    }
    $upgradeHash = $originalHash + "-upgrade"
    if ($upgradeHash -eq $originalHash) {
        $upgradeHash = $originalHash + "-v2"
    }

    $upgradePayloadJson = New-UpgradeMarketJson `
        -providerId $providerId `
        -pricePerGb 0.023 `
        -packageHash $upgradeHash

    $tempImportPath = Join-Path $env:TEMP ("openmesh-win-provider-upgrade-" + [guid]::NewGuid().ToString("N") + ".json")
    [System.IO.File]::WriteAllText($tempImportPath, $upgradePayloadJson, [System.Text.UTF8Encoding]::new($false))

    $importUpgradeResp = Invoke-Core @{
        action = "provider_import_file"
        importPath = $tempImportPath
    }
    Assert-True -condition ([bool]$importUpgradeResp.ok) -message ("provider_import_file for upgrade failed: " + [string]$importUpgradeResp.message)

    $marketAfterImportUpgrade = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterImportUpgrade.ok) -message ("provider_market_list after import upgrade failed: " + [string]$marketAfterImportUpgrade.message)
    $upgradableOffer = @($marketAfterImportUpgrade.providers | Where-Object { $_.id -eq $providerId }) | Select-Object -First 1
    Assert-True -condition ($null -ne $upgradableOffer) -message "upgradable offer missing in market list"
    Assert-True -condition ([string]$upgradableOffer.packageHash -eq $upgradeHash) -message "market package hash should be updated after import"
    Assert-True -condition ([bool]$upgradableOffer.upgradeAvailable) -message "upgradeAvailable should be true before provider_upgrade"

    $upgradeResp = Invoke-Core @{
        action = "provider_upgrade"
        providerId = $providerId
    }
    Assert-True -condition ([bool]$upgradeResp.ok) -message ("provider_upgrade failed: " + [string]$upgradeResp.message)
    Assert-True -condition ($upgradeResp.installedProviderIds -contains $providerId) -message "installedProviderIds should keep provider after upgrade"

    $marketAfterUpgrade = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterUpgrade.ok) -message ("provider_market_list after upgrade failed: " + [string]$marketAfterUpgrade.message)
    $upgradedOffer = @($marketAfterUpgrade.providers | Where-Object { $_.id -eq $providerId }) | Select-Object -First 1
    Assert-True -condition ($null -ne $upgradedOffer) -message "upgraded offer missing in market list"
    Assert-True -condition ([string]$upgradedOffer.packageHash -eq $upgradeHash) -message "market package hash should remain upgraded value"
    Assert-True -condition (-not [bool]$upgradedOffer.upgradeAvailable) -message "upgradeAvailable should be false after provider_upgrade"

    $textImportId = "import-text-" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $textImportPayload = @"
{
  "providers": [
    {
      "id": "$textImportId",
      "name": "Import Text Provider",
      "region": "text-region",
      "pricePerGb": 0.018,
      "packageHash": "pkg-$textImportId-v1",
      "description": "imported from text payload"
    }
  ]
}
"@
    $importTextResp = Invoke-Core @{
        action = "provider_import_text"
        importContent = $textImportPayload
    }
    Assert-True -condition ([bool]$importTextResp.ok) -message ("provider_import_text failed: " + [string]$importTextResp.message)
    $importTextIds = @($importTextResp.providers | ForEach-Object { [string]$_.id })
    Assert-True -condition ($importTextIds -contains $textImportId) -message "provider_import_text should contain imported provider id"

    $urlImportId = "import-url-" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $urlImportPayload = @"
{
  "providers": [
    {
      "id": "$urlImportId",
      "name": "Import URL Provider",
      "region": "url-region",
      "pricePerGb": 0.017,
      "packageHash": "pkg-$urlImportId-v1",
      "description": "imported from url payload"
    }
  ]
}
"@
    $httpPort = Get-FreeTcpPort
    $httpPrefix = "http://127.0.0.1:$httpPort/"
    $httpJob = Start-Job -ScriptBlock {
        param($Port, $PayloadText)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, [int]$Port)
        $listener.Start()
        try {
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                while ($true) {
                    $line = $reader.ReadLine()
                    if ($null -eq $line -or $line -eq "") {
                        break
                    }
                }
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($PayloadText)
                $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
                $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                $stream.Flush()
            }
            finally {
                $client.Close()
            }
        }
        finally {
            $listener.Stop()
        }
    } -ArgumentList $httpPort, $urlImportPayload

    for ($waitIndex = 0; $waitIndex -lt 50; $waitIndex++) {
        $jobState = (Get-Job -Id $httpJob.Id).State
        if ($jobState -eq "Running") {
            break
        }
        if ($jobState -eq "Failed" -or $jobState -eq "Completed" -or $jobState -eq "Stopped") {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    Start-Sleep -Milliseconds 600
    $importUrlResp = Invoke-Core @{
        action = "provider_import_url"
        importUrl = ($httpPrefix + "providers.json")
    }
    Wait-Job -Job $httpJob -Timeout 5 | Out-Null
    Receive-Job -Job $httpJob | Out-Null
    Remove-Job -Job $httpJob -Force
    Assert-True -condition ([bool]$importUrlResp.ok) -message ("provider_import_url failed: " + [string]$importUrlResp.message)
    $importUrlIds = @($importUrlResp.providers | ForEach-Object { [string]$_.id })
    Assert-True -condition ($importUrlIds -contains $urlImportId) -message "provider_import_url should contain imported provider id"

    $activateResp = Invoke-Core @{
        action = "provider_activate"
        providerId = $providerId
    }
    Assert-True -condition ([bool]$activateResp.ok) -message ("provider_activate failed: " + [string]$activateResp.message)
    Assert-True -condition ([string]$activateResp.profilePath -like ("*" + $expectedProfileSuffix)) -message ("provider_activate should keep provider profile active, got profilePath=" + [string]$activateResp.profilePath)

    $uninstallResp = Invoke-Core @{
        action = "provider_uninstall"
        providerId = $providerId
    }
    Assert-True -condition ([bool]$uninstallResp.ok) -message ("provider_uninstall failed: " + [string]$uninstallResp.message)
    Assert-True -condition (-not ($uninstallResp.installedProviderIds -contains $providerId)) -message "installedProviderIds should not contain removed provider"
    Assert-True -condition ([string]$uninstallResp.profilePath -notlike ("*" + $expectedProfileSuffix)) -message ("provider_uninstall should fallback active profile away from removed provider, got profilePath=" + [string]$uninstallResp.profilePath)

    $marketAfterUninstall = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterUninstall.ok) -message ("provider_market_list after uninstall failed: " + [string]$marketAfterUninstall.message)
    Assert-True -condition (-not ($marketAfterUninstall.installedProviderIds -contains $providerId)) -message "provider should remain removed in market list"

    Write-Host "P7 go core provider smoke checks passed."
}
finally {
    if ($null -ne $tempImportPath -and (Test-Path $tempImportPath)) {
        Remove-Item -Path $tempImportPath -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
