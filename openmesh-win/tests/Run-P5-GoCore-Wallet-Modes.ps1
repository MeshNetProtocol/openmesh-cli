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

$envBackup1 = Save-And-SetEnv @{
    "OPENMESH_WIN_P5_BALANCE_REAL" = "0"
    "OPENMESH_WIN_P5_BALANCE_STRICT" = "0"
    "OPENMESH_WIN_P5_X402_REAL" = "0"
    "OPENMESH_WIN_P5_X402_STRICT" = "0"
}

try {
    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $mn = Invoke-Core @{ action = "wallet_generate_mnemonic" }
    Assert-True -condition ([bool]$mn.ok) -message ("wallet_generate_mnemonic failed: " + [string]$mn.message)

    $cw = Invoke-Core @{
        action = "wallet_create"
        mnemonic = [string]$mn.generatedMnemonic
        password = $password
    }
    Assert-True -condition ([bool]$cw.ok) -message ("wallet_create failed: " + [string]$cw.message)

    $balance = Invoke-Core @{
        action = "wallet_balance"
        network = "unknown-network"
        tokenSymbol = "USDC"
    }
    Assert-True -condition ([bool]$balance.ok) -message ("wallet_balance failed: " + [string]$balance.message)
    $source = [string]$balance.walletBalanceSource
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace($source)) -message "walletBalanceSource should not be empty"

    $pay = Invoke-Core @{
        action = "x402_pay"
        to = "provider.openmesh"
        resource = "/api/v1/relay"
        amount = "0.010000"
        password = $password
    }
    Assert-True -condition ([bool]$pay.ok) -message ("x402_pay failed in simulated mode: " + [string]$pay.message)
    Assert-True -condition ([string]$pay.paymentMode -eq "simulated") -message ("paymentMode should be simulated, got: " + [string]$pay.paymentMode)

    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
        $proc.WaitForExit()
    }
    $proc = $null
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    Restore-Env -backup $envBackup1
}
Write-Host "P5 go core wallet mode checks passed."
