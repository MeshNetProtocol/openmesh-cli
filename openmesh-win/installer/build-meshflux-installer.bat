@echo off
setlocal

rem Builds the MeshFlux installer (MSI only, self-contained by default).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-P6-Wix-Msi.ps1" -Configuration Release -RequireWintun -Version 1.0.0
exit /b %errorlevel%
