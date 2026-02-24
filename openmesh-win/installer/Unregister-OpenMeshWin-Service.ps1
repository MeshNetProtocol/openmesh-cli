param(
    [string]$ServiceName = "OpenMeshWinService"
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

if (-not (Test-IsAdministrator)) {
    throw "Administrator privileges are required to unregister Windows service."
}

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -eq $existing) {
    Write-Host "Service not found. Nothing to unregister: $ServiceName"
    exit 0
}

if ($existing.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
}

& sc.exe delete $ServiceName | Out-Null
Wait-ServiceDeleted -name $ServiceName

Write-Host "OpenMeshWin service unregistered: $ServiceName"
