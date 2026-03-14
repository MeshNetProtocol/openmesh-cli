# ADB 日志查看脚本 - OpenMesh Android VPN 调试
# 使用方法：.\view-vpn-log.ps1

$ADB_PATH = "D:\android-sdk\platform-tools\adb.exe"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  OpenMesh VPN 日志查看器" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# 检查 ADB 是否存在
if (-not (Test-Path $ADB_PATH)) {
    Write-Host "❌ ADB 未找到：$ADB_PATH" -ForegroundColor Red
    exit 1
}

# 检查设备连接
Write-Host "正在检查设备连接..." -ForegroundColor Yellow
& $ADB_PATH devices

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ADB 命令执行失败，请检查设备是否连接" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  开始捕获 OpenMesh VPN 日志" -ForegroundColor Green
Write-Host "  按 Ctrl+C 停止" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# 清除旧日志
& $ADB_PATH logcat -c

# 捕获 OpenMesh 相关日志
& $ADB_PATH logcat -s `
    OpenMeshVpnService:* `
    OpenMeshBoxService:* `
    OpenMeshAndroid:* `
    MainActivity:* `
    libbox:* `
    Go:* `
    AndroidRuntime:*
