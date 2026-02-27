param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Write-Host "Running legacy/mock core baseline checks (Phase8 script). Configuration=$Configuration"

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
$solution = Join-Path $repoRoot "openmesh-win.sln"
$coreDll = Join-Path $repoRoot ("core\OpenMeshWin.Core\bin\{0}\net10.0\OpenMeshWin.Core.dll" -f $Configuration)

function Stop-ConflictingProcesses {
    param(
        [string]$RepoRootPath
    )

    $repoLower = $RepoRootPath.ToLowerInvariant()
    $targets = New-Object System.Collections.Generic.List[object]
    $processes = Get-CimInstance Win32_Process

    foreach ($p in $processes) {
        $nameText = if ($null -eq $p.Name) { "" } else { [string]$p.Name }
        $cmdText = if ($null -eq $p.CommandLine) { "" } else { [string]$p.CommandLine }
        $name = $nameText.ToLowerInvariant()
        $cmd = $cmdText.ToLowerInvariant()

        $isOpenMeshWinExe = $name -eq "openmeshwin.exe"
        $isOpenMeshCoreExe = $name -eq "openmeshwin.core.exe"
        $isDotnetOpenMeshCore = $name -eq "dotnet.exe" -and $cmd.Contains("openmeshwin.core.dll") -and $cmd.Contains($repoLower)

        if ($isOpenMeshWinExe -or $isOpenMeshCoreExe -or $isDotnetOpenMeshCore) {
            $targets.Add($p)
        }
    }

    if ($targets.Count -eq 0) {
        Write-Host "No conflicting OpenMesh processes found."
        return
    }

    Write-Host ("Stopping {0} conflicting process(es)..." -f $targets.Count)
    foreach ($target in $targets) {
        try {
            $targetPid = [int]$target.ProcessId
            $procName = $target.Name
            Stop-Process -Id $targetPid -Force -ErrorAction Stop
            Write-Host ("Stopped PID={0} Name={1}" -f $targetPid, $procName)
        }
        catch {
            Write-Warning ("Failed to stop PID={0} Name={1}: {2}" -f $target.ProcessId, $target.Name, $_.Exception.Message)
        }
    }

    Start-Sleep -Milliseconds 500
}

if (-not $SkipStopConflictingProcesses) {
    Stop-ConflictingProcesses -RepoRootPath $repoRoot
}

& dotnet build $solution -c $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE. Retry with a clean workspace and no running OpenMesh processes."
}

if (-not (Test-Path $coreDll)) {
    throw "Core dll missing: $coreDll"
}

$proc = Start-Process -FilePath "dotnet" -ArgumentList @($coreDll) -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 800

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

try {
    $null = Invoke-Core @{ action = "reload" }
    $start = Invoke-Core @{ action = "start_vpn" }
    if (-not $start.ok) { throw "start_vpn failed: $($start.message)" }

    $heartbeatPath = Join-Path $env:APPDATA "OpenMeshWin\app_heartbeat"
    New-Item -Path (Split-Path $heartbeatPath -Parent) -ItemType Directory -Force | Out-Null
    Set-Content -Path $heartbeatPath -Value "stale-heartbeat" -Encoding UTF8
    (Get-Item $heartbeatPath).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-2)
    Start-Sleep -Milliseconds 450

    $status = Invoke-Core @{ action = "status" }
    if ($status.vpnRunning) {
        throw "heartbeat guard check failed: vpn still running"
    }

    $mn = Invoke-Core @{ action = "wallet_generate_mnemonic" }
    $cw = Invoke-Core @{ action = "wallet_create"; mnemonic = $mn.generatedMnemonic; password = "OpenMesh#123" }
    if (-not $cw.ok) { throw "wallet_create failed: $($cw.message)" }
    $pay = Invoke-Core @{ action = "x402_pay"; to = "provider.openmesh"; resource = "/api/v1/relay"; amount = "0.010000"; password = "OpenMesh#123" }
    if (-not $pay.ok) { throw "x402_pay failed: $($pay.message)" }

    Write-Host "Phase8 checks passed (legacy/mock baseline)."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
