@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File ".\release-google-play.ps1"
pause