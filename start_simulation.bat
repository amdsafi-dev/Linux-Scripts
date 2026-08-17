@echo off
REM ==============================================================================
REM Batch Launcher for RHEL Keytab Simulator (Windows CMD)
REM ==============================================================================

echo ================================================================================
echo          RHEL 7+ Kerberos Keytab Manager Simulation Environment
echo ================================================================================
echo.

where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker is not installed or not running.
    echo Please install Docker Desktop or run python simulation/simulate_standalone.py
    pause
    exit /b 1
)

echo [1/3] Building simulation image...
docker build -t rhel-keytab-sim -f simulation/Dockerfile .
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker build failed.
    pause
    exit /b 1
)

echo.
echo [2/3] Choose Startup Mode:
echo   [1] Launch Interactive Keytab Manager directly (./keytab_manager.sh)
echo   [2] Launch Automated Test Suite (./test_keytab_manager.sh)
echo   [3] Open Interactive RHEL Bash Shell
echo.
set /p choice="Select option [1, 2, 3 - Default: 1]: "
if "%choice%"=="" set choice=1

echo.
echo [3/3] Starting Container...
if "%choice%"=="1" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "chmod +x /workspace/keytab_manager.sh && /workspace/keytab_manager.sh"
) else if "%choice%"=="2" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "chmod +x /workspace/*.sh && /workspace/test_keytab_manager.sh"
) else (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash
)
