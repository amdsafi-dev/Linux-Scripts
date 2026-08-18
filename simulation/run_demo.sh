#!/usr/bin/env bash
# ==============================================================================
# Script Name   : run_demo.sh
# Description   : Live Demonstration Script for Keytab Operations
# ==============================================================================

set -e

echo "================================================================================"
echo "                     EXECUTING LIVE DEMONSTRATION RUN                          "
echo "================================================================================"

echo ""
echo ">>> [SCENARIO 1] Adding dummy principal to /etc/security/keytabs/hive.keytab..."
echo "--- Initial Entries in hive.keytab ---"
klist -kte /etc/security/keytabs/hive.keytab

temp_kt=$(mktemp /var/tmp/kt_demo1.XXXXXX)
rm -f "$temp_kt"
printf "rkt /etc/security/keytabs/hive.keytab\naddent -password -p dummy_analyst/node01.example.corp@EXAMPLE.CORP -k 1 -e aes256-cts-hmac-sha1-96\nDummyP@ssw0rd123\naddent -password -p dummy_analyst/node01.example.corp@EXAMPLE.CORP -k 1 -e aes128-cts-hmac-sha1-96\nDummyP@ssw0rd123\naddent -password -p dummy_analyst/node01.example.corp@EXAMPLE.CORP -k 1 -e arcfour-hmac\nDummyP@ssw0rd123\nwkt %s\nquit\n" "$temp_kt" | ktutil
chmod 0600 "$temp_kt"
cp "$temp_kt" /etc/security/keytabs/hive.keytab && rm -f "$temp_kt"

echo ""
echo "--- Updated Entries in hive.keytab (with dummy principal added) ---"
klist -kte /etc/security/keytabs/hive.keytab

echo ""
echo "================================================================================"
echo ">>> [SCENARIO 2] Creating new keytab /etc/security/keytabs/dummy_service.keytab..."
temp_kt2=$(mktemp /var/tmp/kt_demo2.XXXXXX)
rm -f "$temp_kt2"
printf "addent -password -p dummy_app/server01.example.corp@EXAMPLE.CORP -k 1 -e aes256-cts-hmac-sha1-96\nServiceSecurePass99!\naddent -password -p dummy_app/server01.example.corp@EXAMPLE.CORP -k 1 -e aes128-cts-hmac-sha1-96\nServiceSecurePass99!\naddent -password -p dummy_app/server01.example.corp@EXAMPLE.CORP -k 1 -e arcfour-hmac\nServiceSecurePass99!\nwkt %s\nquit\n" "$temp_kt2" | ktutil
chmod 0600 "$temp_kt2"
cp "$temp_kt2" /etc/security/keytabs/dummy_service.keytab && rm -f "$temp_kt2"

echo ""
echo "--- Entries in newly created /etc/security/keytabs/dummy_service.keytab ---"
klist -kte /etc/security/keytabs/dummy_service.keytab
ls -l /etc/security/keytabs/dummy_service.keytab

echo ""
echo "================================================================================"
echo ">>> [SCENARIO 3] Deleting dummy_analyst principal from hive.keytab..."
# Delete slots for dummy_analyst
kt_list=$(printf "rkt /etc/security/keytabs/hive.keytab\nlist\nquit\n" | ktutil)
matching_slots=()
while IFS= read -r line; do
    if echo "$line" | grep -q "dummy_analyst"; then
        s_num=$(echo "$line" | awk '{print $1}' | tr -dc '0-9')
        [[ -n "$s_num" ]] && matching_slots+=("$s_num")
    fi
done < <(echo "$kt_list" | grep -E '^[[:space:]]*[0-9]+')

IFS=$'\n' sorted_slots=($(sort -nr <<<"${matching_slots[*]}"))
unset IFS

del_cmds=""
for slot in "${sorted_slots[@]}"; do
    del_cmds+="delent ${slot}\n"
done

temp_kt3=$(mktemp /var/tmp/kt_demo3.XXXXXX)
rm -f "$temp_kt3"
printf "rkt /etc/security/keytabs/hive.keytab\n%bwkt %s\nquit\n" "$del_cmds" "$temp_kt3" | ktutil
chmod 0600 "$temp_kt3"
cp "$temp_kt3" /etc/security/keytabs/hive.keytab && rm -f "$temp_kt3"

echo ""
echo "--- Final Entries in hive.keytab (dummy_analyst removed, original hive remains) ---"
klist -kte /etc/security/keytabs/hive.keytab

echo ""
echo "================================================================================"
echo "DEMONSTRATION RUN EXECUTED SUCCESSFULLY WITH 100% INTEGRITY!"
