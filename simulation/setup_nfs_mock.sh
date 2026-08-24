#!/usr/bin/env bash
# ==============================================================================
# Script Name   : setup_nfs_mock.sh
# Description   : Seeds mock existing keytab, new incoming AES keytab,
#                 mock /etc/krb5.conf, /etc/fstab, and mock mount data for testing.
# ==============================================================================

set -e

echo "=== Initializing Mock Keytabs and System Files for Merge & Migration Testing ==="

# 1. Ensure Directories exist
mkdir -p /etc/security/keytabs
mkdir -p /tmp/incoming_keytabs
mkdir -p /mnt/nfs_finance
mkdir -p /mnt/nfs_data

# 2. Mock /etc/krb5.conf if missing
if [[ ! -f "/etc/krb5.conf" ]]; then
    cat << 'EOF' > /etc/krb5.conf
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 default_realm = EXAMPLE.CORP
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 EXAMPLE.CORP = {
  kdc = kdc01.example.corp
  admin_server = kdc01.example.corp
 }

[domain_realm]
 .example.corp = EXAMPLE.CORP
 example.corp = EXAMPLE.CORP
EOF
    chmod 0644 /etc/krb5.conf
fi

# 3. Mock /etc/fstab entry if missing
if [[ ! -f "/etc/fstab" ]] || ! grep -q "nfs" /etc/fstab; then
    cat << 'EOF' >> /etc/fstab
# Mock NFS shares for testing
nfs-server01.example.corp:/exports/finance /mnt/nfs_finance nfs sec=krb5,rw,hard,intr 0 0
nfs-server01.example.corp:/exports/data    /mnt/nfs_data    nfs sec=krb5,ro,hard,intr 0 0
EOF
fi

# 4. Generate Existing Production Keytab (e.g. /etc/security/keytabs/nfs_service.keytab)
echo "Generating existing production keytab: /etc/security/keytabs/nfs_service.keytab ..."
rm -f /etc/security/keytabs/nfs_service.keytab
temp_e=$(mktemp /var/tmp/kt_e.XXXXXX); rm -f "$temp_e"
ktutil <<EOF
addent -password -p nfs/storage01.example.corp@EXAMPLE.CORP -k 1 -e arcfour-hmac
LegacyPass#123
addent -password -p host/client01.example.corp@EXAMPLE.CORP -k 1 -e arcfour-hmac
LegacyHostPass!
wkt $temp_e
quit
EOF
chmod 0600 "$temp_e"
cp "$temp_e" /etc/security/keytabs/nfs_service.keytab && rm -f "$temp_e"

# 5. Generate New Incoming AES Keytab (/tmp/incoming_keytabs/new_aes_nfs.keytab)
echo "Generating incoming new AES keytab: /tmp/incoming_keytabs/new_aes_nfs.keytab ..."
rm -f /tmp/incoming_keytabs/new_aes_nfs.keytab
temp_n=$(mktemp /var/tmp/kt_n.XXXXXX); rm -f "$temp_n"
ktutil <<EOF
addent -password -p nfs/storage01.example.corp@EXAMPLE.CORP -k 2 -e aes256-cts-hmac-sha1-96
NewAESPass!2026
addent -password -p nfs/storage01.example.corp@EXAMPLE.CORP -k 2 -e aes128-cts-hmac-sha1-96
NewAESPass!2026
addent -password -p HTTP/storage01.example.corp@EXAMPLE.CORP -k 2 -e aes256-cts-hmac-sha1-96
NewHttpAESPass!
wkt $temp_n
quit
EOF
chmod 0600 "$temp_n"
cp "$temp_n" /tmp/incoming_keytabs/new_aes_nfs.keytab && rm -f "$temp_n"

echo ""
echo "=== Mock environment initialized successfully ==="
echo "Existing keytab : /etc/security/keytabs/nfs_service.keytab"
klist -kte /etc/security/keytabs/nfs_service.keytab
echo ""
echo "Incoming AES kt : /tmp/incoming_keytabs/new_aes_nfs.keytab"
klist -kte /tmp/incoming_keytabs/new_aes_nfs.keytab
echo "=================================================="
