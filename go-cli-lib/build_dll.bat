@echo off
setlocal

:: Set CGO_ENABLED
set CGO_ENABLED=1

:: Add MinGW/GCC to PATH if not already present
if exist "C:\msys64\ucrt64\bin" (
    set "PATH=C:\msys64\ucrt64\bin;%PATH%"
)

:: Navigate to the Go embedded core directory
pushd "%~dp0\cmd\openmesh-win-core-embedded"

echo Building OpenMesh Go Core DLL...
go build -tags with_clash_api -buildmode=c-shared -o openmesh_core.dll .
if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    popd
    exit /b %ERRORLEVEL%
)

echo Build success!

:: Copy to openmesh-win project libs folder (creating it if needed)
set "TARGET_DIR=%~dp0..\..\openmesh-win\libs"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

copy /Y openmesh_core.dll "%TARGET_DIR%"
copy /Y openmesh_core.h "%TARGET_DIR%"

:: Also copy to Debug output for immediate use
set "DEBUG_OUT=%~dp0..\..\openmesh-win\bin\Debug\net10.0-windows"
if exist "%DEBUG_OUT%" (
    copy /Y openmesh_core.dll "%DEBUG_OUT%"
)

echo Copied files to %TARGET_DIR%

popd
endlocal
