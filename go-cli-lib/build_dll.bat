@echo off
setlocal enabledelayedexpansion

:: Set CGO_ENABLED
set CGO_ENABLED=1

:: Add MinGW/GCC to PATH if not already present
if exist "C:\msys64\ucrt64\bin" (
    set "PATH=C:\msys64\ucrt64\bin;%PATH%"
)

:: Navigate to the Go embedded core directory
pushd "%~dp0\cmd\openmesh-win-core-embedded"

echo [BUILD] Building OpenMesh Go Core DLL...
go build -tags with_clash_api -buildmode=c-shared -o openmesh_core.dll .
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed with code %ERRORLEVEL%!
    popd
    exit /b %ERRORLEVEL%
)

echo [BUILD] Build success.

:: Copy to openmesh-win project libs folder (creating it if needed)
set "TARGET_DIR=%~dp0..\openmesh-win\libs"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo [COPY] Copying to libs: %TARGET_DIR%
copy /Y openmesh_core.dll "%TARGET_DIR%"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to copy to libs!
) else (
    echo [COPY] Success copying to libs.
)

copy /Y openmesh_core.h "%TARGET_DIR%"

:: Copy MinGW dependencies if they exist
if exist "C:\msys64\ucrt64\bin\libwinpthread-1.dll" (
    echo [COPY] Copying libwinpthread-1.dll
    copy /Y "C:\msys64\ucrt64\bin\libwinpthread-1.dll" "%TARGET_DIR%"
)

:: Also copy to Debug output for immediate use
set "DEBUG_OUT=%~dp0..\openmesh-win\bin\Debug\net10.0-windows\libs"
if exist "%DEBUG_OUT%" (
    echo [COPY] Copying to Debug output libs: %DEBUG_OUT%
    copy /Y openmesh_core.dll "%DEBUG_OUT%"
    set "COPY_ERR=!ERRORLEVEL!"
    if exist "C:\msys64\ucrt64\bin\libwinpthread-1.dll" (
        copy /Y "C:\msys64\ucrt64\bin\libwinpthread-1.dll" "%DEBUG_OUT%"
    )
    if not "!COPY_ERR!"=="0" (
        echo [WARNING] Failed to copy to Debug output libs. File may be locked by a running app.
        echo [ACTION] Stop the application and rebuild so Debug picks up the new DLL from libs.
    ) else (
        echo [COPY] Success copying to Debug output libs.
    )
)

popd
endlocal
