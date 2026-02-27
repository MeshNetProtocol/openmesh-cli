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

$env:OPENMESH_WIN_P3_ENABLE = "1"
$env:OPENMESH_WIN_P3_APPLY = ""
$env:OPENMESH_WIN_P3_STRICT = ""

$proc = Start-Process -FilePath $resolvedGoCore -PassThru -WindowStyle Hidden
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    if ($proc.HasExited) {
        throw "go core exited early with code $($proc.ExitCode)"
    }
    try {
        $probe = Invoke-Core @{ action = "ping" }
        if ($probe.ok) {
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

try {
    $preflight = Invoke-Core @{ action = "p3_network_preflight" }
    if (-not ($preflight.PSObject.Properties.Name -contains "p3Admin")) {
        throw "preflight response missing p3Admin"
    }
    if (-not ($preflight.PSObject.Properties.Name -contains "p3WintunFound")) {
        throw "preflight response missing p3WintunFound"
    }

    $prepare = Invoke-Core @{ action = "p3_network_prepare" }
    if (-not $prepare.ok) { throw "p3_network_prepare failed: $($prepare.message)" }
    if (-not $prepare.p3NetworkPrepared) { throw "expected p3NetworkPrepared=true after prepare" }
    if (-not $prepare.p3NetworkDryRun) { throw "expected p3NetworkDryRun=true in default framework mode" }

    $start = Invoke-Core @{ action = "start_vpn" }
    if (-not $start.ok) { throw "start_vpn failed: $($start.message)" }
    if (-not $start.vpnRunning) { throw "expected vpnRunning=true after start_vpn" }
    if (-not $start.p3NetworkPrepared) { throw "expected p3 network prepared while vpn is running" }

    $stop = Invoke-Core @{ action = "stop_vpn" }
    if (-not $stop.ok) { throw "stop_vpn failed: $($stop.message)" }
    if ($stop.vpnRunning) { throw "expected vpnRunning=false after stop_vpn" }

    $status = Invoke-Core @{ action = "status" }
    if ($status.p3NetworkPrepared) { throw "expected p3NetworkPrepared=false after stop rollback" }
    if ([string]::IsNullOrWhiteSpace($status.p3LastRollbackAtUtc)) { throw "expected p3LastRollbackAtUtc after rollback" }

    Write-Host "P3 go core network framework checks passed."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
