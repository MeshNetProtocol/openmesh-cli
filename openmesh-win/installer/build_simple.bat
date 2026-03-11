@echo off
setlocal

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-P6-Wix-Msi.ps1" -Configuration Release -Version 1.0.0 -RequireWintun
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-P6-Wix-Msi.ps1" %*
)

exit /b %errorlevel%
