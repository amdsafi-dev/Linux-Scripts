# Kerberos Keytab Manager for RHEL 7+

A production-grade, interactive Bash utility for managing MIT Kerberos Keytab files on Red Hat Enterprise Linux (RHEL 7, 8, 9), CentOS, Rocky Linux, and AlmaLinux.

Accompanied by a containerized **RHEL Simulation Environment** and an automated validation test suite.

---

## 🌟 Key Features

1. **List Keytab Files in Server**:
   - Automatically scans standard locations (`/etc/krb5.keytab`, `/etc/security/keytabs/`, `/var/kerberos/`, `/etc/hadoop/`, `/etc/hive/`, etc.).
   - Supports deep full-filesystem search across `/`.
   - Displays file size, owner, group, and octal permissions (`0600`, `0400`).

2. **Inspect Keytab Content (`klist -kte`)**:
   - Inspect all discovered keytabs at once or select a specific keytab.
   - Shows Key Version Number (KVNO), Timestamp, Principal Name, and Encryption Type (AES-256, AES-128, RC4).

3. **Take Backup of Keytab Files (`/var/tmp`)**:
   - Backs up single or all keytabs to `/var/tmp/keytab_backups/<keytab>.<timestamp>.bak`.
   - Preserves strict file permissions (`0600`) and metadata.
   - Generates SHA256 checksums in `backup_manifest.log` for integrity tracking.

4. **Add or Remove Principal from Keytab**:
   - **Safety First**: Automatically prompts to create a safety backup before applying any modification.
   - **Add Principal**: Guided step-by-step wizard (Principal name, KVNO, encryption types `aes256-cts-hmac-sha1-96`, `aes128-cts`, `arcfour-hmac`, and password with verification).
   - **Remove Principal**: Remove by exact slot index or bulk remove all entries matching a principal name.
   - Uses `ktutil` with atomic temp-file write and validation.

5. **Create a New Keytab File**:
   - Creates a brand new keytab from scratch at any specified file path.
   - Auto-creates parent directories and guides initial principal/password setup.
   - Sets secure `0600` permissions and validates with `klist -kte`.

6. **Delete / Remove an Existing Keytab File**:
   - Prompts for keytab file selection and shows current entries.
   - Automatically offers to create an immediate safety backup in `/var/tmp/keytab_backups`.
   - Double-confirms deletion before removing the file.

7. **Restore from Backup**:
   - Discovers all backups in `/var/tmp` and `/var/tmp/keytab_backups`.
   - Inspects backup content before restoring.
   - Confirms overwrite and applies secure permissions (`0600`).

---

## 🚀 Quickstart & Usage

### 1. Running directly on RHEL 7 / 8 / 9 / CentOS / Rocky / AlmaLinux

Ensure `krb5-workstation` is installed:
```bash
# RHEL 7 / 8 / 9 / Rocky / AlmaLinux / CentOS
sudo yum install -y krb5-workstation

# Make executable and run
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
