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

function Start-GoCore([string]$corePath) {
    $proc = Start-Process -FilePath $corePath -PassThru -WindowStyle Hidden
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
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    throw "go core pipe did not become ready in time"
}

function Stop-GoCore($proc) {
    if ($null -eq $proc) {
        return
    }
    try {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
    catch {
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

$commonEnv = @{
    "OPENMESH_WIN_P3_ENABLE" = "1"
    "OPENMESH_WIN_P3_APPLY" = ""
    "OPENMESH_WIN_P3_STRICT" = ""
}

$proc = $null
$backup = $null

try {
    $backup = Save-And-SetEnv (@{
        "OPENMESH_WIN_P3_ENABLE" = $commonEnv["OPENMESH_WIN_P3_ENABLE"]
        "OPENMESH_WIN_P3_APPLY" = $commonEnv["OPENMESH_WIN_P3_APPLY"]
        "OPENMESH_WIN_P3_STRICT" = $commonEnv["OPENMESH_WIN_P3_STRICT"]
        "OPENMESH_WIN_P3_HEALTH_TCP" = "127.0.0.1:1"
        "OPENMESH_WIN_P3_HEALTH_TIMEOUT_MS" = "900"
    })

    $proc = Start-GoCore -corePath $resolvedGoCore
    $failedStart = Invoke-Core @{ action = "start_vpn" }
    if ($failedStart.ok) {
        throw "expected start_vpn to fail when tcp health endpoint is unreachable"
    }
    if (($failedStart.message -as [string]) -notmatch "health") {
        throw "expected failed start_vpn message to mention health check, got: $($failedStart.message)"
    }

    $status = Invoke-Core @{ action = "status" }
    if ($status.vpnRunning) { throw "expected vpnRunning=false after failed start_vpn" }
    if ($status.p3NetworkPrepared) { throw "expected p3NetworkPrepared=false after rollback on failed health check" }
    if ($status.p3EngineRunning) { throw "expected p3EngineRunning=false after failed health check startup path" }
    if ([string]::IsNullOrWhiteSpace($status.p3LastRollbackAtUtc)) {
        throw "expected p3LastRollbackAtUtc to be recorded after failed start rollback"
    }

    Stop-GoCore -proc $proc
    $proc = $null

    Restore-Env -backup $backup
    $backup = Save-And-SetEnv (@{
        "OPENMESH_WIN_P3_ENABLE" = $commonEnv["OPENMESH_WIN_P3_ENABLE"]
        "OPENMESH_WIN_P3_APPLY" = $commonEnv["OPENMESH_WIN_P3_APPLY"]
        "OPENMESH_WIN_P3_STRICT" = $commonEnv["OPENMESH_WIN_P3_STRICT"]
        "OPENMESH_WIN_P3_HEALTH_TCP" = ""
        "OPENMESH_WIN_P3_HEALTH_TIMEOUT_MS" = "1500"
    })

    $proc = Start-GoCore -corePath $resolvedGoCore
    $started = Invoke-Core @{ action = "start_vpn" }
    if (-not $started.ok) { throw "expected start_vpn success when process-only health check is used: $($started.message)" }
    if (-not $started.vpnRunning) { throw "expected vpnRunning=true after successful start_vpn" }
    if (-not $started.p3EngineRunning) { throw "expected p3EngineRunning=true after successful start_vpn" }

    $health = Invoke-Core @{ action = "p3_engine_health" }
    if (-not $health.ok) { throw "expected p3_engine_health success, got: $($health.message)" }
    if (-not $health.p3EngineHealthy) { throw "expected p3EngineHealthy=true after successful health check" }

    $stop = Invoke-Core @{ action = "stop_vpn" }
    if (-not $stop.ok) { throw "stop_vpn failed: $($stop.message)" }
    if ($stop.vpnRunning) { throw "expected vpnRunning=false after stop_vpn" }

    Write-Host "P3 go core engine health checks passed."
}
finally {
    Stop-GoCore -proc $proc
    if ($null -ne $backup) {
        Restore-Env -backup $backup
    }
}
