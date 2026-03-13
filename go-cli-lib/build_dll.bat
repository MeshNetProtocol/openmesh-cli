@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "CORE_DIR=%SCRIPT_DIR%cmd\openmesh-win-core-embedded"
set "SOURCE_LIBS=%SCRIPT_DIR%..\openmesh-win\libs"
set "DEBUG_LIBS=%SCRIPT_DIR%..\openmesh-win\bin\Debug\net10.0-windows\libs"
set "RELEASE_LIBS=%SCRIPT_DIR%..\openmesh-win\bin\Release\net10.0-windows\libs"
set "MINGW_BIN=C:\msys64\ucrt64\bin"

set "CGO_ENABLED=1"
if exist "%MINGW_BIN%" (
    set "PATH=%MINGW_BIN%;%PATH%"
)

if not exist "%CORE_DIR%" (
    echo [ERROR] Core directory not found: %CORE_DIR%
    exit /b 1
)

pushd "%CORE_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to enter core directory: %CORE_DIR%
    exit /b 1
)

echo [BUILD] Building OpenMesh Go Core DLL...
go build -tags with_clash_api -buildmode=c-shared -o openmesh_core.dll .
if errorlevel 1 (
    set "BUILD_EXIT=%ERRORLEVEL%"
    echo [ERROR] Build failed with code !BUILD_EXIT!.
    popd
    exit /b !BUILD_EXIT!
)
echo [BUILD] Build success.

call :copy_artifacts "%SOURCE_LIBS%" required
if errorlevel 1 (
    set "COPY_EXIT=%ERRORLEVEL%"
    popd
    exit /b !COPY_EXIT!
)

call :copy_artifacts "%DEBUG_LIBS%" optional
if errorlevel 1 (
    set "COPY_EXIT=%ERRORLEVEL%"
    popd
    exit /b !COPY_EXIT!
)

call :copy_artifacts "%RELEASE_LIBS%" optional
if errorlevel 1 (
    set "COPY_EXIT=%ERRORLEVEL%"
    popd
    exit /b !COPY_EXIT!
)

popd
echo [SUCCESS] Built and synced openmesh_core.dll into the C# project.
exit /b 0

:copy_artifacts
set "DEST_DIR=%~1"
set "COPY_MODE=%~2"

if /I "%COPY_MODE%"=="optional" (
    if not exist "%DEST_DIR%" (
        echo [SKIP] Output directory not present: %DEST_DIR%
        exit /b 0
    )
)

if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

copy /Y "openmesh_core.dll" "%DEST_DIR%\" >nul
if errorlevel 1 (
    if /I "%COPY_MODE%"=="required" (
        echo [ERROR] Failed to copy openmesh_core.dll to %DEST_DIR%
        exit /b 1
    )
    echo [WARNING] Failed to copy openmesh_core.dll to %DEST_DIR%. The file may be locked by a running app.
    exit /b 0
)

copy /Y "openmesh_core.h" "%DEST_DIR%\" >nul
if errorlevel 1 (
    if /I "%COPY_MODE%"=="required" (
        echo [ERROR] Failed to copy openmesh_core.h to %DEST_DIR%
        exit /b 1
    )
    echo [WARNING] Failed to copy openmesh_core.h to %DEST_DIR%.
    exit /b 0
)

if exist "%MINGW_BIN%\libwinpthread-1.dll" (
    copy /Y "%MINGW_BIN%\libwinpthread-1.dll" "%DEST_DIR%\" >nul
    if errorlevel 1 (
        if /I "%COPY_MODE%"=="required" (
            echo [ERROR] Failed to copy libwinpthread-1.dll to %DEST_DIR%
            exit /b 1
        )
        echo [WARNING] Failed to copy libwinpthread-1.dll to %DEST_DIR%.
        exit /b 0
    )
)

echo [COPY] Synced artifacts to %DEST_DIR%
exit /b 0
