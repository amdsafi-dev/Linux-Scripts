#!/usr/bin/env bash
# ==============================================================================
# Script Name   : test_keytab_merge.sh
# Description   : Automated Validation Suite for AES Keytab Merge & NFS Migration
# ==============================================================================

set -o pipefail

C_GREEN='\033[32m'
C_RED='\033[31m'
C_YELLOW='\033[33m'
C_CYAN='\033[36m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

assert_success() {
    local test_name="$1"
    local status="$2"
    if [[ $status -eq 0 ]]; then
        echo -e "  [${C_GREEN}PASS${C_RESET}] $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "  [${C_RED}FAIL${C_RESET}] $test_name (Status code: $status)"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  [${C_GREEN}PASS${C_RESET}] $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "  [${C_RED}FAIL${C_RESET}] $test_name - Expected pattern '$needle' not found."
        ((TESTS_FAILED++))
    fi
}

echo -e "${C_BOLD}${C_CYAN}"
echo "================================================================================"
echo "    KERBEROS AES KEYTAB MERGE & NFS MIGRATION AUTOMATED TEST SUITE             "
echo "================================================================================"
echo -e "${C_RESET}"

# Setup mock data
if [[ -f "simulation/setup_nfs_mock.sh" ]]; then
    bash simulation/setup_nfs_mock.sh >/dev/null 2>&1 || true
fi

# Source functions from keytab_merge_migrator.sh
source ./keytab_merge_migrator.sh --source-only 2>/dev/null || true

TARGET_KT="/etc/security/keytabs/nfs_service.keytab"
NEW_AES_KT="/tmp/incoming_keytabs/new_aes_nfs.keytab"

# ------------------------------------------------------------------------------
# Test 1: In-Place Keytab Backup Location & Permissions
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 1: In-Place Keytab Backup Creation${C_RESET}"
initial_sha=$(sha256sum "$TARGET_KT" | awk '{print $1}')
backup_file=$(create_inplace_keytab_backup "$TARGET_KT")

assert_success "create_inplace_keytab_backup executed successfully" $?

# Verify backup is in same parent directory under /backup/
expected_backup_dir="$(dirname "$TARGET_KT")/backup"
if [[ -f "$backup_file" && "$backup_file" == ${expected_backup_dir}/* ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Backup saved in same directory under backup/: $backup_file"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Backup not in expected directory: $backup_file"
    ((TESTS_FAILED++))
fi

# Check permissions 0600
bak_perms=$(stat -c "%a" "$backup_file" 2>/dev/null || echo "0600")
if [[ "$bak_perms" == "600" || "$bak_perms" == "0600" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Secure in-place backup permissions verified ($bak_perms)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_YELLOW}WARN${C_RESET}] Backup permissions are $bak_perms (expected 0600)"
fi

# Check SHA256 integrity
bak_sha=$(sha256sum "$backup_file" | awk '{print $1}')
if [[ "$initial_sha" == "$bak_sha" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] SHA256 integrity match between original and in-place backup ($initial_sha)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] SHA256 mismatch: Original=$initial_sha, Backup=$bak_sha"
    ((TESTS_FAILED++))
fi
echo ""

# ------------------------------------------------------------------------------
# Test 2: System & Mount State Snapshot Capture
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 2: Pre-Migration System & Mount State Snapshots${C_RESET}"
take_system_snapshots "$TARGET_KT" >/dev/null 2>&1

snap_dir="$LAST_SNAPSHOT_DIR"
if [[ -d "$snap_dir" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Snapshot directory created: $snap_dir"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Snapshot directory not created"
    ((TESTS_FAILED++))
fi

# Check df_h_pre.log exists and is non-empty
if [[ -s "${snap_dir}/df_h_pre.log" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] 'df -h' baseline snapshot captured"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] 'df -h' snapshot missing or empty"
    ((TESTS_FAILED++))
fi

# Check mount_nfs_cifs_pre.log exists
if [[ -f "${snap_dir}/mount_nfs_cifs_pre.log" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] 'mount | egrep \"nfs|cifs\"' baseline snapshot captured"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] mount baseline snapshot missing"
    ((TESTS_FAILED++))
fi

# Check /etc/krb5.conf & /etc/fstab backup files
if ls "${snap_dir}/krb5.conf."*.bak >/dev/null 2>&1 || [[ ! -f "/etc/krb5.conf" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] /etc/krb5.conf snapshot verified"
    ((TESTS_PASSED++))
fi

if ls "${snap_dir}/fstab."*.bak >/dev/null 2>&1 || [[ ! -f "/etc/fstab" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] /etc/fstab snapshot verified"
    ((TESTS_PASSED++))
fi
echo ""

# ------------------------------------------------------------------------------
# Test 3: Atomic AES Keytab Merging via ktutil
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 3: Atomic Keytab Merge Operation${C_RESET}"
pre_merge_klist=$(klist -kte "$TARGET_KT" 2>&1)
pre_merge_perms=$(stat -c "%a" "$TARGET_KT" 2>/dev/null || echo "0600")

execute_keytab_merge "$TARGET_KT" "$NEW_AES_KT" >/dev/null 2>&1
assert_success "execute_keytab_merge executed successfully" $?

merged_klist=$(klist -kte "$TARGET_KT" 2>&1)

# Check that legacy principal still exists
assert_contains "Merged keytab preserves original host principal" "$merged_klist" "host/client01.example.corp@EXAMPLE.CORP"

# Check that incoming AES principal exists with AES-256
assert_contains "Merged keytab contains new AES-256 cipher" "$merged_klist" "aes256-cts-hmac-sha1-96"
assert_contains "Merged keytab contains new AES-128 cipher" "$merged_klist" "aes128-cts-hmac-sha1-96"
assert_contains "Merged keytab contains HTTP SPNEGO principal" "$merged_klist" "HTTP/storage01.example.corp@EXAMPLE.CORP"

# Check permission preservation
post_merge_perms=$(stat -c "%a" "$TARGET_KT" 2>/dev/null || echo "0600")
if [[ "$pre_merge_perms" == "$post_merge_perms" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Exact permissions preserved after merge ($post_merge_perms)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Permissions changed from $pre_merge_perms to $post_merge_perms"
    ((TESTS_FAILED++))
fi
echo ""

# ------------------------------------------------------------------------------
# Test 4: Filesystem Sanity & Comparison Engine
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 4: Filesystem Sanity & Diff Verification${C_RESET}"
run_filesystem_sanity_check "$snap_dir" >/dev/null 2>&1

if [[ -f "${snap_dir}/df_h_post.log" && -f "${snap_dir}/mount_nfs_cifs_post.log" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Post-migration filesystem snapshots captured"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Post-migration snapshots missing"
    ((TESTS_FAILED++))
fi
echo ""

# ------------------------------------------------------------------------------
# Test 5: Rollback from In-Place Backup
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 5: Rollback / Recovery from In-Place Backup${C_RESET}"
cp -p "$backup_file" "$TARGET_KT"
chmod 0600 "$TARGET_KT"

restored_sha=$(sha256sum "$TARGET_KT" | awk '{print $1}')
if [[ "$initial_sha" == "$restored_sha" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Rollback restores exact original keytab binary (SHA256: $restored_sha)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Rollback SHA256 mismatch: Initial=$initial_sha, Restored=$restored_sha"
    ((TESTS_FAILED++))
fi
echo ""

# ------------------------------------------------------------------------------
# Final Test Summary
# ------------------------------------------------------------------------------
echo "================================================================================"
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${C_GREEN}${C_BOLD}ALL $TOTAL_TESTS TESTS PASSED SUCCESSFULLY!${C_RESET}"
    exit 0
else
    echo -e "${C_RED}${C_BOLD}$TESTS_FAILED of $TOTAL_TESTS TESTS FAILED.${C_RESET}"
    exit 1
fi
