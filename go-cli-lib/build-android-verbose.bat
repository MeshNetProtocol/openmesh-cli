@echo off
chcp 65001 >nul
cls
echo ========================================
echo   OpenMesh Android AAR Builder
echo   (详细日志版)
echo ========================================
echo.

REM 配置
set OUTPUT_DIR=.\lib\android
set FRAMEWORK_NAME=OpenMeshGo
set GO_TAGS=with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_clash_api,with_conntrack,tfogo_checklinkname0
set ANDROID_API=21
set DEST_LIBS_DIR=..\openmesh-android\app\libs

echo [编译配置]
echo   GO_TAGS: %GO_TAGS%
echo   Android API: %ANDROID_API%
echo   输出目录：%OUTPUT_DIR%
echo   目标目录：%DEST_LIBS_DIR%
echo.

REM 检查 Go
echo [1/7] 检查 Go 环境...
where go >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 go 命令，请先安装 Go
    pause
    exit /b 1
)
go version
echo   [OK] Go 环境正常
echo.

REM 设置环境变量
echo [2/7] 配置环境变量...
set GOPROXY=https://proxy.golang.org,direct
set GOSUMDB=sum.golang.org
set GOFLAGS=-mod=mod -p=4
set GOMAXPROCS=4
set JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
echo   [OK] 环境变量已设置
echo.

REM 安装 gomobile
echo [3/7] 检查/安装 gomobile...
set GOMOBILE=%GOPATH%\bin\gomobile.exe
if not exist "%GOMOBILE%" (
    echo   正在安装 gomobile...
    go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11
    go install github.com/sagernet/gomobile/cmd/gobind@v0.1.11
    echo   [OK] gomobile 安装完成
) else (
    echo   [OK] gomobile 已存在
)

echo   初始化 gomobile...
gomobile init
echo   [OK] gomobile 初始化完成
echo.

REM 创建输出目录
echo [4/7] 准备输出目录...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
echo   [OK] 输出目录：%OUTPUT_DIR%
echo.

REM 定义包
set PKG1=github.com/sagernet/sing-box/experimental/libbox
set PKG2=github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface

echo [5/7] 开始编译 AAR（详细日志）...
echo   包含标签：%GO_TAGS%
echo   目标文件：%OUTPUT_DIR%\%FRAMEWORK_NAME%.aar
echo.
echo   ----------------------------------------
echo   编译开始（请等待 2-5 分钟）...
echo   ----------------------------------------
echo.

REM 执行编译（带详细日志）
gomobile bind ^
    -target=android ^
    -androidapi=%ANDROID_API% ^
    -tags="%GO_TAGS%" ^
    -ldflags="-buildid= -s -w -checklinkname=0" ^
    -v ^
    -x ^
    -o .\lib\android\%FRAMEWORK_NAME%.aar ^
    %PKG1% %PKG2%

if %errorlevel% neq 0 (
    echo.
    echo   ----------------------------------------
    echo   [失败] 编译失败！请检查上述错误信息
    echo   ----------------------------------------
    pause
    exit /b 1
)

echo.
echo   ----------------------------------------
echo   [成功] 编译完成！
echo   ----------------------------------------
echo.

echo [6/7] 验证并复制文件...

REM 验证
if exist ".\lib\android\%FRAMEWORK_NAME%.aar" (
    for %%A in (".\lib\android\%FRAMEWORK_NAME%.aar") do set SIZE=%%~zA
    set /a SIZEMB=%SIZE%/1048576
    
    echo   [OK] AAR 文件生成成功
    echo       路径：.\lib\android\%FRAMEWORK_NAME%.aar
    echo       大小：%SIZEMB% MB
    
    REM 创建目标目录
    if not exist "%DEST_LIBS_DIR%" mkdir "%DEST_LIBS_DIR%"
    
    REM 复制到 openmesh-android/app/libs
    echo   正在复制到 %DEST_LIBS_DIR%...
    copy /y ".\lib\android\%FRAMEWORK_NAME%.aar" "%DEST_LIBS_DIR%\" >nul
    echo   [OK] 已复制 AAR 到 %DEST_LIBS_DIR%
    
    REM Sources jar
    if exist ".\lib\android\%FRAMEWORK_NAME%-sources.jar" (
        copy /y ".\lib\android\%FRAMEWORK_NAME%-sources.jar" "%DEST_LIBS_DIR%\" >nul
        echo   [OK] 已复制 Sources JAR
    )
) else (
    echo   [失败] AAR 文件未生成
    pause
    exit /b 1
)

echo.
echo [7/7] 完成！
echo.
echo ========================================
echo   编译成功！
echo ========================================
echo.
echo 下一步操作：
echo   1. 打开 Android Studio
echo   2. File ^> Sync Project with Gradle Files
echo   3. Build ^> Clean Project
echo   4. Build ^> Rebuild Project
echo   5. 运行应用测试 VPN
echo.
echo 按任意键退出...
pause >nul
