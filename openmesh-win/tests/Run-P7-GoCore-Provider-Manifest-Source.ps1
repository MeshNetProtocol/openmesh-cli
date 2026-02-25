param(
    [string]$GoCoreExePath = "",
    [switch]$SkipStopConflictingProcesses
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path
$buildScript = Join-Path $repoRoot "openmesh-win\tests\Build-P1-GoCore.ps1"
$reportsDir = Join-Path $repoRoot "openmesh-win\tests\reports"

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

if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

$runtimeDir = Join-Path (Split-Path -Parent $resolvedGoCore) "runtime"
if (-not (Test-Path $runtimeDir)) {
    New-Item -Path $runtimeDir -ItemType Directory -Force | Out-Null
}
$customMarketPath = Join-Path $runtimeDir "provider_market.json"
$customPayload = @'
{
  "providers": [
    {
      "id": "provider-alpha-us",
      "name": "Provider Alpha US",
      "region": "us-east-1",
      "pricePerGb": 0.011,
      "packageHash": "pkg-alpha-us-v1",
      "description": "alpha route"
    },
    {
      "id": "provider-beta-eu",
      "name": "Provider Beta EU",
      "region": "eu-central-1",
      "pricePerGb": 0.013,
      "packageHash": "pkg-beta-eu-v1",
      "description": "beta route"
    },
    {
      "id": "",
      "name": "invalid-empty-id",
      "region": "global",
      "pricePerGb": 0.5
    }
  ]
}
'@
[System.IO.File]::WriteAllText($customMarketPath, $customPayload, [System.Text.UTF8Encoding]::new($false))

$proc = $null
try {
    $proc = Start-GoCoreAndWait -exePath $resolvedGoCore

    $marketResp = Invoke-Core @{ action = "provider_market_list" }
    Assert-True -condition ([bool]$marketResp.ok) -message ("provider_market_list failed: " + [string]$marketResp.message)
    Assert-True -condition ($marketResp.providers.Count -eq 2) -message ("expected 2 providers from custom manifest, got " + $marketResp.providers.Count)

    $ids = @($marketResp.providers | ForEach-Object { [string]$_.id })
    Assert-True -condition ($ids -contains "provider-alpha-us") -message "missing provider-alpha-us from manifest source"
    Assert-True -condition ($ids -contains "provider-beta-eu") -message "missing provider-beta-eu from manifest source"

    Write-Host "P7 go core provider manifest source checks passed."
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    if (Test-Path $customMarketPath) {
        Remove-Item -Path $customMarketPath -Force -ErrorAction SilentlyContinue
    }
}
