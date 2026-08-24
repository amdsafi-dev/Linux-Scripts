# Kerberos Keytab Manager & AES NFS Migrator for RHEL 7+

A production-grade, interactive Bash suite for managing MIT Kerberos Keytab files and executing zero-downtime **AES Encryption Merges & Kerberized NFS Mount Migrations** on Red Hat Enterprise Linux (RHEL 7, 8, 9), CentOS, Rocky Linux, and AlmaLinux.

Accompanied by a containerized **RHEL Simulation Environment**, an automated validation test suite, and a standalone Python simulator.

---

## 🌟 Utilities Included

### 1. `keytab_merge_migrator.sh` (AES Keytab Merge & NFS Migration Utility)
Specialized enterprise utility for merging incoming AES keytabs into production keytabs while managing NFS mount security:
- **In-Place Keytab Backup**: Automatically archives keytabs inside `$(dirname "$keytab")/backup/` with strict `0600` permissions and SHA256 integrity logging.
- **Pre-Migration Snapshots**: Backs up `/etc/krb5.conf`, `/etc/fstab`, and captures baseline states of `df -h` and `mount | egrep "nfs|cifs"`.
- **NFS Pre-Merge Transition (`sec=sys`)**: Remounts active Kerberized NFS shares with `sec=sys` before modifying keytabs to prevent I/O deadlocks.
- **Atomic AES Merge via `ktutil`**: Merges new AES encryption entries (`aes256-cts-hmac-sha1-96`, `aes128-cts-hmac-sha1-96`) into the production keytab while strictly preserving original owner, group, and permissions (`0600`/`0400`).
- **NFS Post-Merge Transition (`sec=krb5`)**: Remounts NFS shares back with Kerberos security (`sec=krb5`, `sec=krb5i`, `sec=krb5p`).
- **Filesystem Sanity & Comparison Engine**: Automatically compares pre vs post `df -h` and mount tables, diffs option changes, and runs live responsiveness probes against all mount points.
- **Guided Migration Wizard**: Executes the entire 5-step migration safely with step-by-step confirmation.

### 2. `keytab_manager.sh` (General Keytab Administration Utility)
- Discovers keytabs in standard paths (`/etc/krb5.keytab`, `/etc/security/keytabs/`, `/var/kerberos/`, `/etc/hadoop/`, etc.) or via full system scan.
- Inspects keytabs with formatted `klist -kte`.
- Creates backups to `/var/tmp/keytab_backups`.
- Adds or removes principals interactively by slot number or principal name.
- Creates brand new keytab files from scratch or deletes obsolete keytabs.
- Restores corrupted keytabs from backup archives.

---

## 🚀 Quickstart & Usage

### 1. Running Keytab AES Merge & NFS Migrator
```bash
chmod +x keytab_merge_migrator.sh
sudo ./keytab_merge_migrator.sh
```

### 2. Running General Keytab Manager
```bash
chmod +x keytab_manager.sh
sudo ./keytab_manager.sh
```

---

## 🧪 Simulation Environment (Testing without RHEL Servers)

You can safely test the script in a containerized RHEL 9 (Rocky Linux) environment pre-configured with mock keytabs (`host`, `hdfs`, `HTTP`, `hive`, `appuser`, `yarn`).

### Option A: One-Click Launchers

- **Windows (PowerShell)**:
  ```powershell
  .\start_simulation.ps1
  ```
- **Windows (Command Prompt)**:
  ```cmd
  start_simulation.bat
  ```
- **Linux / macOS / WSL**:
  ```bash
  chmod +x start_simulation.sh
  ./start_simulation.sh
  ```

### Option B: Docker Compose

```bash
docker compose -f simulation/docker-compose.yml run --rm keytab-sim ./keytab_manager.sh
```

### Option C: Standalone Python Simulator (Zero-Docker)

If Docker is not running, test the exact interactive experience using Python:
```bash
python simulation/simulate_standalone.py
```

---

## 🔬 Automated Test Suite

Run the automated test suite inside the simulation container to verify all test categories:

```bash
docker run -it --rm -v "%cd%:/workspace" -w /workspace rhel-keytab-sim ./test_keytab_manager.sh
```

### Tests Covered:
- [x] Test 1: Required tools (`klist`, `ktutil`, `find`, `chmod`, `cp`, `sha256sum`)
- [x] Test 2: Standard Keytab discovery
- [x] Test 3: `klist -kte` inspection and encryption type validation
- [x] Test 4: Keytab backup to `/var/tmp` and SHA256 verification
- [x] Test 5: Principal addition with multiple encryption ciphers
- [x] Test 6: Principal deletion by name and slot index
- [x] Test 7: Keytab restore from backup and hash verification
- [x] Test 8: Create brand new keytab file from scratch
- [x] Test 9: Delete keytab file with safety backup

---

## 📁 Repository Structure

```
.
├── keytab_manager.sh             # Main interactive Bash script
├── test_keytab_manager.sh        # Automated test suite & test harness
├── start_simulation.ps1          # Windows PowerShell simulation runner
├── start_simulation.bat          # Windows CMD simulation runner
├── start_simulation.sh           # Linux / macOS simulation runner
├── simulation/
│   ├── Dockerfile                # RHEL-compatible Rocky Linux 9 image
│   ├── docker-compose.yml        # Docker Compose service definition
│   ├── setup_mock_data.sh        # Seed script for realistic mock keytabs
│   ├── simulate_standalone.py    # Zero-Docker Python interactive simulator
│   └── README.md                 # Simulation setup guide
└── README.md                     # Main documentation
```
