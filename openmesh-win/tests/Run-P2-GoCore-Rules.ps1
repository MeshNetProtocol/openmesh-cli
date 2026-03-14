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
    $connected = $false
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $pipe.Connect(1200)
            $connected = $true
            break
        }
        catch {
            if ($i -eq 5) {
                throw
            }
            Start-Sleep -Milliseconds 350
        }
    }
    if (-not $connected) {
        throw "failed to connect core pipe"
    }
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

function Get-RouteRulesCount([string]$effectiveConfigPath) {
    if (-not (Test-Path $effectiveConfigPath)) {
        throw "effective config missing: $effectiveConfigPath"
    }
    $cfg = Get-Content -Raw -Path $effectiveConfigPath | ConvertFrom-Json
    if ($null -eq $cfg.route -or $null -eq $cfg.route.rules) {
        return 0
    }
    return @($cfg.route.rules).Count
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

$runtimeRoot = Join-Path (Split-Path -Parent $resolvedGoCore) "runtime"
$profilesRoot = Join-Path $runtimeRoot "profiles"
$routingRulesPath = Join-Path $runtimeRoot "routing_rules.json"
New-Item -Path $profilesRoot -ItemType Directory -Force | Out-Null

$profilePath = Join-Path $profilesRoot "p2_profile.json"
$profileContent = @'
{
  // relaxed JSON profile for P2
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "selector", "tag": "proxy", "outbounds": ["node-a", "node-b"], "default": "node-a", },
    { "type": "urltest", "tag": "auto", "outbounds": ["node-a", "node-b"], "default": "node-a" },
    { "type": "shadowsocks", "tag": "node-a" },
    { "type": "shadowsocks", "tag": "node-b" }
  ],
  "route": {
    "rules": [
      { "action": "sniff" },
    ],
  },
}
'@
Set-Content -Path $profilePath -Value $profileContent -Encoding UTF8

$rulesContent = @'
# text mode rules
ip_cidr: 1.1.1.1/32
domain_suffix: openai.com, github.com
chat.openai.com
'@
Set-Content -Path $routingRulesPath -Value $rulesContent -Encoding UTF8

$prevEnable = $env:OPENMESH_WIN_P3_ENABLE
$env:OPENMESH_WIN_P3_ENABLE = ""

$proc = Start-Process -FilePath $resolvedGoCore -PassThru -WindowStyle Hidden
$ready = $false
for ($i = 0; $i -lt 50; $i++) {
    if ($proc.HasExited) {
        throw "go core exited early with code $($proc.ExitCode)"
    }
    try {
        $ping = Invoke-Core @{ action = "ping" }
        if ($ping.ok) {
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
    $setProfile = Invoke-Core @{ action = "set_profile"; profilePath = $profilePath }
    if (-not $setProfile.ok) { throw "set_profile failed: $($setProfile.message)" }

    $reload1 = Invoke-Core @{ action = "reload" }
    if (-not $reload1.ok) { throw "reload1 failed: $($reload1.message)" }
    if ($reload1.injectedRuleCount -le 0) { throw "reload1 expected injectedRuleCount > 0" }
    $rulesCount1 = Get-RouteRulesCount -effectiveConfigPath $reload1.effectiveConfigPath

    $reload2 = Invoke-Core @{ action = "reload" }
    if (-not $reload2.ok) { throw "reload2 failed: $($reload2.message)" }
    $rulesCount2 = Get-RouteRulesCount -effectiveConfigPath $reload2.effectiveConfigPath
    if ($rulesCount2 -ne $rulesCount1) {
        throw "duplicate injection detected: rules count changed $rulesCount1 -> $rulesCount2"
    }

    $sel = Invoke-Core @{ action = "select_outbound"; group = "proxy"; outbound = "node-b" }
    if (-not $sel.ok) { throw "select_outbound failed: $($sel.message)" }

    $statusSel = Invoke-Core @{ action = "status" }
    $proxyGroup = @($statusSel.outboundGroups | Where-Object { $_.tag -eq "proxy" }) | Select-Object -First 1
    if ($null -eq $proxyGroup) { throw "status missing proxy group" }
    if ($proxyGroup.selected -ne "node-b") { throw "select persistence missing before reload, got: $($proxyGroup.selected)" }

    $reload3 = Invoke-Core @{ action = "reload" }
    if (-not $reload3.ok) { throw "reload3 failed: $($reload3.message)" }
    $statusAfterReload = Invoke-Core @{ action = "status" }
    $proxyGroup2 = @($statusAfterReload.outboundGroups | Where-Object { $_.tag -eq "proxy" }) | Select-Object -First 1
    if ($null -eq $proxyGroup2) { throw "status after reload missing proxy group" }
    if ($proxyGroup2.selected -ne "node-b") { throw "select persistence missing after reload, got: $($proxyGroup2.selected)" }

    $urltest = Invoke-Core @{ action = "urltest"; group = "proxy" }
    if (-not $urltest.ok) { throw "urltest failed: $($urltest.message)" }
    if ($urltest.group -ne "proxy") { throw "urltest returned unexpected group: $($urltest.group)" }
    if ($null -eq $urltest.delays.'node-a' -or $null -eq $urltest.delays.'node-b') {
        throw "urltest delays missing node-a/node-b entries"
    }

    Write-Host "P2 go core rules checks passed."
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    $env:OPENMESH_WIN_P3_ENABLE = $prevEnable
}
