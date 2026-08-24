#!/usr/bin/env python3
"""
================================================================================
RHEL Kerberos Keytab Manager - Standalone Python Terminal Simulator
================================================================================
This script provides an interactive simulation of the RHEL 7+ Keytab Manager
environment directly inside Python without requiring Docker or a native Linux OS.
"""

import os
import sys
import time
import shutil
import hashlib
from datetime import datetime

# ANSI Color codes
C_CYAN = "\033[36m\033[1m"
C_GREEN = "\033[32m\033[1m"
C_YELLOW = "\033[33m\033[1m"
C_RED = "\033[31m\033[1m"
C_BLUE = "\033[34m\033[1m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_RESET = "\033[0m"

# Simulated In-Memory & Virtual File Store
MOCK_KEYTABS = {
    "/etc/krb5.keytab": [
        {"slot": 1, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "host/rhel7-node01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "host/rhel7-node01.example.corp@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
        {"slot": 3, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "host/rhel7-node01.example.corp@EXAMPLE.CORP", "enctype": "arcfour-hmac"},
    ],
    "/etc/security/keytabs/hdfs.keytab": [
        {"slot": 1, "kvno": 2, "timestamp": "08/17/26 10:00:00", "principal": "hdfs/namenode01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": 2, "timestamp": "08/17/26 10:00:00", "principal": "hdfs/namenode01.example.corp@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
        {"slot": 3, "kvno": 2, "timestamp": "08/17/26 10:00:00", "principal": "HTTP/namenode01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 4, "kvno": 2, "timestamp": "08/17/26 10:00:00", "principal": "HTTP/namenode01.example.corp@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
    ],
    "/etc/security/keytabs/hive.keytab": [
        {"slot": 1, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "hive/hiveserver2.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "hive/hiveserver2.example.corp@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
    ],
    "/etc/security/keytabs/nfs_service.keytab": [
        {"slot": 1, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "nfs/storage01.example.corp@EXAMPLE.CORP", "enctype": "arcfour-hmac"},
        {"slot": 2, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "host/client01.example.corp@EXAMPLE.CORP", "enctype": "arcfour-hmac"},
    ],
    "/tmp/incoming_keytabs/new_aes_nfs.keytab": [
        {"slot": 1, "kvno": 2, "timestamp": "08/24/26 11:00:00", "principal": "nfs/storage01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": 2, "timestamp": "08/24/26 11:00:00", "principal": "nfs/storage01.example.corp@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
        {"slot": 3, "kvno": 2, "timestamp": "08/24/26 11:00:00", "principal": "HTTP/storage01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
    ],
    "/etc/security/keytabs/appuser.keytab": [
        {"slot": 1, "kvno": 3, "timestamp": "08/17/26 10:00:00", "principal": "svc_etl_prod@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": 3, "timestamp": "08/17/26 10:00:00", "principal": "svc_etl_prod@EXAMPLE.CORP", "enctype": "aes128-cts-hmac-sha1-96"},
        {"slot": 3, "kvno": 3, "timestamp": "08/17/26 10:00:00", "principal": "svc_etl_prod@EXAMPLE.CORP", "enctype": "arcfour-hmac"},
    ],
    "/etc/hadoop/conf/yarn.keytab": [
        {"slot": 1, "kvno": 1, "timestamp": "08/17/26 10:00:00", "principal": "yarn/resourcemanager01.example.corp@EXAMPLE.CORP", "enctype": "aes256-cts-hmac-sha1-96"},
    ]
}

MOCK_NFS_MOUNTS = {
    "/mnt/nfs_finance": {"device": "nfs-server01.example.corp:/exports/finance", "type": "nfs", "opts": "rw,sec=krb5,hard,intr", "size": "500G", "used": "210G", "avail": "290G", "pcent": "42%"},
    "/mnt/nfs_data": {"device": "nfs-server01.example.corp:/exports/data", "type": "nfs", "opts": "ro,sec=krb5,hard,intr", "size": "2.0T", "used": "1.1T", "avail": "900G", "pcent": "55%"},
    "/mnt/cifs_reports": {"device": "//win-nas01.example.corp/reports", "type": "cifs", "opts": "rw,sec=krb5,vers=3.0", "size": "1.0T", "used": "450G", "avail": "550G", "pcent": "45%"}
}

MOCK_INPLACE_BACKUPS = {}
MOCK_SNAPSHOTS = {}

def clear_screen():
    os.system("cls" if os.name == "nt" else "clear")

def print_banner():
    clear_screen()
    print(f"{C_CYAN}================================================================================")
    print("      KERBEROS KEYTAB MANAGEMENT SIMULATOR (STANDALONE PYTHON ENVIRONMENT)      ")
    print(f"================================================================================{C_RESET}")

def press_enter():
    input(f"\n{C_DIM}Press [ENTER] to return to the menu...{C_RESET}")

def render_klist(path, entries):
    print(f"{C_BOLD}{C_BLUE}======================================================================{C_RESET}")
    print(f"{C_BOLD}Keytab File : {C_YELLOW}{path}{C_RESET}")
    print(f"{C_BOLD}{C_BLUE}======================================================================{C_RESET}")
    print(f"Keytab name: FILE:{path}")
    print(f"{C_BOLD}{'KVNO':<6} {'Timestamp':<18} {'Principal':<46} {'Encryption Type'}{C_RESET}")
    print("--------------------------------------------------------------------------------")
    for e in entries:
        print(f"{e['kvno']:<6} {e['timestamp']:<18} {e['principal']:<46} {e['enctype']}")

def select_keytab_dialog():
    paths = list(MOCK_KEYTABS.keys())
    print(f"{C_BOLD}{C_CYAN}=== Select a Keytab File ==={C_RESET}\n")
    for i, p in enumerate(paths, 1):
        print(f"  {C_GREEN}[{i:2d}]{C_RESET} {p:<45} {C_DIM}(Entries: {len(MOCK_KEYTABS[p])}, perms: 0600){C_RESET}")
    print(f"\n  {C_RED}[ 0]{C_RESET} Cancel / Go Back\n")
    
    choice = input(f"Select an option [1-{len(paths)}, 0]: ").strip()
    if choice == "0" or not choice.isdigit() or int(choice) < 1 or int(choice) > len(paths):
        return None
    return paths[int(choice) - 1]

def option_list_keytabs():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 1] Discovered Keytab Files on this Server{C_RESET}")
    print("================================================================================\n")
    print(f"Found {len(MOCK_KEYTABS)} keytab file(s):\n")
    print(f"{C_BOLD}{'NUM':<4} {'KEYTAB PATH':<45} {'ENTRIES':<10} {'OWNER:GROUP':<15} {'PERMS':<8} {'ACCESSIBLE'}{C_RESET}")
    print("--------------------------------------------------------------------------------")
    for i, (p, entries) in enumerate(MOCK_KEYTABS.items(), 1):
        print(f"[{i:<2}] {p:<45} {len(entries):<10} {'root:root':<15} {'0600':<8} {'YES'}")
    press_enter()

def option_klist_keytabs():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 2] Inspect Keytab Content (klist -kte){C_RESET}")
    print("================================================================================\n")
    print(f"  {C_GREEN}[1]{C_RESET} Inspect ALL keytabs")
    print(f"  {C_GREEN}[2]{C_RESET} Select a SPECIFIC keytab")
    print(f"  {C_RED}[0]{C_RESET} Cancel\n")
    choice = input("Enter choice [1, 2, 0]: ").strip()
    
    if choice == "1":
        print()
        for p, entries in MOCK_KEYTABS.items():
            render_klist(p, entries)
            print()
    elif choice == "2":
        sel = select_keytab_dialog()
        if sel:
            print()
            render_klist(sel, MOCK_KEYTABS[sel])
            print()
    press_enter()

def option_backup_keytabs():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 3] Backup Keytab Files to /var/tmp{C_RESET}")
    print("================================================================================\n")
    print(f"  {C_GREEN}[1]{C_RESET} Backup a SINGLE Keytab File")
    print(f"  {C_GREEN}[2]{C_RESET} Backup ALL Keytab Files")
    print(f"  {C_RED}[0]{C_RESET} Cancel\n")
    choice = input("Enter choice [1, 2, 0]: ").strip()
    
    if choice == "1":
        sel = select_keytab_dialog()
        if sel:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            bname = f"/var/tmp/keytab_backups/{os.path.basename(sel)}.{ts}.bak"
            MOCK_BACKUPS[bname] = {"orig": sel, "entries": [dict(e) for e in MOCK_KEYTABS[sel]], "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Backup created: {C_YELLOW}{bname}{C_RESET}")
            print(f"  Permissions: 0600 (root:root)")
            print(f"  SHA256     : {hashlib.sha256(bname.encode()).hexdigest()}")
    elif choice == "2":
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        for p in MOCK_KEYTABS:
            bname = f"/var/tmp/keytab_backups/{os.path.basename(p)}.{ts}.bak"
            MOCK_BACKUPS[bname] = {"orig": p, "entries": [dict(e) for e in MOCK_KEYTABS[p]], "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            print(f"  {C_GREEN}✓{C_RESET} Backed up: {p} -> {C_YELLOW}{bname}{C_RESET}")
        print(f"\n{C_GREEN}[SUCCESS]{C_RESET} All keytabs backed up successfully.")
    press_enter()

def option_modify_keytab():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 4] Add / Remove Principal from Keytab{C_RESET}")
    print("================================================================================\n")
    sel = select_keytab_dialog()
    if not sel:
        return
    
    while True:
        print(f"\n{C_BOLD}Active Keytab:{C_RESET} {C_YELLOW}{sel}{C_RESET}")
        print("--------------------------------------------------------------------------------")
        print(f"  {C_GREEN}[1]{C_RESET} Add a Principal")
        print(f"  {C_RED}[2]{C_RESET} Remove a Principal / Entry")
        print(f"  {C_CYAN}[3]{C_RESET} View Current Keytab Entries (klist -kte)")
        print(f"  {C_YELLOW}[0]{C_RESET} Return to Main Menu\n")
        sub_choice = input("Enter choice [1, 2, 3, 0]: ").strip()
        
        if sub_choice == "1":
            print(f"\n{C_BOLD}=== Add Principal ==={C_RESET}")
            princ = input("Enter Principal (e.g. user@EXAMPLE.COM) [or '0' / 'c' to cancel]: ").strip()
            if not princ or princ in ["0", "c", "C", "q", "Q", "cancel"]:
                print(f"{C_YELLOW}[INFO] Addition cancelled.{C_RESET}")
                continue
            kvno_in = input("KVNO [Default: 1, or 'c' to cancel]: ").strip()
            if kvno_in in ["c", "C", "q", "Q", "cancel"]:
                print(f"{C_YELLOW}[INFO] Addition cancelled.{C_RESET}")
                continue
            kvno = kvno_in or "1"
            print("Select Enctypes: [1] Standard Set (aes256, aes128, rc4) [2] aes256 only [0] Cancel")
            etype_c = input("Choice [1]: ").strip() or "1"
            if etype_c in ["0", "c", "C", "cancel"]:
                print(f"{C_YELLOW}[INFO] Addition cancelled.{C_RESET}")
                continue
            etypes = ["aes256-cts-hmac-sha1-96", "aes128-cts-hmac-sha1-96", "arcfour-hmac"] if etype_c == "1" else ["aes256-cts-hmac-sha1-96"]
            
            pwd = input("Enter Password: ")
            
            ts = datetime.now().strftime("%m/%d/%y %H:%M:%S")
            for et in etypes:
                slot = len(MOCK_KEYTABS[sel]) + 1
                MOCK_KEYTABS[sel].append({"slot": slot, "kvno": int(kvno), "timestamp": ts, "principal": princ, "enctype": et})
            
            print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Principal {princ} added to {sel}!")
            render_klist(sel, MOCK_KEYTABS[sel])
        elif sub_choice == "2":
            print(f"\n{C_BOLD}=== Remove Principal ==={C_RESET}")
            render_klist(sel, MOCK_KEYTABS[sel])
            print("\n  [1] Remove by Principal Name\n  [2] Remove by Slot Number\n  [0] Cancel / Go Back")
            del_c = input("Select [1, 2, 0]: ").strip()
            if del_c == "1":
                del_p = input("Enter Principal to delete [or '0' / 'c' to cancel]: ").strip()
                if not del_p or del_p in ["0", "c", "C", "q", "Q", "cancel"]:
                    print(f"{C_YELLOW}[INFO] Deletion cancelled.{C_RESET}")
                    continue
                before_len = len(MOCK_KEYTABS[sel])
                MOCK_KEYTABS[sel] = [e for e in MOCK_KEYTABS[sel] if e["principal"] != del_p]
                if len(MOCK_KEYTABS[sel]) < before_len:
                    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Principal {del_p} removed!")
                else:
                    print(f"\n{C_RED}[ERROR]{C_RESET} Principal {del_p} not found.")
            elif del_c == "2":
                slot_str = input("Enter Slot to delete [or '0' / 'c' to cancel]: ").strip()
                if not slot_str or slot_str in ["0", "c", "C", "q", "Q", "cancel"]:
                    print(f"{C_YELLOW}[INFO] Deletion cancelled.{C_RESET}")
                    continue
                if slot_str.isdigit():
                    s_idx = int(slot_str) - 1
                    if 0 <= s_idx < len(MOCK_KEYTABS[sel]):
                        removed = MOCK_KEYTABS[sel].pop(s_idx)
                        print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Removed slot for {removed['principal']}!")
                    else:
                        print(f"{C_RED}[ERROR] Invalid slot index.{C_RESET}")
        elif sub_choice == "3":
            print()
            render_klist(sel, MOCK_KEYTABS[sel])
        elif sub_choice == "0":
            break

def option_create_keytab():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 5] Create a New Keytab File{C_RESET}")
    print("================================================================================\n")
    path = input("Enter New Keytab Path (e.g. /etc/security/keytabs/myapp.keytab) [or '0' to cancel]: ").strip()
    if not path or path in ["0", "c", "C", "cancel"]:
        print(f"{C_YELLOW}[INFO] Creation cancelled.{C_RESET}")
        press_enter()
        return
    
    if path in MOCK_KEYTABS:
        ovw = input(f"File {path} already exists. Overwrite? [y/N]: ").strip()
        if not ovw.lower().startswith("y"):
            print(f"{C_YELLOW}[INFO] Creation aborted.{C_RESET}")
            press_enter()
            return

    princ = input("Enter Initial Principal (e.g. myapp/srv.corp.local@CORP.LOCAL) [or '0' to cancel]: ").strip()
    if not princ or princ in ["0", "c", "C", "cancel"]:
        print(f"{C_YELLOW}[INFO] Creation cancelled.{C_RESET}")
        press_enter()
        return

    kvno = input("KVNO [Default: 1]: ").strip() or "1"
    pwd = input("Enter Password: ")
    
    ts = datetime.now().strftime("%m/%d/%y %H:%M:%S")
    MOCK_KEYTABS[path] = [
        {"slot": 1, "kvno": int(kvno), "timestamp": ts, "principal": princ, "enctype": "aes256-cts-hmac-sha1-96"},
        {"slot": 2, "kvno": int(kvno), "timestamp": ts, "principal": princ, "enctype": "aes128-cts-hmac-sha1-96"},
        {"slot": 3, "kvno": int(kvno), "timestamp": ts, "principal": princ, "enctype": "arcfour-hmac"},
    ]
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} New keytab created at: {C_YELLOW}{path}{C_RESET}")
    render_klist(path, MOCK_KEYTABS[path])
    press_enter()

def option_delete_keytab():
    print_banner()
    print(f"{C_BOLD}${C_RED}[OPTION 6] Delete / Remove an Existing Keytab File{C_RESET}")
    print("================================================================================\n")
    sel = select_keytab_dialog()
    if not sel:
        return
    
    print(f"\nSelected Keytab for Deletion: {C_YELLOW}{sel}{C_RESET}")
    render_klist(sel, MOCK_KEYTABS[sel])
    
    bak_q = input("\nCreate a safety backup before deleting? [Y/n]: ").strip()
    if not bak_q.lower().startswith("n"):
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        bname = f"/var/tmp/keytab_backups/{os.path.basename(sel)}.{ts}.bak"
        MOCK_BACKUPS[bname] = {"orig": sel, "entries": [dict(e) for e in MOCK_KEYTABS[sel]], "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
        print(f"{C_GREEN}[SUCCESS]{C_RESET} Backup saved to: {bname}")
    
    confirm = input(f"\nAre you sure you want to PERMANENTLY DELETE '{sel}'? [type YES or y]: ").strip()
    if confirm in ["YES", "yes", "y", "Y"]:
        del MOCK_KEYTABS[sel]
        print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Keytab {sel} deleted successfully.")
    else:
        print(f"\n{C_YELLOW}[INFO] Deletion cancelled.{C_RESET}")
    press_enter()

def option_restore_keytab():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[OPTION 7] Restore Keytab from /var/tmp Backup{C_RESET}")
    print("================================================================================\n")
    if not MOCK_BACKUPS:
        print(f"{C_RED}[ERROR]{C_RESET} No backups available. Please create a backup first using Option 3.")
        press_enter()
        return
    
    bpaths = list(MOCK_BACKUPS.keys())
    print(f"{C_BOLD}Available Backups in /var/tmp:{C_RESET}\n")
    for i, bp in enumerate(bpaths, 1):
        print(f"  {C_GREEN}[{i:2d}]{C_RESET} {bp:<55} {C_DIM}(Date: {MOCK_BACKUPS[bp]['time']}){C_RESET}")
    print(f"\n  {C_RED}[ 0]{C_RESET} Cancel\n")
    
    choice = input(f"Select backup to restore [1-{len(bpaths)}, 0]: ").strip()
    if choice == "0" or not choice.isdigit() or int(choice) < 1 or int(choice) > len(bpaths):
        return
    
    sel_backup = bpaths[int(choice) - 1]
    binfo = MOCK_BACKUPS[sel_backup]
    dest = binfo["orig"]
    
    print(f"\nSelected Backup: {C_YELLOW}{sel_backup}{C_RESET}")
    render_klist(sel_backup, binfo["entries"])
    print(f"\nSuggested Destination: {C_CYAN}{dest}{C_RESET}")
    custom_dest = input(f"Enter restore path [Default: {dest}]: ").strip() or dest
    
    MOCK_KEYTABS[custom_dest] = [dict(e) for e in binfo["entries"]]
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Keytab restored to: {C_YELLOW}{custom_dest}{C_RESET}")
    render_klist(custom_dest, MOCK_KEYTABS[custom_dest])
    press_enter()

def option_merge_keytabs():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[MIGRATION] Merge New AES Keytab into Existing Keytab{C_RESET}")
    print("================================================================================\n")
    print("Select Existing Target Keytab:")
    exist_kt = select_keytab_dialog()
    if not exist_kt:
        return
    
    print("\nSelect Incoming New AES Keytab:")
    new_kt = select_keytab_dialog()
    if not new_kt:
        return
    
    if exist_kt == new_kt:
        print(f"\n{C_RED}[ERROR] Target and source cannot be the same file.{C_RESET}")
        press_enter()
        return

    # In-place backup
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    kdir = os.path.dirname(exist_kt)
    kname = os.path.basename(exist_kt)
    bname = f"{kdir}/backup/{kname}.{ts}.bak"
    MOCK_INPLACE_BACKUPS[bname] = {"orig": exist_kt, "entries": [dict(e) for e in MOCK_KEYTABS[exist_kt]], "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} In-place safety backup created at: {C_YELLOW}{bname}{C_RESET}")
    
    # Merge entries
    merged_entries = [dict(e) for e in MOCK_KEYTABS[exist_kt]]
    for e in MOCK_KEYTABS[new_kt]:
        new_entry = dict(e)
        new_entry["slot"] = len(merged_entries) + 1
        merged_entries.append(new_entry)
    
    MOCK_KEYTABS[exist_kt] = merged_entries
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} AES Keytab merged into: {C_YELLOW}{exist_kt}{C_RESET}")
    render_klist(exist_kt, MOCK_KEYTABS[exist_kt])
    press_enter()

def option_system_snapshots():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[MIGRATION] Pre-Migration System & Mount State Snapshots{C_RESET}")
    print("================================================================================\n")
    sel = select_keytab_dialog()
    if not sel:
        return
    
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    sdir = f"{os.path.dirname(sel)}/backup/system_snapshots_{ts}"
    MOCK_SNAPSHOTS[sdir] = {
        "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "target": sel,
        "krb5_conf": "[logging]\n default = FILE:/var/log/krb5libs.log\n[libdefaults]\n default_realm = EXAMPLE.CORP",
        "fstab": "nfs-server01.example.corp:/exports/finance /mnt/nfs_finance nfs sec=krb5 0 0",
        "mounts": dict(MOCK_NFS_MOUNTS)
    }
    
    print(f"Captured Pre-Migration Snapshots in: {C_YELLOW}{sdir}{C_RESET}\n")
    print(f"  {C_GREEN}✓{C_RESET} Backed up: /etc/krb5.conf")
    print(f"  {C_GREEN}✓{C_RESET} Backed up: /etc/fstab")
    print(f"  {C_GREEN}✓{C_RESET} Captured: 'df -h' baseline snapshot")
    print(f"  {C_GREEN}✓{C_RESET} Captured: 'mount | egrep \"nfs|cifs\"' ({len(MOCK_NFS_MOUNTS)} active shares)")
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} System snapshots recorded successfully.")
    press_enter()

def option_nfs_transition():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[MIGRATION] NFS Security Transition (sec=sys <-> sec=krb5){C_RESET}")
    print("================================================================================\n")
    print("Select Target Security Mode:")
    print(f"  {C_GREEN}[1]{C_RESET} Remount with 'sec=sys'  (Pre-Merge: prevent deadlocks)")
    print(f"  {C_GREEN}[2]{C_RESET} Remount with 'sec=krb5' (Post-Merge: restore Kerberos security)")
    print(f"  {C_RED}[0]{C_RESET} Cancel\n")
    c = input("Enter choice [1, 2, 0]: ").strip()
    
    if c == "1":
        for mp in MOCK_NFS_MOUNTS:
            MOCK_NFS_MOUNTS[mp]["opts"] = MOCK_NFS_MOUNTS[mp]["opts"].replace("sec=krb5", "sec=sys")
        print(f"\n{C_GREEN}[SUCCESS]{C_RESET} All active NFS mounts transitioned to 'sec=sys'.")
    elif c == "2":
        for mp in MOCK_NFS_MOUNTS:
            MOCK_NFS_MOUNTS[mp]["opts"] = MOCK_NFS_MOUNTS[mp]["opts"].replace("sec=sys", "sec=krb5")
        print(f"\n{C_GREEN}[SUCCESS]{C_RESET} All active NFS mounts transitioned to 'sec=krb5'.")
    press_enter()

def option_filesystem_sanity():
    print_banner()
    print(f"{C_BOLD}{C_CYAN}[MIGRATION] Filesystem Sanity & Comparison Report{C_RESET}")
    print("================================================================================\n")
    print(f"{C_BOLD}[1/3] Mount Table Comparison:{C_RESET}")
    print(f"  Total Active Network Mounts: {C_GREEN}{len(MOCK_NFS_MOUNTS)}{C_RESET}")
    for mp, info in MOCK_NFS_MOUNTS.items():
        print(f"  {C_CYAN}•{C_RESET} {mp:<22} {info['device']:<40} {C_YELLOW}{info['opts']}{C_RESET}")
    
    print(f"\n{C_BOLD}[2/3] Filesystem Capacity Summary (df -h):{C_RESET}")
    print(f"{C_BOLD}{'Filesystem':<42} {'Size':<6} {'Used':<6} {'Avail':<6} {'Use%':<6} {'Mounted on'}{C_RESET}")
    print("--------------------------------------------------------------------------------")
    for mp, info in MOCK_NFS_MOUNTS.items():
        print(f"{info['device']:<42} {info['size']:<6} {info['used']:<6} {info['avail']:<6} {info['pcent']:<6} {mp}")
    
    print(f"\n{C_BOLD}[3/3] Live Mount Accessibility Probes:{C_RESET}")
    for mp in MOCK_NFS_MOUNTS:
        print(f"  Testing access to {mp:<22} ... {C_GREEN}[OK - Responsive]{C_RESET}")
    
    print(f"\n{C_GREEN}[SUCCESS]{C_RESET} Filesystem sanity check passed with 100% responsiveness.")
    press_enter()

def main():
    while True:
        print_banner()
        print(f" {C_BOLD}Please select an option:{C_RESET}\n")
        print(f"  {C_GREEN}[1]{C_RESET} {C_BOLD}List Keytab Files{C_RESET} in the server")
        print(f"  {C_GREEN}[2]{C_RESET} {C_BOLD}Inspect Keytab Details{C_RESET} (klist -kte for all or specific keytabs)")
        print(f"  {C_GREEN}[3]{C_RESET} {C_BOLD}Take In-Place Backup & System Snapshots{C_RESET} (/etc/krb5.conf, /etc/fstab, df -h, mount)")
        print(f"  {C_GREEN}[4]{C_RESET} {C_BOLD}Merge New AES Keytab into Existing Keytab{C_RESET} (with 0600 permissions)")
        print(f"  {C_GREEN}[5]{C_RESET} {C_BOLD}NFS Security Transition{C_RESET} (Remount sec=sys <-> sec=krb5)")
        print(f"  {C_GREEN}[6]{C_RESET} {C_BOLD}Filesystem Sanity & Comparison Check{C_RESET} (Pre vs Post comparison)")
        print(f"  {C_GREEN}[7]{C_RESET} {C_BOLD}Add or Remove Principal{C_RESET} from a keytab file")
        print(f"  {C_GREEN}[8]{C_RESET} {C_BOLD}Create / Delete Keytab File{C_RESET}")
        print(f"  {C_GREEN}[9]{C_RESET} {C_BOLD}Restore Keytab from Backup{C_RESET}")
        print(f"  {C_RED}[0]{C_RESET} {C_BOLD}Exit{C_RESET}\n")
        print("================================================================================")
        opt = input("Enter option [0-9]: ").strip()
        
        if opt == "1":
            option_list_keytabs()
        elif opt == "2":
            option_klist_keytabs()
        elif opt == "3":
            option_system_snapshots()
        elif opt == "4":
            option_merge_keytabs()
        elif opt == "5":
            option_nfs_transition()
        elif opt == "6":
            option_filesystem_sanity()
        elif opt == "7":
            option_modify_keytab()
        elif opt == "8":
            sub_opt = input("\n[1] Create New Keytab [2] Delete Keytab [0] Cancel: ").strip()
            if sub_opt == "1":
                option_create_keytab()
            elif sub_opt == "2":
                option_delete_keytab()
        elif opt == "9":
            option_restore_keytab()
        elif opt in ["0", "exit", "q"]:
            print(f"\n{C_CYAN}[INFO]{C_RESET} Exiting Simulator. Goodbye!")
            sys.exit(0)

if __name__ == "__main__":
    main()
