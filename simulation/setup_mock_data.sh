#!/usr/bin/env bash
# ==============================================================================
# Script Name   : setup_mock_data.sh
# Description   : Generates realistic mock Kerberos keytabs for RHEL 7+ simulation
# ==============================================================================

set -e

echo "=== Initializing Mock Kerberos Keytabs for RHEL 7+ Simulation ==="

# 1. Ensure required directories exist
mkdir -p /etc/security/keytabs
mkdir -p /etc/hadoop/conf
mkdir -p /var/kerberos/krb5kdc
mkdir -p /var/tmp/keytab_backups

# Helper to create mock keytab with ktutil
create_mock_keytab() {
    local kpath="$1"
    local princ="$2"
    local kvno="$3"
    local pass="$4"
    local mode="${5:-0600}"

    echo "Creating mock keytab: $kpath ($princ, kvno=$kvno)..."
    
    # Remove existing if any
    rm -f "$kpath"

    # Use ktutil to generate valid binary keytab entries
    ktutil <<EOF
addent -password -p $princ -k $kvno -e aes256-cts-hmac-sha1-96
$pass
addent -password -p $princ -k $kvno -e aes128-cts-hmac-sha1-96
$pass
addent -password -p $princ -k $kvno -e arcfour-hmac
$pass
wkt $kpath
quit
EOF

    chmod "$mode" "$kpath"
}

# 2. Generate Host Keytab (/etc/krb5.keytab)
create_mock_keytab "/etc/krb5.keytab" "host/rhel7-node01.example.corp@EXAMPLE.CORP" 1 "HostP@ssw0rd123" "0600"

# 3. Generate HDFS Service Keytab with dual principals (hdfs + HTTP)
echo "Creating mock keytab: /etc/security/keytabs/hdfs.keytab (dual principal)..."
rm -f /etc/security/keytabs/hdfs.keytab
ktutil <<EOF
addent -password -p hdfs/namenode01.example.corp@EXAMPLE.CORP -k 2 -e aes256-cts-hmac-sha1-96
HdfsSecurePass1
addent -password -p hdfs/namenode01.example.corp@EXAMPLE.CORP -k 2 -e aes128-cts-hmac-sha1-96
HdfsSecurePass1
addent -password -p HTTP/namenode01.example.corp@EXAMPLE.CORP -k 2 -e aes256-cts-hmac-sha1-96
HttpSpnegoPass1
addent -password -p HTTP/namenode01.example.corp@EXAMPLE.CORP -k 2 -e aes128-cts-hmac-sha1-96
HttpSpnegoPass1
wkt /etc/security/keytabs/hdfs.keytab
quit
EOF
chmod 0400 /etc/security/keytabs/hdfs.keytab

# 4. Generate Hive Service Keytab
create_mock_keytab "/etc/security/keytabs/hive.keytab" "hive/hiveserver2.example.corp@EXAMPLE.CORP" 1 "HiveSecret99!" "0600"

# 5. Generate ETL Application User Keytab
create_mock_keytab "/etc/security/keytabs/appuser.keytab" "svc_etl_prod@EXAMPLE.CORP" 3 "ETLApp_P@ssw0rd" "0600"

# 6. Generate Hadoop YARN Keytab
create_mock_keytab "/etc/hadoop/conf/yarn.keytab" "yarn/resourcemanager01.example.corp@EXAMPLE.CORP" 1 "YarnRM_Pass#1" "0600"

echo ""
echo "Mock keytabs generated successfully:"
ls -la /etc/krb5.keytab /etc/security/keytabs/*.keytab /etc/hadoop/conf/*.keytab
echo "================================================================="
