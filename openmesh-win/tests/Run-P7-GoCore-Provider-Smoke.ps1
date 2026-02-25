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

    $marketAfterInstall = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterInstall.ok) -message ("provider_market_list after install failed: " + [string]$marketAfterInstall.message)
    Assert-True -condition ($marketAfterInstall.installedProviderIds -contains $providerId) -message "provider should remain installed in market list"

    $uninstallResp = Invoke-Core @{
        action = "provider_uninstall"
        providerId = $providerId
    }
    Assert-True -condition ([bool]$uninstallResp.ok) -message ("provider_uninstall failed: " + [string]$uninstallResp.message)
    Assert-True -condition (-not ($uninstallResp.installedProviderIds -contains $providerId)) -message "installedProviderIds should not contain removed provider"

    $marketAfterUninstall = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketAfterUninstall.ok) -message ("provider_market_list after uninstall failed: " + [string]$marketAfterUninstall.message)
    Assert-True -condition (-not ($marketAfterUninstall.installedProviderIds -contains $providerId)) -message "provider should remain removed in market list"

    Write-Host "P7 go core provider smoke checks passed."
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
