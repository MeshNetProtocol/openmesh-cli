param(
    [string]$InstallDir = "$env:ProgramFiles\OpenMeshWin",
    [string]$ServiceName = "OpenMeshWinService",
    [string]$DisplayName = "OpenMeshWin Service",
    [string]$Description = "OpenMeshWin privileged background service.",
    [ValidateSet("Automatic", "Manual", "Disabled")]
    [string]$StartupType = "Automatic",
    [switch]$StartService
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ServiceDeleted([string]$name, [int]$timeoutSeconds = 20) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($null -eq (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 400
    }
    throw "Service deletion timeout: $name"
}

function Wait-ServiceExists([string]$name, [int]$timeoutSeconds = 20) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($null -ne (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 300
    }
    throw "Service creation timeout: $name"
}

function Invoke-Sc([string[]]$arguments) {
    $output = & sc.exe @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $text = (($output | ForEach-Object { [string]$_ }) -join " | ")
        throw "sc.exe failed (exit=$exitCode): $text"
    }
    return $output
}

function Get-ServiceQueryText([string]$name) {
    $query = & sc.exe query $name 2>&1
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return (($query | ForEach-Object { [string]$_ }) -join " | ")
}

function Wait-ServiceRunning([string]$name, [int]$timeoutSeconds = 20) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
            return
        }
        Start-Sleep -Milliseconds 400
    }
    throw "Service did not reach Running state within timeout: $name"
}

if (-not (Test-IsAdministrator)) {
    throw "Administrator privileges are required to register Windows service."
}

$serviceExe = Join-Path $InstallDir "service\OpenMeshWin.Service.exe"
$serviceDll = Join-Path $InstallDir "service\OpenMeshWin.Service.dll"

$binPath = ""
if (Test-Path $serviceExe) {
    $binPath = "`"$serviceExe`" --service --service-name `"$ServiceName`""
} elseif (Test-Path $serviceDll) {
    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $dotnetCmd -or [string]::IsNullOrWhiteSpace($dotnetCmd.Source)) {
        throw "Service DLL found but dotnet runtime command is missing."
    }
    $dotnetPath = [string]$dotnetCmd.Source
    $binPath = "`"$dotnetPath`" `"$serviceDll`" --service --service-name `"$ServiceName`""
} else {
    throw "Service binary not found under: $InstallDir\service"
}

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    if ($existing.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    }
    Invoke-Sc -arguments @("delete", $ServiceName) | Out-Null
    Wait-ServiceDeleted -name $ServiceName
}

$startToken = switch ($StartupType) {
    "Automatic" { "auto" }
    "Manual" { "demand" }
    "Disabled" { "disabled" }
    default { "demand" }
}

Invoke-Sc -arguments @(
    "create",
    $ServiceName,
    "binPath=",
    $binPath,
    "start=",
    $startToken,
    "DisplayName=",
    $DisplayName
) | Out-Null
Wait-ServiceExists -name $ServiceName -timeoutSeconds 20
Invoke-Sc -arguments @("description", $ServiceName, $Description) | Out-Null

if ($StartService) {
    $started = $false
    $lastStartError = ""
    $lastQuery = ""
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }
        catch {
            $lastStartError = $_.Exception.Message
        }

        try {
            Wait-ServiceRunning -name $ServiceName -timeoutSeconds 3
            $started = $true
            break
        }
        catch {
            $lastQuery = Get-ServiceQueryText -name $ServiceName
            Start-Sleep -Milliseconds 1200
        }
    }
    if (-not $started) {
        if ([string]::IsNullOrWhiteSpace($lastQuery)) {
            throw "Start-Service failed for ${ServiceName}: $lastStartError"
        }
        throw "Start-Service failed for ${ServiceName}: $lastStartError ; sc.query=$lastQuery"
    }
}

$service = Get-Service -Name $ServiceName -ErrorAction Stop
Write-Host "OpenMeshWin service registered."
Write-Host "ServiceName: $ServiceName"
Write-Host "Status: $($service.Status)"
Write-Host "StartupType: $StartupType"
Write-Host "BinaryPath: $binPath"
