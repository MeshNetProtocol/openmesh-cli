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

function Start-GoCore([string]$corePath) {
    $proc = Start-Process -FilePath $corePath -PassThru -WindowStyle Hidden
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if ($proc.HasExited) {
            throw "go core exited early with code $($proc.ExitCode)"
        }
        try {
            $pong = Invoke-Core @{ action = "ping" }
            if ($pong.ok) {
                $ready = $true
                break
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
        throw "go core pipe did not become ready in time"
    }
    return $proc
}

function Open-StatusStream() {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'openmesh-win-core', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(2500)
    $writer = [System.IO.StreamWriter]::new($pipe, [System.Text.UTF8Encoding]::new($false), 1024, $true)
    $writer.AutoFlush = $true
    $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8, $false, 1024, $true)

    $request = @{
        action = "status_stream"
        streamIntervalMs = 180
        streamMaxEvents = 0
        streamHeartbeatEnabled = $true
    }
    $writer.WriteLine(($request | ConvertTo-Json -Compress))

    return @{
        Pipe = $pipe
        Writer = $writer
        Reader = $reader
    }
}

function Read-StreamEvent([System.IO.StreamReader]$reader, [int]$timeoutMs) {
    $task = $reader.ReadLineAsync()
    if (-not $task.Wait($timeoutMs)) {
        throw "status stream read timeout after ${timeoutMs}ms"
    }
    $line = $task.Result
    if ($null -eq $line) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }
    return ($line | ConvertFrom-Json)
}

function Close-StatusStream($stream) {
    if ($null -eq $stream) {
        return
    }
    if ($null -ne $stream.Reader) {
        try { $stream.Reader.Dispose() } catch {}
    }
    if ($null -ne $stream.Writer) {
        try { $stream.Writer.Dispose() } catch {}
    }
    if ($null -ne $stream.Pipe) {
        try { $stream.Pipe.Dispose() } catch {}
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
            Set-Item ("Env:" + $k) ([string]$v
            )
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

$backup = Save-And-SetEnv @{
    "OPENMESH_WIN_P3_ENABLE" = ""
    "OPENMESH_WIN_P3_APPLY" = ""
    "OPENMESH_WIN_P3_STRICT" = ""
    "OPENMESH_WIN_P3_ENGINE" = ""
}

$procA = $null
$procB = $null
$streamA = $null
$streamB = $null

try {
    $procA = Start-GoCore -corePath $resolvedGoCore
    $streamA = Open-StatusStream

    $first = Read-StreamEvent -reader $streamA.Reader -timeoutMs 2500
    if ($null -eq $first) { throw "stream A closed before first event" }
    if ($first.streamType -ne "snapshot") { throw "expected stream A first event to be snapshot, got: $($first.streamType)" }
    if ([int]$first.streamSeq -ne 1) { throw "expected stream A first seq=1, got: $($first.streamSeq)" }

    $start = Invoke-Core @{ action = "start_vpn" }
    if (-not $start.ok) { throw "start_vpn failed before reconnect test: $($start.message)" }

    $sawDeltaBeforeRestart = $false
    for ($i = 0; $i -lt 8; $i++) {
        $evt = Read-StreamEvent -reader $streamA.Reader -timeoutMs 2500
        if ($null -eq $evt) {
            break
        }
        if ($evt.streamType -eq "delta" -and $evt.vpnRunning) {
            $sawDeltaBeforeRestart = $true
            break
        }
    }
    if (-not $sawDeltaBeforeRestart) {
        throw "expected at least one delta event with vpnRunning=true before restart"
    }

    if (-not $procA.HasExited) {
        try {
            Stop-Process -Id $procA.Id -Force -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -notlike "*Cannot find a process*") {
                throw
            }
        }
    }
    Start-Sleep -Milliseconds 350

    $streamABroken = $false
    try {
        $afterKill = Read-StreamEvent -reader $streamA.Reader -timeoutMs 1800
        if ($null -eq $afterKill) {
            $streamABroken = $true
        } else {
            throw "expected stream A to terminate after core kill, but received: $($afterKill.streamType)"
        }
    }
    catch {
        $streamABroken = $true
    }
    if (-not $streamABroken) {
        throw "stream A did not break after core kill"
    }

    Close-StatusStream -stream $streamA
    $streamA = $null

    $procB = Start-GoCore -corePath $resolvedGoCore
    $streamB = Open-StatusStream

    $firstB = Read-StreamEvent -reader $streamB.Reader -timeoutMs 2500
    if ($null -eq $firstB) { throw "stream B closed before first event" }
    if ($firstB.streamType -ne "snapshot") { throw "expected stream B first event to be snapshot, got: $($firstB.streamType)" }
    if ([int]$firstB.streamSeq -ne 1) { throw "expected stream B first seq=1 after restart, got: $($firstB.streamSeq)" }

    $status = Invoke-Core @{ action = "status" }
    if (-not $status.ok) { throw "status failed after reconnect: $($status.message)" }

    $stop = Invoke-Core @{ action = "stop_vpn" }
    if (-not $stop.ok) { throw "stop_vpn failed after reconnect: $($stop.message)" }

    Write-Host "P4 go core stream reconnect checks passed."
}
finally {
    Close-StatusStream -stream $streamA
    Close-StatusStream -stream $streamB

    foreach ($proc in @($procA, $procB)) {
        if ($null -ne $proc) {
            try {
                if (-not $proc.HasExited) {
                    Stop-Process -Id $proc.Id -Force
                }
            }
            catch {
            }
        }
    }

    Restore-Env -backup $backup
}
