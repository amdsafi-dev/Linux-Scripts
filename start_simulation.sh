#!/usr/bin/env bash
# ==============================================================================
# Bash Launcher for RHEL Keytab Simulator (Linux / macOS / WSL)
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
    echo "Please start Docker Desktop or install Docker to run the containerized simulation."
    echo "Alternatively, run the standalone Python simulator: python3 simulation/simulate_standalone.py"
    exit 1
fi

echo "[1/3] Building RHEL-compatible Simulation Container..."
docker build -t rhel-keytab-sim -f simulation/Dockerfile .

echo ""
echo "[2/3] Choose Startup Mode:"
echo "  [1] Launch General Keytab Manager (./keytab_manager.sh)"
echo "  [2] Launch AES Keytab Merge & NFS Migrator (./keytab_merge_migrator.sh)"
echo "  [3] Run General Keytab Test Suite (./test_keytab_manager.sh)"
echo "  [4] Run AES Keytab Merge Test Suite (./test_keytab_merge.sh)"
echo "  [5] Open Interactive RHEL 9 Bash Shell"
echo ""

read -r -p "Select option [1-5 - Default: 1]: " choice
choice="${choice:-1}"

echo ""
echo "[3/3] Starting Container..."

case "$choice" in
    1)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_manager.sh"
        ;;
    2)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_merge_migrator.sh"
        ;;
    3)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/test_keytab_manager.sh"
        ;;
    4)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/test_keytab_merge.sh"
        ;;
    5)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash
        ;;
    *)
        docker run -it --rm -v "${PWD}:/workspace" -w /workspace rhel-keytab-sim bash -c "sed -i 's/\r$//' /workspace/*.sh /workspace/simulation/*.sh && chmod +x /workspace/*.sh /workspace/simulation/*.sh && /workspace/keytab_manager.sh"
        ;;
esac
