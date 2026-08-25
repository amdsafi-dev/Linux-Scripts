@echo off
REM ==============================================================================
REM Windows CMD Launcher for RHEL Keytab Simulator
REM ==============================================================================

echo ================================================================================
echo          RHEL 7+ Kerberos Keytab Manager Simulation Environment                 
echo ================================================================================
echo.

where docker >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker is not installed or not in PATH.
    echo Please start Docker Desktop or install Docker to run the containerized simulation.
    echo Alternatively, you can run the standalone Python simulator: python simulation/simulate_standalone.py
    pause
    exit /b 1
)

cd /d "%~dp0"

echo [1/3] Building RHEL-compatible Simulation Container...
docker build -t rhel-keytab-sim -f simulation/Dockerfile .
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker build failed.
    pause
    exit /b 1
)

echo.
echo [2/3] Choose Startup Mode:
echo   [1] Launch General Keytab Manager (keytab_manager.sh)
echo   [2] Launch AES Keytab Merge & NFS Migrator (keytab_merge_migrator.sh)
echo   [3] Run General Keytab Test Suite (test_keytab_manager.sh)
echo   [4] Run AES Keytab Merge Test Suite (test_keytab_merge.sh)
echo   [5] Open Interactive RHEL 9 Bash Shell
echo.

set /p choice="Select option [1-5 - Default: 1]: "
if "%choice%"=="" set choice=1

echo.
echo [3/3] Starting Container...

if "%choice%"=="1" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_manager.sh"
) else if "%choice%"=="2" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_merge_migrator.sh"
) else if "%choice%"=="3" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/test_keytab_manager.sh"
) else if "%choice%"=="4" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/test_keytab_merge.sh"
) else if "%choice%"=="5" (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash
) else (
    docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_manager.sh"
)
