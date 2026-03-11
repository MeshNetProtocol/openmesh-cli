@echo off
setlocal
set SCRIPT_DIR=%~dp0
cd /d %SCRIPT_DIR%
echo [INFO] Running build script...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Build-Core-Windows.ps1"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Build failed with exit code %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)
echo [SUCCESS] Build completed.
endlocal
