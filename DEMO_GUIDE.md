# Demonstration & Implementation Guide: Keytab Operations

This document provides exact, step-by-step instructions for demonstrating and testing the three core Kerberos keytab operations using the interactive **Kerberos Keytab Manager** utility.

---

## 📋 Scenarios at a Glance

| Scenario | Operation | Target Keytab | Principal / Details | Menu Sequence |
| :--- | :--- | :--- | :--- | :--- |
| **Scenario 1** | Add dummy principal to existing keytab | `/etc/security/keytabs/hive.keytab` | `dummy_analyst/node01.example.corp@EXAMPLE.CORP` | `4` $\rightarrow$ Select `hive.keytab` $\rightarrow$ `1` |
| **Scenario 2** | Create a new keytab file with new principal | `/etc/security/keytabs/dummy_service.keytab` | `dummy_app/server01.example.corp@EXAMPLE.CORP` | `5` |
| **Scenario 3** | Delete principal from existing keytab | `/etc/security/keytabs/hive.keytab` | `dummy_analyst/node01.example.corp@EXAMPLE.CORP` | `4` $\rightarrow$ Select `hive.keytab` $\rightarrow$ `2` |

---

## 🚀 Environment Launch Options

You can run this demonstration in any of the three environments:

### Option A: Zero-Docker Python Standalone Simulator (Fastest)
```bash
python simulation/simulate_standalone.py
```

### Option B: Containerized RHEL Simulation (Docker)
- **Windows (PowerShell)**: `.\start_simulation.ps1`
- **Windows (CMD)**: `start_simulation.bat`
- **Linux / macOS / WSL**: `./start_simulation.sh`

### Option C: Direct Execution on RHEL 7 / 8 / 9 Server
```bash
sudo ./keytab_manager.sh
```

---

## 🧪 Scenario 1: Add a Dummy Principal to an Existing Keytab

### Objective
Add `dummy_analyst/node01.example.corp@EXAMPLE.CORP` into `/etc/security/keytabs/hive.keytab` without altering the existing `hive/hiveserver2` entries.

### Keystroke Steps:
1. **Main Menu**: Type `4` and press `[ENTER]` (**Add or Remove Principal from a keytab file**).
2. **Select Keytab**: Select `/etc/security/keytabs/hive.keytab` (enter number, e.g. `3`).
3. **Safety Backup**: When asked `Create an automatic backup now? [Y/n]`:
   - Press `[ENTER]` or `y` (Saves a backup to `/var/tmp/keytab_backups`).
4. **Choose Operation**: Type `1` (**Add a Principal**).
5. **Step 1 (Principal)**:
   ```text
   dummy_analyst/node01.example.corp@EXAMPLE.CORP
   ```
6. **Step 2 (KVNO)**:
   - Press `[ENTER]` (Default: `1`).
7. **Step 3 (Encryption Types)**:
   - Press `[ENTER]` (Option `1`: Recommended Standard Set — `aes256-cts`, `aes128-cts`, `arcfour-hmac`).
8. **Step 4 (Password)**:
   - Enter password: `DummyP@ssw0rd123`
   - Confirm password: `DummyP@ssw0rd123`
9. **Step 5 (Confirm Write)**:
   - Press `[ENTER]` or `y`.

### Expected Verification:
The updated `klist -kte` will display both the original `hive/hiveserver2` entries and the 3 newly added encryption slots for `dummy_analyst`.

---

## 🧪 Scenario 2: Create a Brand New Keytab File with a New Principal

### Objective
Create a fresh keytab file at `/etc/security/keytabs/dummy_service.keytab` with `0600` permissions and initial principal `dummy_app/server01.example.corp@EXAMPLE.CORP`.

### Keystroke Steps:
1. **Main Menu**: Type `5` and press `[ENTER]` (**Create a New Keytab File**).
2. **Step 1 (New Keytab Path)**:
   ```text
   /etc/security/keytabs/dummy_service.keytab
   ```
3. **Step 2 (Initial Principal)**:
   ```text
   dummy_app/server01.example.corp@EXAMPLE.CORP
   ```
4. **Step 3 (KVNO & Encryption Types)**:
   - **KVNO**: Press `[ENTER]` (Default: `1`).
   - **Encryption Types**: Press `[ENTER]` (Option `1`: Standard Set).
5. **Step 4 (Password)**:
   - Enter password: `ServiceSecurePass99!`
   - Confirm password: `ServiceSecurePass99!`

### Expected Verification:
1. The tool reports `[SUCCESS] New keytab created successfully at: /etc/security/keytabs/dummy_service.keytab`.
2. `klist -kte` confirms the newly created keytab with `dummy_app` entries.
3. Return to Main Menu and select Option `1` (**List Keytab Files**) to see `/etc/security/keytabs/dummy_service.keytab` listed.

---

## 🧪 Scenario 3: Delete an Existing Principal from a Keytab

### Objective
Safely remove all entries matching `dummy_analyst/node01.example.corp@EXAMPLE.CORP` from `/etc/security/keytabs/hive.keytab`, ensuring original `hive` credentials remain untouched.

### Keystroke Steps:
1. **Main Menu**: Type `4` and press `[ENTER]` (**Add or Remove Principal from a keytab file**).
2. **Select Keytab**: Select `/etc/security/keytabs/hive.keytab`.
3. **Choose Operation**: Type `2` (**Remove a Principal / Entry**).
4. **Choose Removal Mode**:
   - Type `2` (**Remove ALL entries matching a specific Principal Name**).
5. **Enter Principal to Remove**:
   ```text
   dummy_analyst/node01.example.corp@EXAMPLE.CORP
   ```
6. **Confirm Deletion**:
   - Type `y` and press `[ENTER]`.

### Expected Verification:
1. The tool reports `[SUCCESS] Principal dummy_analyst/node01.example.corp@EXAMPLE.CORP removed successfully!`.
2. `klist -kte` shows only the original `hive/hiveserver2.example.corp@EXAMPLE.CORP` entries remaining.

---

## 🧪 Scenario 4: AES Keytab Merge & NFS Mount Migration (`keytab_merge_migrator.sh`)

### Objective
Execute an enterprise zero-downtime keytab upgrade by merging an incoming AES keytab into an existing keytab, taking in-place backups, capturing pre-migration system state (`/etc/krb5.conf`, `/etc/fstab`, `df -h`, `mount | egrep "nfs|cifs"`), transitioning NFS shares through `sec=sys` -> `sec=krb5`, and running an automated filesystem sanity check.

### Step-by-Step Execution:
1. **Launch the Migrator**:
   ```bash
   chmod +x keytab_merge_migrator.sh
   sudo ./keytab_merge_migrator.sh
   ```
2. **Step 1: Snapshots & In-Place Backups** (Option `1`):
   - Select target keytab: `/etc/security/keytabs/nfs_service.keytab`.
   - In-place backup created: `/etc/security/keytabs/backup/nfs_service.keytab.<timestamp>.bak` (`0600`).
   - System state captured in `/etc/security/keytabs/backup/system_snapshots_<timestamp>/`.
3. **Step 2: Transition NFS to `sec=sys`** (Option `2`):
   - Active Kerberized NFS shares are safely remounted with `sec=sys` to prevent I/O deadlocks during keytab rollover.
4. **Step 3: Merge AES Keytab** (Option `3`):
   - Target: `/etc/security/keytabs/nfs_service.keytab`
   - Source: `/tmp/incoming_keytabs/new_aes_nfs.keytab`
   - `ktutil` merges entries and preserves exact original ownership and `0600` permissions.
5. **Step 4: Remount NFS with `sec=krb5`** (Option `4`):
   - Restores Kerberos encryption on active NFS shares.
6. **Step 5: Filesystem Sanity Check** (Option `5`):
   - Captures post-migration state, compares `df -h` and `mount` tables against pre-migration baseline, and performs live responsiveness probes on all mount points.

---

## 🔄 Automated Validation Scripts

- **Test General Keytab Manager**:
  ```bash
  ./test_keytab_manager.sh
  ```
- **Test AES Merge & NFS Migrator**:
  ```bash
  python simulation/test_merge_flow.py
  ```
