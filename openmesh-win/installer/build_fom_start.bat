@echo off
setlocal

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-Full-Installer.ps1" -Configuration Release -Version 1.0.0
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-Full-Installer.ps1" %*
)

exit /b %errorlevel%
