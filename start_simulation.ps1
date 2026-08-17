# ==============================================================================
# PowerShell Launcher for RHEL Keytab Simulator
# ==============================================================================

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "         RHEL 7+ Kerberos Keytab Manager Simulation Environment                 " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker availability
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Docker is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please start Docker Desktop or install Docker to run the containerized simulation." -ForegroundColor Yellow
    Write-Host "Alternatively, you can run the standalone Python simulator: python simulation/simulate_standalone.py" -ForegroundColor Cyan
    Exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location "$ScriptDir"

Write-Host "[1/3] Building RHEL-compatible Simulation Container..." -ForegroundColor Yellow
docker build -t rhel-keytab-sim -f simulation/Dockerfile .

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker build failed." -ForegroundColor Red
    Exit 1
}

Write-Host ""
Write-Host "[2/3] Choose Startup Mode:" -ForegroundColor Cyan
Write-Host "  [1] Launch Interactive Keytab Manager directly (./keytab_manager.sh)" -ForegroundColor Green
Write-Host "  [2] Launch Automated Test Suite (./test_keytab_manager.sh)" -ForegroundColor Green
Write-Host "  [3] Open Interactive RHEL Bash Shell (explore / test manually)" -ForegroundColor Green
Write-Host ""

$choice = Read-Host "Select option [1, 2, 3 - Default: 1]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

Write-Host ""
Write-Host "[3/3] Starting Container..." -ForegroundColor Green

switch ($choice) {
    "1" {
        docker run -it --rm `
            -v "${PWD}:/workspace" `
            -w /workspace `
            rhel-keytab-sim bash -c "chmod +x /workspace/keytab_manager.sh && /workspace/keytab_manager.sh"
    }
    "2" {
        docker run -it --rm `
            -v "${PWD}:/workspace" `
            -w /workspace `
            rhel-keytab-sim bash -c "chmod +x /workspace/*.sh && /workspace/test_keytab_manager.sh"
    }
    "3" {
        docker run -it --rm `
            -v "${PWD}:/workspace" `
            -w /workspace `
            rhel-keytab-sim bash
    }
    Default {
        docker run -it --rm `
            -v "${PWD}:/workspace" `
            -w /workspace `
            rhel-keytab-sim bash -c "chmod +x /workspace/keytab_manager.sh && /workspace/keytab_manager.sh"
    }
}
