#!/usr/bin/env bash
# ==============================================================================
# Linux / macOS / WSL Launcher for RHEL Keytab Simulator
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "         RHEL 7+ Kerberos Keytab Manager Simulation Environment                 "
echo "================================================================================"
echo ""

if ! command -v docker &>/dev/null; then
    echo "[ERROR] Docker is not installed or not in PATH."
    echo "Please install Docker to run the containerized simulation."
    echo "Alternatively, you can run the standalone Python simulator: python3 simulation/simulate_standalone.py"
    exit 1
fi

echo "[1/3] Building RHEL-compatible Simulation Container..."
docker build -t rhel-keytab-sim -f simulation/Dockerfile .

echo ""
echo "[2/3] Choose Startup Mode:"
echo "  [1] Launch Interactive Keytab Manager directly (./keytab_manager.sh)"
echo "  [2] Launch Automated Test Suite (./test_keytab_manager.sh)"
echo "  [3] Open Interactive RHEL Bash Shell"
echo ""

read -r -p "Select option [1, 2, 3 - Default: 1]: " choice
choice="${choice:-1}"

echo ""
echo "[3/3] Starting Container..."

case "$choice" in
    1)
        docker run -it --rm \
            -v "$PWD:/workspace" \
            -w /workspace \
            rhel-keytab-sim bash -c "chmod +x /workspace/keytab_manager.sh && /workspace/keytab_manager.sh"
        ;;
    2)
        docker run -it --rm \
            -v "$PWD:/workspace" \
            -w /workspace \
            rhel-keytab-sim bash -c "chmod +x /workspace/*.sh && /workspace/test_keytab_manager.sh"
        ;;
    3)
        docker run -it --rm \
            -v "$PWD:/workspace" \
            -w /workspace \
            rhel-keytab-sim bash
        ;;
    *)
        docker run -it --rm \
            -v "$PWD:/workspace" \
            -w /workspace \
            rhel-keytab-sim bash -c "chmod +x /workspace/keytab_manager.sh && /workspace/keytab_manager.sh"
        ;;
esac
