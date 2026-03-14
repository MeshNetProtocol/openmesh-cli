# ADB 调试脚本 - 用于调试 Offline Import 闪退问题
# 使用方法：.\adb-debug.ps1

$ADB_PATH = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  ADB 调试工具" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# 检查设备连接
Write-Host "正在检查设备连接..." -ForegroundColor Yellow
& $ADB_PATH devices

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ADB 命令执行失败，请检查 ADB 路径是否正确" -ForegroundColor Red
    Write-Host "ADB 路径：$ADB_PATH" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  开始捕获日志（按 Ctrl+C 停止）" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# 清除旧日志
& $ADB_PATH logcat -c

# 捕获 OpenMesh 相关日志
& $ADB_PATH logcat -s `
    OpenMeshAndroid:* `
    MainActivity:* `
    OfflineImportActivity:* `
    AndroidRuntime:* `
    PackageManager:*
