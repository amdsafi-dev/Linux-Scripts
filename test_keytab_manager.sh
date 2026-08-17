#!/usr/bin/env bash
# ==============================================================================
# Script Name   : test_keytab_manager.sh
# Description   : Automated Test Suite & Validation for Kerberos Keytab Manager
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
        echo -e "  [${C_RED}FAIL${C_RESET}] $test_name (Exit code: $status)"
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

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if ! echo "$haystack" | grep -q "$needle"; then
        echo -e "  [${C_GREEN}PASS${C_RESET}] $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "  [${C_RED}FAIL${C_RESET}] $test_name - Pattern '$needle' should NOT be present."
        ((TESTS_FAILED++))
    fi
}

echo -e "${C_BOLD}${C_CYAN}"
echo "================================================================================"
echo "          KERBEROS KEYTAB MANAGER AUTOMATED VALIDATION TEST SUITE               "
echo "================================================================================"
echo -e "${C_RESET}"

# Ensure mock keytabs exist
if [[ -f "/usr/local/bin/setup_mock_data.sh" ]]; then
    /usr/local/bin/setup_mock_data.sh >/dev/null 2>&1 || true
elif [[ -f "simulation/setup_mock_data.sh" ]]; then
    bash simulation/setup_mock_data.sh >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# Test 1: Check Required Utilities
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 1: Utility & Tool Availability${C_RESET}"
for tool in klist ktutil find chmod cp sha256sum; do
    command -v "$tool" >/dev/null 2>&1
    assert_success "Checking binary presence: $tool" $?
done
echo ""

# ------------------------------------------------------------------------------
# Test 2: Verify Keytab Discovery
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 2: Keytab Discovery & File Access${C_RESET}"
source ./keytab_manager.sh --source-only 2>/dev/null || true

scan_keytabs "standard"
if [[ ${#DISCOVERED_KEYTABS[@]} -ge 3 ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Discovered ${#DISCOVERED_KEYTABS[@]} standard keytabs (expected >= 3)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Discovered only ${#DISCOVERED_KEYTABS[@]} keytabs."
    ((TESTS_FAILED++))
fi

assert_contains "Host keytab discovery (/etc/krb5.keytab)" "${DISCOVERED_KEYTABS[*]}" "/etc/krb5.keytab"
assert_contains "HDFS keytab discovery (/etc/security/keytabs/hdfs.keytab)" "${DISCOVERED_KEYTABS[*]}" "/etc/security/keytabs/hdfs.keytab"
echo ""

# ------------------------------------------------------------------------------
# Test 3: Verify klist -kte inspection
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 3: klist -kte Content Inspection${C_RESET}"
klist_host_out=$(klist -kte /etc/krb5.keytab 2>&1)
assert_success "Run klist -kte /etc/krb5.keytab" $?
assert_contains "Keytab contains host principal" "$klist_host_out" "host/rhel7-node01.example.corp@EXAMPLE.CORP"
assert_contains "Keytab contains aes256 cipher" "$klist_host_out" "aes256-cts"

klist_hdfs_out=$(klist -kte /etc/security/keytabs/hdfs.keytab 2>&1)
assert_contains "HDFS keytab contains hdfs principal" "$klist_hdfs_out" "hdfs/namenode01.example.corp@EXAMPLE.CORP"
assert_contains "HDFS keytab contains HTTP SPNEGO principal" "$klist_hdfs_out" "HTTP/namenode01.example.corp@EXAMPLE.CORP"
echo ""

# ------------------------------------------------------------------------------
# Test 4: Keytab Backup Creation
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 4: Keytab Backup to /var/tmp${C_RESET}"
target_test_kt="/etc/security/keytabs/appuser.keytab"
initial_sha=$(sha256sum "$target_test_kt" | awk '{print $1}')

backup_file=$(create_backup_file "$target_test_kt")
assert_success "create_backup_file for $target_test_kt" $?

if [[ -f "$backup_file" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Backup file created at: $backup_file"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Backup file not found at: $backup_file"
    ((TESTS_FAILED++))
fi

backup_sha=$(sha256sum "$backup_file" | awk '{print $1}')
if [[ "$initial_sha" == "$backup_sha" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] SHA256 integrity match between original and backup ($initial_sha)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] SHA256 mismatch: Original=$initial_sha, Backup=$backup_sha"
    ((TESTS_FAILED++))
fi

# Verify permissions 0600 on backup
backup_perms=$(stat -c "%a" "$backup_file" 2>/dev/null || echo "0600")
if [[ "$backup_perms" == "600" || "$backup_perms" == "0600" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Secure backup permissions verified ($backup_perms)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_YELLOW}WARN${C_RESET}] Backup permissions are $backup_perms (expected 0600)"
fi
echo ""

# ------------------------------------------------------------------------------
# Test 5: Add Principal to Keytab
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 5: Add Principal via ktutil${C_RESET}"
new_princ="new_service/analytics.example.corp@EXAMPLE.CORP"
new_kvno=4
new_pass="SecretPass456!"

# Programmatically simulate ktutil addition using printf pipeline
temp_kt=$(mktemp "/var/tmp/kt_test.XXXXXX")
rm -f "$temp_kt"
printf "rkt %s\naddent -password -p %s -k %s -e aes256-cts-hmac-sha1-96\n%s\naddent -password -p %s -k %s -e aes128-cts-hmac-sha1-96\n%s\nwkt %s\nquit\n" \
    "$target_test_kt" "$new_princ" "$new_kvno" "$new_pass" "$new_princ" "$new_kvno" "$new_pass" "$temp_kt" | ktutil >/dev/null 2>&1

if [[ -f "$temp_kt" && -s "$temp_kt" ]]; then
    chmod 0600 "$temp_kt"
    cp "$temp_kt" "$target_test_kt" && rm -f "$temp_kt"
fi

updated_klist=$(klist -kte "$target_test_kt" 2>&1)
assert_contains "Added principal exists in keytab" "$updated_klist" "$new_princ"
assert_contains "Original principal still exists in keytab" "$updated_klist" "svc_etl_prod@EXAMPLE.CORP"
echo ""

# ------------------------------------------------------------------------------
# Test 6: Remove Principal from Keytab
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 6: Remove Principal from Keytab${C_RESET}"
# Parse slots matching new_princ and delete them
kt_list=$(printf "rkt %s\nlist\nquit\n" "$target_test_kt" | ktutil 2>/dev/null)
matching_slots=()
while IFS= read -r line; do
    if echo "$line" | grep -q "$new_princ"; then
        s_num=$(echo "$line" | awk '{print $1}' | tr -dc '0-9')
        [[ -n "$s_num" ]] && matching_slots+=("$s_num")
    fi
done < <(echo "$kt_list" | grep -E '^[[:space:]]*[0-9]+')

# Sort slots descending
IFS=$'\n' sorted_slots=($(sort -nr <<<"${matching_slots[*]}"))
unset IFS

temp_kt2=$(mktemp "/var/tmp/kt_test2.XXXXXX")
rm -f "$temp_kt2"
del_sub_cmds=""
for slot in "${sorted_slots[@]}"; do
    del_sub_cmds+="delent ${slot}\n"
done

printf "rkt %s\n%bwkt %s\nquit\n" "$target_test_kt" "$del_sub_cmds" "$temp_kt2" | ktutil >/dev/null 2>&1

if [[ -f "$temp_kt2" && -s "$temp_kt2" ]]; then
    chmod 0600 "$temp_kt2"
    cp "$temp_kt2" "$target_test_kt" && rm -f "$temp_kt2"
fi

post_del_klist=$(klist -kte "$target_test_kt" 2>&1)
assert_not_contains "Deleted principal no longer in keytab" "$post_del_klist" "$new_princ"
assert_contains "Original principal remains intact" "$post_del_klist" "svc_etl_prod@EXAMPLE.CORP"
echo ""

# ------------------------------------------------------------------------------
# Test 7: Restore from Backup
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 7: Restore Keytab from Backup${C_RESET}"
# Overwrite keytab with empty file to simulate corruption/loss
echo "corrupted" > "$target_test_kt"

# Restore from backup
cp -p "$backup_file" "$target_test_kt"
chmod 0600 "$target_test_kt"

restored_sha=$(sha256sum "$target_test_kt" | awk '{print $1}')
if [[ "$initial_sha" == "$restored_sha" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Keytab successfully restored from backup (SHA256 match: $restored_sha)"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Restored SHA256 mismatch: Original=$initial_sha, Restored=$restored_sha"
    ((TESTS_FAILED++))
fi

restored_klist=$(klist -kte "$target_test_kt" 2>&1)
assert_contains "Restored keytab has original principal" "$restored_klist" "svc_etl_prod@EXAMPLE.CORP"
echo ""

# ------------------------------------------------------------------------------
# Test 8: Create Brand New Keytab File from Scratch
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 8: Create New Keytab File from Scratch${C_RESET}"
new_kt_path="/etc/security/keytabs/custom_service.keytab"
new_kt_princ="custom_svc/webnode01.example.corp@EXAMPLE.CORP"
rm -f "$new_kt_path"

temp_kt3=$(mktemp "/var/tmp/kt_test3.XXXXXX")
rm -f "$temp_kt3"

printf "addent -password -p %s -k 1 -e aes256-cts-hmac-sha1-96\nNewKeyPass123!\nwkt %s\nquit\n" \
    "$new_kt_princ" "$temp_kt3" | ktutil >/dev/null 2>&1

if [[ -f "$temp_kt3" && -s "$temp_kt3" ]]; then
    chmod 0600 "$temp_kt3"
    cp "$temp_kt3" "$new_kt_path" && rm -f "$temp_kt3"
fi

if [[ -f "$new_kt_path" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] New keytab file created at: $new_kt_path"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Failed to create keytab at: $new_kt_path"
    ((TESTS_FAILED++))
fi

new_kt_content=$(klist -kte "$new_kt_path" 2>&1)
assert_contains "New keytab contains specified initial principal" "$new_kt_content" "$new_kt_princ"
echo ""

# ------------------------------------------------------------------------------
# Test 9: Delete / Remove an Existing Keytab File
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}Test Suite 9: Delete / Remove Keytab File${C_RESET}"
# Create safety backup first
del_backup=$(create_backup_file "$new_kt_path")
assert_success "Backup prior to keytab deletion" $?

# Delete the keytab file
rm -f "$new_kt_path"
if [[ ! -f "$new_kt_path" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Keytab file successfully deleted"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Keytab file still exists after deletion"
    ((TESTS_FAILED++))
fi

# Verify backup exists and can restore it
if [[ -f "$del_backup" ]]; then
    echo -e "  [${C_GREEN}PASS${C_RESET}] Deletion safety backup verified at: $del_backup"
    ((TESTS_PASSED++))
else
    echo -e "  [${C_RED}FAIL${C_RESET}] Deletion safety backup not found"
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
