@echo off
REM MOP 移动端 APK 编译脚本 (Windows)
REM 版本: mop-v0115-0530

setlocal enabledelayedexpansion

REM 配置
set PROJECT_DIR=%~dp0..\mobile
set OUTPUT_DIR=%~dp0..\build_output
set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=release
set TARGET_ARCH=%2
if "%TARGET_ARCH%"=="" set TARGET_ARCH=all

echo ==========================================
echo MOP 移动端 APK 编译脚本
echo 版本: mop-v0115-0530
echo ==========================================
echo.

REM 检查 Flutter
echo [INFO] 检查 Flutter 环境...
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter 未安装或未在 PATH 中
    echo [INFO] 请安装 Flutter SDK: https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)

flutter --version | findstr /C:"Flutter"
echo.

REM 检查 Java
echo [INFO] 检查 Java 环境...
where java >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Java 未安装
    echo [INFO] 请安装 Java JDK 17
    pause
    exit /b 1
)

java -version
echo.

REM 准备构建环境
echo [INFO] 准备构建环境...
cd /d "%PROJECT_DIR%"

if not exist "pubspec.yaml" (
    echo [ERROR] 未找到 pubspec.yaml，请检查项目目录
    pause
    exit /b 1
)

echo [INFO] 清理旧的构建文件...
flutter clean

echo [INFO] 获取项目依赖...
flutter pub get

if errorlevel 1 (
    echo [ERROR] 依赖获取失败
    pause
    exit /b 1
)

echo [INFO] 依赖获取完成
echo.

REM 构建 APK
echo [INFO] 开始构建 APK (类型: %BUILD_TYPE%, 架构: %TARGET_ARCH%)...

if "%TARGET_ARCH%"=="all" (
    set TARGET_PLATFORM=android-arm,android-arm64
    set SPLIT_FLAG=--split-per-abi
) else if "%TARGET_ARCH%"=="arm" (
    set TARGET_PLATFORM=android-arm
    set SPLIT_FLAG=
) else if "%TARGET_ARCH%"=="arm64" (
    set TARGET_PLATFORM=android-arm64
    set SPLIT_FLAG=
) else (
    echo [ERROR] 不支持的架构: %TARGET_ARCH%
    pause
    exit /b 1
)

if "%BUILD_TYPE%"=="release" (
    echo [INFO] 构建 Release APK...
    flutter build apk --release --target-platform %TARGET_PLATFORM% %SPLIT_FLAG%
) else if "%BUILD_TYPE%"=="debug" (
    echo [INFO] 构建 Debug APK...
    flutter build apk --debug --target-platform %TARGET_PLATFORM% %SPLIT_FLAG%
) else (
    echo [ERROR] 不支持的构建类型: %BUILD_TYPE%
    pause
    exit /b 1
)

if errorlevel 1 (
    echo [ERROR] APK 构建失败
    pause
    exit /b 1
)

echo [INFO] APK 构建完成
echo.

REM 复制输出文件
echo [INFO] 复制输出文件...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

if "%TARGET_ARCH%"=="all" (
    copy "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-armeabi-v7a-%BUILD_TYPE%.apk" "%OUTPUT_DIR%\" >nul 2>&1
    copy "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-arm64-v8a-%BUILD_TYPE%.apk" "%OUTPUT_DIR%\" >nul 2>&1
)

copy "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-%BUILD_TYPE%.apk" "%OUTPUT_DIR%\" >nul 2>&1

echo [INFO] 输出文件已复制到: %OUTPUT_DIR%
echo.

REM 显示构建信息
echo [INFO] 构建信息：
echo   项目目录: %PROJECT_DIR%
echo   输出目录: %OUTPUT_DIR%
echo   构建类型: %BUILD_TYPE%
echo   目标架构: %TARGET_ARCH%
echo.

if exist "%OUTPUT_DIR%\*.apk" (
    echo [INFO] 生成的 APK 文件：
    dir /b "%OUTPUT_DIR%\*.apk"
) else (
    echo [WARN] 未找到 APK 文件
)

echo.
echo ==========================================
echo 构建完成！
echo ==========================================
pause
