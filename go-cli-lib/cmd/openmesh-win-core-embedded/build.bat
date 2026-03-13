@echo off
setlocal
set SCRIPT_DIR=%~dp0
cd /d %SCRIPT_DIR%
echo [INFO] Delegating to go-cli-lib\build_dll.bat ...
call "%SCRIPT_DIR%..\..\build_dll.bat"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Unified build failed with exit code %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)
echo [SUCCESS] Unified build completed.
endlocal
