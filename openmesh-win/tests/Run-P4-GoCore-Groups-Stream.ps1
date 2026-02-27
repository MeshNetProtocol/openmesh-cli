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

function Read-StreamEvent([System.IO.StreamReader]$reader, [int]$timeoutMs) {
    $task = $reader.ReadLineAsync()
    if (-not $task.Wait($timeoutMs)) {
        throw "groups stream read timeout after ${timeoutMs}ms"
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
$streamPipe = $null
$streamWriter = $null
$streamReader = $null

try {
    $proc = Start-Process -FilePath $resolvedGoCore -PassThru -WindowStyle Hidden
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
        throw "go core pipe did not become ready in time"
    }

    $reload = Invoke-Core @{ action = "reload" }
    if (-not $reload.ok) { throw "reload failed: $($reload.message)" }

    $status = Invoke-Core @{ action = "status" }
    if (-not $status.ok) { throw "status failed: $($status.message)" }
    if ($status.outboundGroups.Count -lt 1) { throw "expected outboundGroups from status" }

    $targetGroup = $null
    foreach ($g in $status.outboundGroups) {
        if ($g.selectable -and $g.items.Count -ge 2) {
            $targetGroup = $g
            break
        }
    }
    if ($null -eq $targetGroup) {
        throw "need at least one selectable group with >=2 outbounds"
    }

    $current = [string]$targetGroup.selected
    $next = $null
    foreach ($item in $targetGroup.items) {
        if ([string]$item.tag -ne $current) {
            $next = [string]$item.tag
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($next)) {
        throw "cannot determine alternate outbound for group '$($targetGroup.tag)'"
    }

    $streamPipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'openmesh-win-core', [System.IO.Pipes.PipeDirection]::InOut)
    $streamPipe.Connect(2500)
    $streamWriter = [System.IO.StreamWriter]::new($streamPipe, [System.Text.UTF8Encoding]::new($false), 1024, $true)
    $streamWriter.AutoFlush = $true
    $streamReader = [System.IO.StreamReader]::new($streamPipe, [System.Text.Encoding]::UTF8, $false, 1024, $true)
    $streamRequest = @{
        action = "groups_stream"
        streamIntervalMs = 160
        streamMaxEvents = 10
        streamHeartbeatEnabled = $true
    }
    $streamWriter.WriteLine(($streamRequest | ConvertTo-Json -Compress))

    $first = Read-StreamEvent -reader $streamReader -timeoutMs 2500
    if ($null -eq $first) { throw "groups stream closed before first event" }
    if ($first.streamType -ne "snapshot") { throw "expected first streamType=snapshot, got: $($first.streamType)" }
    if ([int]$first.streamSeq -ne 1) { throw "expected first streamSeq=1, got: $($first.streamSeq)" }
    $firstFingerprint = [string]$first.streamFingerprint

    $selected = Invoke-Core @{ action = "select_outbound"; group = [string]$targetGroup.tag; outbound = $next }
    if (-not $selected.ok) { throw "select_outbound failed: $($selected.message)" }

    $sawDelta = $false
    $prevSeq = [int]$first.streamSeq
    for ($i = 0; $i -lt 8; $i++) {
        $evt = Read-StreamEvent -reader $streamReader -timeoutMs 2500
        if ($null -eq $evt) { break }

        $currentSeq = [int]$evt.streamSeq
        if ($currentSeq -le $prevSeq) {
            throw "streamSeq must be strictly increasing, prev=$prevSeq current=$currentSeq"
        }
        $prevSeq = $currentSeq

        if ($evt.streamType -eq "delta" -and ([string]$evt.streamFingerprint) -ne $firstFingerprint) {
            $sawDelta = $true
            break
        }
    }
    if (-not $sawDelta) {
        throw "expected at least one groups stream delta after select_outbound"
    }

    Write-Host "P4 go core groups stream checks passed."
}
finally {
    if ($null -ne $streamReader) { try { $streamReader.Dispose() } catch {} }
    if ($null -ne $streamWriter) { try { $streamWriter.Dispose() } catch {} }
    if ($null -ne $streamPipe) { try { $streamPipe.Dispose() } catch {} }

    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
