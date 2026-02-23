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

$prevMode = $env:OPENMESH_WIN_P3_ENGINE
$prevSingboxExe = $env:OPENMESH_WIN_SINGBOX_EXE
$prevEnable = $env:OPENMESH_WIN_P3_ENABLE

$env:OPENMESH_WIN_P3_ENABLE = "1"
$env:OPENMESH_WIN_P3_ENGINE = "singbox"
$env:OPENMESH_WIN_SINGBOX_EXE = "Z:\\__definitely_not_exists__\\sing-box.exe"

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
    $probe = Invoke-Core @{ action = "p3_engine_probe" }
    if ($probe.p3EngineMode -ne "singbox") { throw "expected p3EngineMode=singbox, got: $($probe.p3EngineMode)" }
    if ($probe.p3SingboxFound) { throw "expected p3SingboxFound=false with forced invalid path" }
    if ($probe.ok) { throw "expected p3_engine_probe to fail when sing-box is missing" }

    $start = Invoke-Core @{ action = "start_vpn" }
    if ($start.ok) { throw "expected start_vpn to fail when engine mode=singbox and executable is missing" }
    if (($start.message -as [string]) -notmatch "sing-box") {
        throw "start_vpn failure reason should mention sing-box, got: $($start.message)"
    }

    $status = Invoke-Core @{ action = "status" }
    if ($status.vpnRunning) { throw "expected vpnRunning=false after failed start_vpn" }

    Write-Host "P3 go core engine mode checks passed."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    $env:OPENMESH_WIN_P3_ENGINE = $prevMode
    $env:OPENMESH_WIN_SINGBOX_EXE = $prevSingboxExe
    $env:OPENMESH_WIN_P3_ENABLE = $prevEnable
}
