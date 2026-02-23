param()

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
$solution = Join-Path $repoRoot "openmesh-win.sln"
$coreDll = Join-Path $repoRoot "core\OpenMeshWin.Core\bin\Debug\net10.0\OpenMeshWin.Core.dll"

& dotnet build $solution

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

    Write-Host "Phase8 checks passed."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
