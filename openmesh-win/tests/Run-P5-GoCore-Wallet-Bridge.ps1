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

function Save-And-SetEnv([hashtable]$values) {
    $backup = @{}
    foreach ($k in $values.Keys) {
        $item = Get-Item ("Env:" + $k) -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            $backup[$k] = $null
        } else {
            $backup[$k] = [string]$item.Value
        }
        $v = [string]$values[$k]
        if ([string]::IsNullOrWhiteSpace($v)) {
            Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
        } else {
            Set-Item ("Env:" + $k) $v
        }
    }
    return $backup
}

function Restore-Env([hashtable]$backup) {
    foreach ($k in $backup.Keys) {
        $v = $backup[$k]
        if ($null -eq $v) {
            Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
        } else {
            Set-Item ("Env:" + $k) ([string]$v)
        }
    }
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

$password = "OpenMesh#123"
$proc = $null

$strictEnvBackup = Save-And-SetEnv @{
    "OPENMESH_WIN_P5_X402_REAL" = "1"
    "OPENMESH_WIN_P5_X402_STRICT" = "1"
}

try {
    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $mnemonicResp = Invoke-Core @{ action = "wallet_generate_mnemonic" }
    Assert-True -condition ([bool]$mnemonicResp.ok) -message ("wallet_generate_mnemonic failed: " + [string]$mnemonicResp.message)
    $mnemonic = [string]$mnemonicResp.generatedMnemonic
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace($mnemonic)) -message "generatedMnemonic is empty"

    $createResp = Invoke-Core @{
        action = "wallet_create"
        mnemonic = $mnemonic
        password = $password
    }
    Assert-True -condition ([bool]$createResp.ok) -message ("wallet_create failed: " + [string]$createResp.message)

    $goCoreDir = Split-Path -Parent $resolvedGoCore
    $keystorePath = Join-Path $goCoreDir "runtime\wallet\keystore.json"
    Assert-True -condition (Test-Path $keystorePath) -message ("wallet keystore missing: " + $keystorePath)

    $keystoreRaw = Get-Content -Path $keystorePath -Raw
    $keystore = $keystoreRaw | ConvertFrom-Json
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace([string]$keystore.keystoreJson)) -message "keystoreJson is empty; go-cli-lib wallet bridge not persisted"

    $realPayResp = Invoke-Core @{
        action = "x402_pay"
        to = "https://example.com"
        resource = "/"
        amount = "0.010000"
        password = $password
    }
    if ([bool]$realPayResp.ok) {
        $mode = ([string]$realPayResp.paymentMode).ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($mode)) {
            Assert-True -condition ($mode -eq "real" -or $mode -eq "simulated") -message ("unexpected paymentMode: " + [string]$realPayResp.paymentMode)
        }
        Assert-True -condition (-not [string]::IsNullOrWhiteSpace([string]$realPayResp.paymentId)) -message "strict real mode returned ok but paymentId is empty"
    } else {
        $mode = ([string]$realPayResp.paymentMode).ToLowerInvariant()
        Assert-True -condition (($mode -eq "real") -or (([string]$realPayResp.message).ToLowerInvariant().Contains("real")) ) -message "strict real mode failed but response is not marked as real-mode failure"
    }

    Stop-Process -Id $proc.Id -Force
    $proc.WaitForExit()
    $proc = $null
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    Restore-Env -backup $strictEnvBackup
}

try {
    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $unlockResp = Invoke-Core @{
        action = "wallet_unlock"
        password = $password
    }
    Assert-True -condition ([bool]$unlockResp.ok) -message ("wallet_unlock failed after restart: " + [string]$unlockResp.message)

    $payResp = Invoke-Core @{
        action = "x402_pay"
        to = "provider.openmesh"
        resource = "/api/v1/relay"
        amount = "0.020000"
        password = $password
    }
    Assert-True -condition ([bool]$payResp.ok) -message ("x402_pay fallback mode failed: " + [string]$payResp.message)
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace([string]$payResp.paymentId)) -message "paymentId is empty in fallback mode"

    Write-Host "P5 go core wallet bridge checks passed."
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
