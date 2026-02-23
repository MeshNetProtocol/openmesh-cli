param(
    [string]$GoCoreExePath = "",
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path

function Stop-ConflictingProcesses {
    $targets = New-Object System.Collections.Generic.List[object]
    $processes = Get-CimInstance Win32_Process
    foreach ($p in $processes) {
        $nameText = if ($null -eq $p.Name) { "" } else { [string]$p.Name }
        $name = $nameText.ToLowerInvariant()
        if ($name -eq "openmeshwin.exe" -or
            $name -eq "openmeshwin.core.exe" -or
            $name -eq "openmesh-win-core.exe") {
            $targets.Add($p)
            continue
        }

        if ($name -eq "dotnet.exe") {
            $cmdText = if ($null -eq $p.CommandLine) { "" } else { [string]$p.CommandLine }
            $cmd = $cmdText.ToLowerInvariant()
            if ($cmd.Contains("openmeshwin.core.dll")) {
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
            Write-Warning ("Failed to stop PID={0} Name={1}: {2}" -f $target.ProcessId, $target.Name, $_.Exception.Message)
        }
    }

    Start-Sleep -Milliseconds 500
}

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

function Invoke-Core([hashtable]$payload) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'openmesh-win-core', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(2500)
    try {
        $writer = [System.IO.StreamWriter]::new($pipe, [System.Text.UTF8Encoding]::new($false), 1024, $true)
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8, $false, 1024, $true)
        $writer.WriteLine(($payload | ConvertTo-Json -Compress))
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw "empty response"
        }
        return ($line | ConvertFrom-Json)
    }
    finally {
        $pipe.Dispose()
    }
}

$resolvedGoCore = Resolve-GoCorePath -explicitPath $GoCoreExePath
if ($null -eq $resolvedGoCore) {
    throw (
        "Cannot find openmesh-win-core.exe. " +
        "Run .\\openmesh-win\\tests\\Build-P1-GoCore.ps1 first, or set OPENMESH_WIN_GO_CORE_EXE."
    )
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses
}

$proc = Start-Process -FilePath $resolvedGoCore -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 900

try {
    $ping = Invoke-Core @{ action = "ping" }
    if (-not $ping.ok) { throw "ping failed: $($ping.message)" }
    if (($ping.message -as [string]) -notlike "*go core*") {
        throw "unexpected ping response, likely not from go core: $($ping.message)"
    }

    $status1 = Invoke-Core @{ action = "status" }
    if (-not $status1.ok) { throw "status failed: $($status1.message)" }

    $reload = Invoke-Core @{ action = "reload" }
    if (-not $reload.ok) { throw "reload failed: $($reload.message)" }

    $start = Invoke-Core @{ action = "start_vpn" }
    if (-not $start.ok) { throw "start_vpn failed: $($start.message)" }

    $status2 = Invoke-Core @{ action = "status" }
    if (-not $status2.vpnRunning) { throw "status expected vpnRunning=true after start_vpn" }

    $stop = Invoke-Core @{ action = "stop_vpn" }
    if (-not $stop.ok) { throw "stop_vpn failed: $($stop.message)" }

    $status3 = Invoke-Core @{ action = "status" }
    if ($status3.vpnRunning) { throw "status expected vpnRunning=false after stop_vpn" }

    Write-Host "P1 go core smoke checks passed."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
