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

function Assert-Near([double]$left, [double]$right, [double]$epsilon, [string]$message) {
    if ([math]::Abs($left - $right) -gt $epsilon) {
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

    $mnemonicResp = Invoke-Core @{ action = "wallet_generate_mnemonic" }
    Assert-True -condition ([bool]$mnemonicResp.ok) -message ("wallet_generate_mnemonic failed: " + [string]$mnemonicResp.message)

    $mnemonic = [string]$mnemonicResp.generatedMnemonic
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace($mnemonic)) -message "generatedMnemonic is empty"
    $wordCount = (($mnemonic -split "\s+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    Assert-True -condition ($wordCount -eq 12) -message ("expected 12 mnemonic words, got: " + $wordCount)

    $password = "OpenMesh#123"
    $createResp = Invoke-Core @{
        action = "wallet_create"
        mnemonic = $mnemonic
        password = $password
    }
    Assert-True -condition ([bool]$createResp.ok) -message ("wallet_create failed: " + [string]$createResp.message)
    Assert-True -condition ([bool]$createResp.walletExists) -message "wallet_create should set walletExists=true"
    Assert-True -condition ([bool]$createResp.walletUnlocked) -message "wallet_create should set walletUnlocked=true"
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace([string]$createResp.walletAddress)) -message "walletAddress is empty after wallet_create"

    $balanceResp = Invoke-Core @{
        action = "wallet_balance"
        network = "base-mainnet"
        tokenSymbol = "USDC"
    }
    Assert-True -condition ([bool]$balanceResp.ok) -message ("wallet_balance failed: " + [string]$balanceResp.message)
    $balanceBefore = [double]$balanceResp.walletBalance
    Assert-True -condition ($balanceBefore -gt 0) -message "wallet balance should be positive before x402_pay"

    $amountText = "0.125000"
    $payResp = Invoke-Core @{
        action = "x402_pay"
        to = "provider.openmesh"
        resource = "/api/v1/relay"
        amount = $amountText
        password = $password
    }
    Assert-True -condition ([bool]$payResp.ok) -message ("x402_pay failed: " + [string]$payResp.message)
    Assert-True -condition (-not [string]::IsNullOrWhiteSpace([string]$payResp.paymentId)) -message "x402_pay should return paymentId"

    $balanceAfterPay = [double]$payResp.walletBalance
    Assert-True -condition ($balanceAfterPay -lt $balanceBefore) -message "wallet balance should decrease after x402_pay"
    $expectedAfterPay = $balanceBefore - [double]$amountText
    Assert-Near -left $balanceAfterPay -right $expectedAfterPay -epsilon 0.000001 -message "wallet balance delta mismatch after x402_pay"

    Stop-Process -Id $proc.Id -Force
    $proc.WaitForExit()
    $proc = $null
    Start-Sleep -Milliseconds 300

    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $restartBalanceResp = Invoke-Core @{
        action = "wallet_balance"
        network = "base-mainnet"
        tokenSymbol = "USDC"
    }
    Assert-True -condition ([bool]$restartBalanceResp.ok) -message ("wallet_balance after restart failed: " + [string]$restartBalanceResp.message)
    Assert-True -condition ([bool]$restartBalanceResp.walletExists) -message "wallet should still exist after restart"
    Assert-True -condition (-not [bool]$restartBalanceResp.walletUnlocked) -message "wallet should be locked after restart"

    $unlockFailResp = Invoke-Core @{
        action = "wallet_unlock"
        password = "WrongPass#123"
    }
    Assert-True -condition (-not [bool]$unlockFailResp.ok) -message "wallet_unlock with wrong password should fail"

    $unlockResp = Invoke-Core @{
        action = "wallet_unlock"
        password = $password
    }
    Assert-True -condition ([bool]$unlockResp.ok) -message ("wallet_unlock failed: " + [string]$unlockResp.message)
    Assert-True -condition ([bool]$unlockResp.walletUnlocked) -message "wallet_unlock should set walletUnlocked=true"

    $finalBalanceResp = Invoke-Core @{
        action = "wallet_balance"
        network = "base-mainnet"
        tokenSymbol = "USDC"
    }
    Assert-True -condition ([bool]$finalBalanceResp.ok) -message ("final wallet_balance failed: " + [string]$finalBalanceResp.message)
    $finalBalance = [double]$finalBalanceResp.walletBalance
    Assert-Near -left $finalBalance -right $balanceAfterPay -epsilon 0.000001 -message "wallet balance should persist across restart"

    Write-Host "P5 go core wallet smoke checks passed."
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
