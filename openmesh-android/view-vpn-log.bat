@echo off
REM ADB 日志查看脚本 - OpenMesh Android VPN 调试
REM 使用方法：view-vpn-log.bat

set ADB_PATH=D:\android-sdk\platform-tools\adb.exe

echo =====================================
echo   OpenMesh VPN 日志查看器
echo =====================================
echo.

REM 检查 ADB 是否存在
if not exist "%ADB_PATH%" (
    echo ERROR: ADB 未找到：%ADB_PATH%
    pause
    exit /b 1
)

REM 检查设备连接
echo 正在检查设备连接...
"%ADB_PATH%" devices

if errorlevel 1 (
    echo ERROR: ADB 命令执行失败，请检查设备是否连接
    pause
    exit /b 1
)

echo.
echo =====================================
echo   开始捕获 OpenMesh VPN 日志
echo   按 Ctrl+C 停止
echo =====================================
echo.

REM 清除旧日志
"%ADB_PATH%" logcat -c

REM 捕获 OpenMesh 相关日志
"%ADB_PATH%" logcat -s ^
    OpenMeshVpnService:* ^
    OpenMeshBoxService:* ^
    OpenMeshAndroid:* ^
    MainActivity:* ^
    libbox:* ^
    Go:* ^
    AndroidRuntime:*
