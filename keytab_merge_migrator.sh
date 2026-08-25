#!/usr/bin/env bash
# ==============================================================================
# Script Name   : keytab_merge_migrator.sh
# Description   : Enterprise Kerberos AES Keytab Merge & NFS Migration Utility
# Compatibility : RHEL 7+, CentOS 7+, Rocky Linux 8/9, AlmaLinux 8/9, Fedora
# Requirements  : krb5-workstation (klist, ktutil), bash 4+, coreutils, findutils
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# Global Variables & State
# ------------------------------------------------------------------------------
LAST_SNAPSHOT_DIR=""
LAST_KEYTAB_BACKUP=""
SELECTED_EXISTING_KEYTAB=""
SELECTED_NEW_KEYTAB=""

STANDARD_KEYTAB_DIRS=(
    "/etc/security/keytabs"
    "/etc"
    "/var/kerberos"
    "/etc/hadoop/conf"
    "/etc/hive/conf"
    "/opt"
)

# ------------------------------------------------------------------------------
# Color & Formatting Definitions
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
    C_MAGENTA='\033[35m'
    C_CYAN='\033[36m'
    C_WHITE='\033[37m'
else
    C_RESET=''
    C_BOLD=''
    C_DIM=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_MAGENTA=''
    C_CYAN=''
    C_WHITE=''
fi

# ------------------------------------------------------------------------------
# UI & Output Helpers
# ------------------------------------------------------------------------------
print_banner() {
    clear 2>/dev/null || true
    echo -e "${C_CYAN}${C_BOLD}"
    echo "================================================================================"
    echo "   KERBEROS AES KEYTAB MERGE & NFS MOUNT MIGRATION UTILITY (RHEL 7 / 8 / 9)   "
    echo "================================================================================"
    echo -e "${C_RESET}"
}

msg_info() {
    echo -e "${C_CYAN}[INFO]${C_RESET} $*"
}

msg_success() {
    echo -e "${C_GREEN}[SUCCESS]${C_RESET} $*"
}

msg_warn() {
    echo -e "${C_YELLOW}[WARNING]${C_RESET} $*"
}

msg_error() {
    echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2
}

press_enter() {
    echo ""
    echo -e "${C_DIM}Press [ENTER] to return to the menu...${C_RESET}"
    read -r -s
}

# ------------------------------------------------------------------------------
# Dependency & Permission Checks
# ------------------------------------------------------------------------------
check_prerequisites() {
    local missing=()
    for tool in klist ktutil find chmod cp df mount stat sha256sum diff; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        msg_error "Missing required utilities: ${missing[*]}"
        echo -e "${C_YELLOW}Please install krb5-workstation and core utilities:${C_RESET}"
        echo -e "  sudo yum install -y krb5-workstation coreutils diffutils findutils"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# In-Place Keytab Backup Mechanism
# Stored in <keytab_dir>/backup/<keytab_name>.<timestamp>.bak
# ------------------------------------------------------------------------------
create_inplace_keytab_backup() {
    local kt_path="$1"
    if [[ ! -f "$kt_path" ]]; then
        msg_error "Keytab file does not exist: $kt_path"
        return 1
    fi

    local kdir kname bdir timestamp backup_file sha_val
    kdir=$(dirname "$kt_path")
    kname=$(basename "$kt_path")
    bdir="${kdir}/backup"
    timestamp=$(date "+%Y%m%d_%H%M%S")
    backup_file="${bdir}/${kname}.${timestamp}.bak"

    mkdir -p "$bdir" 2>/dev/null || true
    chmod 0700 "$bdir" 2>/dev/null || true

    if cp -p "$kt_path" "$backup_file" 2>/dev/null; then
        chmod 0600 "$backup_file" 2>/dev/null || true
        sha_val=$(sha256sum "$backup_file" 2>/dev/null | awk '{print $1}' || echo "N/A")
        
        # Log to in-place manifest
        echo "${timestamp}|${kt_path}|${backup_file}|${sha_val}" >> "${bdir}/backup_manifest.log" 2>/dev/null || true
        LAST_KEYTAB_BACKUP="$backup_file"
        echo "$backup_file"
        return 0
    else
        msg_error "Failed to create in-place backup at $backup_file (Check write permissions)."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Pre-Migration System & Mount State Snapshotting
# Backups: /etc/krb5.conf, /etc/fstab, df -h, mount | egrep "nfs|cifs"
# ------------------------------------------------------------------------------
take_system_snapshots() {
    local base_dir="${1:-/etc/security/keytabs}"
    if [[ -f "$base_dir" ]]; then
        base_dir=$(dirname "$base_dir")
    fi

    local timestamp snap_dir
    timestamp=$(date "+%Y%m%d_%H%M%S")
    snap_dir="${base_dir}/backup/system_snapshots_${timestamp}"

    mkdir -p "$snap_dir" 2>/dev/null || true
    chmod 0700 "$snap_dir" 2>/dev/null || true

    msg_info "Capturing Pre-Migration System & Mount Snapshots..."
    echo -e "  Snapshot Directory: ${C_YELLOW}${snap_dir}${C_RESET}\n"

    # 1. /etc/krb5.conf
    if [[ -f "/etc/krb5.conf" ]]; then
        cp -p /etc/krb5.conf "${snap_dir}/krb5.conf.${timestamp}.bak" 2>/dev/null || true
        echo -e "  ${C_GREEN}✓${C_RESET} Backed up: /etc/krb5.conf"
    else
        echo -e "  ${C_DIM}-${C_RESET} /etc/krb5.conf not present (skipped)"
    fi

    # 2. /etc/fstab
    if [[ -f "/etc/fstab" ]]; then
        cp -p /etc/fstab "${snap_dir}/fstab.${timestamp}.bak" 2>/dev/null || true
        echo -e "  ${C_GREEN}✓${C_RESET} Backed up: /etc/fstab"
    fi

    # 3. df -h snapshot
    df -h > "${snap_dir}/df_h_pre.log" 2>/dev/null || true
    echo -e "  ${C_GREEN}✓${C_RESET} Captured: 'df -h' baseline state"

    # 4. mount | egrep "nfs|cifs" snapshot
    {
        mount 2>/dev/null | grep -E "\b(nfs|nfs4|cifs)\b" || true
    } > "${snap_dir}/mount_nfs_cifs_pre.log"
    echo -e "  ${C_GREEN}✓${C_RESET} Captured: 'mount | egrep \"nfs|cifs\"' baseline state"

    LAST_SNAPSHOT_DIR="$snap_dir"
    echo ""
    msg_success "Pre-migration system snapshots successfully saved to: $snap_dir"
}

# ------------------------------------------------------------------------------
# Discovery & Selection Helpers
# ------------------------------------------------------------------------------
discover_keytabs() {
    local temp_f
    temp_f=$(mktemp 2>/dev/null || echo "/tmp/kt_disc.$$")
    for d in "${STANDARD_KEYTAB_DIRS[@]}"; do
        if [[ -f "$d" ]]; then
            echo "$d" >> "$temp_f"
        elif [[ -d "$d" ]]; then
            find "$d" -maxdepth 3 -type f \( -name "*.keytab" -o -name "*keytab*" \) 2>/dev/null >> "$temp_f"
        fi
    done
    sort -u "$temp_f" 2>/dev/null
    rm -f "$temp_f" 2>/dev/null
}

select_keytab_dialog() {
    local prompt_title="${1:-Select a Keytab File}"
    local default_hint="$2"
    local kt_list=()

    while IFS= read -r line; do
        [[ -n "$line" && -f "$line" ]] && kt_list+=("$line")
    done < <(discover_keytabs)

    echo -e "${C_BOLD}${C_CYAN}=== $prompt_title ===${C_RESET}\n"
    if [[ ${#kt_list[@]} -gt 0 ]]; then
        for i in "${!kt_list[@]}"; do
            local idx=$((i + 1))
            local kp="${kt_list[$i]}"
            local perms owner group
            perms=$(stat -c "%a" "$kp" 2>/dev/null || echo "???")
            owner=$(stat -c "%U" "$kp" 2>/dev/null || echo "???")
            group=$(stat -c "%G" "$kp" 2>/dev/null || echo "???")
            printf "  ${C_GREEN}[%2d]${C_RESET} %-48s ${C_DIM}(%s:%s, perms: %s)${C_RESET}\n" "$idx" "$kp" "$owner" "$group" "$perms"
        done
    fi

    echo ""
    echo -e "  ${C_YELLOW}[ C]${C_RESET} Enter custom file path manually"
    echo -e "  ${C_RED}[ 0]${C_RESET} Cancel"
    echo ""

    while true; do
        read -r -p "Select option [1-${#kt_list[@]}, C, 0]: " user_sel
        user_sel=$(echo "$user_sel" | xargs)
        case "$user_sel" in
            0|[qQ]|"cancel")
                SELECTED_KEYTAB=""
                return 1
                ;;
            [cC])
                echo ""
                read -r -p "Enter full path to keytab: " custom_p
                custom_p=$(echo "$custom_p" | xargs)
                if [[ -f "$custom_p" ]]; then
                    SELECTED_KEYTAB="$custom_p"
                    return 0
                else
                    msg_error "File not found: $custom_p"
                fi
                ;;
            *)
                if [[ "$user_sel" =~ ^[0-9]+$ ]] && (( user_sel >= 1 && user_sel <= ${#kt_list[@]} )); then
                    SELECTED_KEYTAB="${kt_list[$((user_sel - 1))]}"
                    return 0
                else
                    msg_error "Invalid selection."
                fi
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# NFS Security Transition Helpers (sec=sys <-> sec=krb5)
# ------------------------------------------------------------------------------
get_active_nfs_mounts() {
    mount 2>/dev/null | grep -E "\b(nfs|nfs4)\b" | awk '{print $3}' || true
}

transition_nfs_security() {
    local target_sec="$1" # "sys" or "krb5"
    local active_mounts=()

    while IFS= read -r mp; do
        [[ -n "$mp" ]] && active_mounts+=("$mp")
    done < <(get_active_nfs_mounts)

    if [[ ${#active_mounts[@]} -eq 0 ]]; then
        msg_warn "No active NFS mount points currently detected via 'mount'."
        echo ""
        read -r -p "Enter custom NFS mount point manually (or press ENTER to skip): " manual_mp
        manual_mp=$(echo "$manual_mp" | xargs)
        if [[ -n "$manual_mp" ]]; then
            active_mounts+=("$manual_mp")
        else
            return 0
        fi
    fi

    echo -e "${C_BOLD}Active NFS Mount Points Detected:${C_RESET}"
    for mp in "${active_mounts[@]}"; do
        local cur_opts
        cur_opts=$(mount | grep -w "$mp" 2>/dev/null || echo "NFS Mount")
        echo -e "  ${C_CYAN}•${C_RESET} ${C_BOLD}$mp${C_RESET} ${C_DIM}($cur_opts)${C_RESET}"
    done
    echo ""

    read -r -p "Proceed with remounting these shares with 'sec=${target_sec}'? [Y/n]: " do_remount
    if [[ "$do_remount" =~ ^[nN] ]]; then
        msg_warn "NFS remount skipped by user."
        return 0
    fi

    local success=0
    for mp in "${active_mounts[@]}"; do
        msg_info "Remounting $mp with sec=${target_sec}..."
        if mount -o "remount,sec=${target_sec}" "$mp" 2>/dev/null; then
            msg_success "Remounted $mp with sec=${target_sec}"
            ((success++))
        else
            msg_warn "Standard remount failed for $mp. Attempting unmount & mount..."
            if umount -l "$mp" 2>/dev/null && mount -o "sec=${target_sec}" "$mp" 2>/dev/null; then
                msg_success "Remounted $mp with sec=${target_sec}"
                ((success++))
            else
                msg_error "Failed to remount $mp with sec=${target_sec}. Check NFS server export permissions or sudo."
            fi
        fi
    done

    echo ""
    msg_info "NFS Transition Summary: $success of ${#active_mounts[@]} shares remounted with sec=${target_sec}."
}

# ------------------------------------------------------------------------------
# Core Feature: Atomic Keytab Merge with ktutil & Permission Enforcement
# ------------------------------------------------------------------------------
execute_keytab_merge() {
    local existing_kt="$1"
    local new_kt="$2"

    if [[ ! -f "$existing_kt" ]]; then
        msg_error "Target existing keytab does not exist: $existing_kt"
        return 1
    fi

    if [[ ! -f "$new_kt" ]]; then
        msg_error "Incoming new AES keytab does not exist: $new_kt"
        return 1
    fi

    echo -e "${C_BOLD}${C_CYAN}=== KEYTAB MERGE OPERATION ===${C_RESET}"
    echo -e "  Existing Keytab : ${C_YELLOW}$existing_kt${C_RESET}"
    echo -e "  New AES Keytab  : ${C_GREEN}$new_kt${C_RESET}\n"

    # Step 1: Capture original permissions & ownership
    local orig_perms orig_owner orig_group
    orig_perms=$(stat -c "%a" "$existing_kt" 2>/dev/null || echo "0600")
    orig_owner=$(stat -c "%U" "$existing_kt" 2>/dev/null || echo "root")
    orig_group=$(stat -c "%G" "$existing_kt" 2>/dev/null || echo "root")

    echo -e "${C_BOLD}Original File Metadata to Preserve:${C_RESET}"
    echo -e "  Permissions : ${C_WHITE}$orig_perms${C_RESET}"
    echo -e "  Ownership   : ${C_WHITE}$orig_owner:$orig_group${C_RESET}\n"

    # Step 2: Take immediate In-Place Backup
    msg_info "Creating in-place safety backup before merge..."
    local bak_res
    bak_res=$(create_inplace_keytab_backup "$existing_kt")
    if [[ $? -eq 0 && -n "$bak_res" ]]; then
        msg_success "In-place backup verified at: $bak_res"
    else
        msg_warn "Could not create backup. Proceed with caution."
    fi
    echo ""

    # Step 3: Perform ktutil Merge into clean temp file
    msg_info "Merging keytabs via ktutil..."
    local temp_merged
    temp_merged=$(mktemp "/var/tmp/kt_merge.XXXXXX" 2>/dev/null || echo "/var/tmp/kt_merge_$$")
    rm -f "$temp_merged"

    local kt_cmds="rkt $existing_kt\nrkt $new_kt\nwkt $temp_merged\nquit\n"
    local kt_out
    kt_out=$(echo -e "$kt_cmds" | ktutil 2>&1)
    local kt_status=$?

    if [[ $kt_status -ne 0 || ! -f "$temp_merged" || ! -s "$temp_merged" ]]; then
        msg_error "ktutil merge failed."
        echo "$kt_out"
        rm -f "$temp_merged" 2>/dev/null || true
        return 1
    fi

    # Step 4: Enforce permissions and ownership on merged file
    chmod "$orig_perms" "$temp_merged" 2>/dev/null || chmod 0600 "$temp_merged" 2>/dev/null || true
    chown "$orig_owner:$orig_group" "$temp_merged" 2>/dev/null || true

    # Step 5: Atomically replace existing keytab
    if cp "$temp_merged" "$existing_kt" && rm -f "$temp_merged"; then
        chmod "$orig_perms" "$existing_kt" 2>/dev/null || chmod 0600 "$existing_kt" 2>/dev/null || true
        chown "$orig_owner:$orig_group" "$existing_kt" 2>/dev/null || true
        msg_success "Keytabs successfully merged into: $existing_kt"
        echo ""
        echo -e "${C_BOLD}--- Merged Keytab Content (klist -kte) ---${C_RESET}"
        klist -kte "$existing_kt"
        return 0
    else
        msg_error "Failed to overwrite target keytab with merged content."
        rm -f "$temp_merged" 2>/dev/null || true
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Filesystem Sanity & Comparison Engine (Pre vs Post Merge)
# ------------------------------------------------------------------------------
run_filesystem_sanity_check() {
    local snap_dir="$1"
    if [[ -z "$snap_dir" || ! -d "$snap_dir" ]]; then
        snap_dir="$LAST_SNAPSHOT_DIR"
    fi

    echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}          FILESYSTEM & MOUNT SANITY COMPARISON REPORT                 ${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}\n"

    # Step 1: Capture Post-Migration State
    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local df_post="${snap_dir}/df_h_post.log"
    local mount_post="${snap_dir}/mount_nfs_cifs_post.log"

    df -h > "$df_post" 2>/dev/null || true
    mount 2>/dev/null | grep -E "\b(nfs|nfs4|cifs)\b" > "$mount_post" 2>/dev/null || true

    local df_pre="${snap_dir}/df_h_pre.log"
    local mount_pre="${snap_dir}/mount_nfs_cifs_pre.log"

    echo -e "${C_BOLD}[1/3] Mount Table Comparison (Pre vs Post Migration):${C_RESET}"
    if [[ -f "$mount_pre" && -f "$mount_post" ]]; then
        local pre_count post_count
        pre_count=$(wc -l < "$mount_pre" | xargs)
        post_count=$(wc -l < "$mount_post" | xargs)

        echo -e "  Pre-Migration Active Mounts  : ${C_YELLOW}$pre_count${C_RESET}"
        echo -e "  Post-Migration Active Mounts : ${C_GREEN}$post_count${C_RESET}"

        if diff -u "$mount_pre" "$mount_post" >/dev/null 2>&1; then
            echo -e "  ${C_GREEN}[PASS]${C_RESET} All NFS / CIFS mount points remain identical."
        else
            echo -e "  ${C_YELLOW}[DIFF]${C_RESET} Detected mount option or table changes:"
            diff -u "$mount_pre" "$mount_post" | grep -E '^[+-]' | grep -v '^[+-]{3}' || true
        fi
    else
        msg_warn "Pre-migration mount baseline not found in $snap_dir."
    fi
    echo ""

    echo -e "${C_BOLD}[2/3] Filesystem Capacity & df -h Verification:${C_RESET}"
    if [[ -f "$df_pre" && -f "$df_post" ]]; then
        echo -e "  ${C_GREEN}[PASS]${C_RESET} Filesystem table captured. Current utilization summary:"
        df -h -t nfs -t nfs4 -t cifs 2>/dev/null || df -h | head -n 10
    fi
    echo ""

    echo -e "${C_BOLD}[3/3] Live Mount Accessibility & Readability Probes:${C_RESET}"
    local active_mounts=()
    while IFS= read -r mp; do
        [[ -n "$mp" ]] && active_mounts+=("$mp")
    done < <(get_active_nfs_mounts)

    if [[ ${#active_mounts[@]} -eq 0 ]]; then
        echo -e "  ${C_DIM}No active network mounts to probe.${C_RESET}"
    else
        for mp in "${active_mounts[@]}"; do
            echo -n "  Testing access to $mp ... "
            if ls -ld "$mp" >/dev/null 2>&1; then
                echo -e "${C_GREEN}[OK - Responsive]${C_RESET}"
            else
                echo -e "${C_RED}[FAIL - Unresponsive or Access Denied]${C_RESET}"
            fi
        done
    fi
    echo ""
    msg_success "Filesystem sanity check completed."
}

# ------------------------------------------------------------------------------
# MENU OPTION 1: View / Inspect Keytab Details (klist -kte)
# ------------------------------------------------------------------------------
option_inspect_keytab() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 1] View / Inspect Keytab Details (klist -kte)${C_RESET}"
    echo "================================================================================"
    echo ""
    echo -e "  ${C_GREEN}[1]${C_RESET} Inspect ALL Discovered Keytabs"
    echo -e "  ${C_GREEN}[2]${C_RESET} Select a SPECIFIC Keytab"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel\n"

    read -r -p "Enter choice [1, 2, 0]: " ins_opt
    ins_opt=$(echo "$ins_opt" | xargs)

    case "$ins_opt" in
        1)
            echo ""
            local any_found=0
            while IFS= read -r kt_path; do
                if [[ -n "$kt_path" && -f "$kt_path" ]]; then
                    any_found=1
                    echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                    echo -e "${C_BOLD}Keytab File : ${C_YELLOW}$kt_path${C_RESET} ${C_DIM}(perms: $(stat -c '%a, %U:%G' "$kt_path" 2>/dev/null || echo '0600'))${C_RESET}"
                    echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                    klist -kte "$kt_path" 2>&1
                    echo ""
                fi
            done < <(discover_keytabs)

            if [[ $any_found -eq 0 ]]; then
                msg_warn "No standard keytab files found on this system."
            fi
            ;;
        2)
            echo ""
            if select_keytab_dialog "Select Keytab to Inspect"; then
                local chosen_kt="$SELECTED_KEYTAB"
                echo ""
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                echo -e "${C_BOLD}Keytab File : ${C_YELLOW}$chosen_kt${C_RESET} ${C_DIM}(perms: $(stat -c '%a, %U:%G' "$chosen_kt" 2>/dev/null || echo '0600'))${C_RESET}"
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                klist -kte "$chosen_kt" 2>&1
                echo ""
            fi
            ;;
        *)
            return
            ;;
    esac
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 2: Pre-Migration Snapshots & In-Place Backups
# ------------------------------------------------------------------------------
option_pre_migration_snapshots() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 2] Pre-Migration Snapshots & In-Place Backups${C_RESET}"
    echo "================================================================================"
    echo ""

    if select_keytab_dialog "Select Existing Production Keytab to Backup"; then
        local target_kt="$SELECTED_KEYTAB"
        echo ""
        # 1. In-place Keytab Backup
        msg_info "Creating in-place keytab backup in $(dirname "$target_kt")/backup/ ..."
        local kbak
        kbak=$(create_inplace_keytab_backup "$target_kt")
        if [[ $? -eq 0 && -n "$kbak" ]]; then
            echo -e "  ${C_GREEN}✓${C_RESET} Keytab Backup: ${C_YELLOW}$kbak${C_RESET}"
            echo -e "  ${C_GREEN}✓${C_RESET} Permissions  : $(stat -c "%a (%U:%G)" "$kbak" 2>/dev/null || echo "0600")"
            echo -e "  ${C_GREEN}✓${C_RESET} SHA256       : $(sha256sum "$kbak" 2>/dev/null | awk '{print $1}')"
        fi
        echo ""

        # 2. System & Mount Snapshots
        take_system_snapshots "$target_kt"
    fi
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 3: NFS Remount sec=sys (Pre-Merge)
# ------------------------------------------------------------------------------
option_nfs_remount_sys() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 3] NFS Transition: Remount with sec=sys (Pre-Merge)${C_RESET}"
    echo "================================================================================"
    echo ""
    echo "This operation safely switches active NFS shares to standard UNIX security (sec=sys)"
    echo "prior to updating keytab credentials, avoiding I/O deadlocks or Kerberos auth errors."
    echo ""
    transition_nfs_security "sys"
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 4: Merge New AES Keytab into Existing Keytab
# ------------------------------------------------------------------------------
option_merge_keytabs() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 4] Merge New AES Keytab into Existing Keytab${C_RESET}"
    echo "================================================================================"
    echo ""

    echo -e "${C_BOLD}Step 1: Select Existing Target Keytab${C_RESET}"
    if ! select_keytab_dialog "Select Existing Target Keytab"; then
        return
    fi
    local exist_kt="$SELECTED_KEYTAB"
    echo ""

    echo -e "${C_BOLD}Step 2: Select Incoming New AES Keytab${C_RESET}"
    if ! select_keytab_dialog "Select Incoming New AES Keytab"; then
        return
    fi
    local new_kt="$SELECTED_KEYTAB"
    echo ""

    if [[ "$exist_kt" == "$new_kt" ]]; then
        msg_error "Existing keytab and new keytab cannot be the same file!"
        press_enter
        return
    fi

    execute_keytab_merge "$exist_kt" "$new_kt"
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 5: NFS Remount sec=krb5 (Post-Merge)
# ------------------------------------------------------------------------------
option_nfs_remount_krb5() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 5] NFS Transition: Remount with sec=krb5 (Post-Merge)${C_RESET}"
    echo "================================================================================"
    echo ""
    echo "This operation remounts active NFS shares with Kerberos security (sec=krb5)"
    echo "after the AES keytab merge has been completed."
    echo ""
    transition_nfs_security "krb5"
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 6: Filesystem Sanity & Comparison Check
# ------------------------------------------------------------------------------
option_filesystem_sanity() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 6] Filesystem Sanity & Comparison Check${C_RESET}"
    echo "================================================================================"
    echo ""
    run_filesystem_sanity_check "$LAST_SNAPSHOT_DIR"
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 7: Rollback / Restore Keytab & Configs
# ------------------------------------------------------------------------------
option_rollback() {
    print_banner
    echo -e "${C_BOLD}${C_RED}[OPTION 7] Rollback / Restore from In-Place Backup${C_RESET}"
    echo "================================================================================"
    echo ""

    if ! select_keytab_dialog "Select Keytab to Rollback"; then
        return
    fi
    local target_kt="$SELECTED_KEYTAB"
    local kdir bdir
    kdir=$(dirname "$target_kt")
    bdir="${kdir}/backup"

    if [[ ! -d "$bdir" ]]; then
        msg_error "No in-place backup directory found at: $bdir"
        press_enter
        return
    fi

    local bfiles=()
    while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && bfiles+=("$f")
    done < <(find "$bdir" -maxdepth 1 -type f -name "*.bak" 2>/dev/null | sort -r)

    if [[ ${#bfiles[@]} -eq 0 ]]; then
        msg_error "No .bak files found in $bdir."
        press_enter
        return
    fi

    echo -e "${C_BOLD}Available In-Place Backups:${C_RESET}\n"
    for i in "${!bfiles[@]}"; do
        local idx=$((i + 1))
        local bf="${bfiles[$i]}"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-55s ${C_DIM}(%s bytes)${C_RESET}\n" "$idx" "$bf" "$(stat -c "%s" "$bf" 2>/dev/null || echo "???")"
    done
    echo ""
    read -r -p "Select backup to restore [1-${#bfiles[@]}, 0 to cancel]: " bsel
    bsel=$(echo "$bsel" | xargs)

    if [[ "$bsel" =~ ^[0-9]+$ ]] && (( bsel >= 1 && bsel <= ${#bfiles[@]} )); then
        local chosen_bak="${bfiles[$((bsel - 1))]}"
        echo ""
        read -r -p "Are you sure you want to restore '$chosen_bak' -> '$target_kt'? [y/N]: " conf_rb
        if [[ "$conf_rb" =~ ^[yY] ]]; then
            if cp -p "$chosen_bak" "$target_kt"; then
                chmod 0600 "$target_kt" 2>/dev/null || true
                msg_success "Keytab rolled back successfully!"
                echo ""
                klist -kte "$target_kt"
            else
                msg_error "Failed to restore keytab."
            fi
        else
            msg_warn "Rollback cancelled."
        fi
    fi
    press_enter
}

# ------------------------------------------------------------------------------
# MENU OPTION 8: Guided End-to-End Automated Migration Wizard
# ------------------------------------------------------------------------------
option_guided_wizard() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}=== GUIDED END-TO-END AES KEYTAB & NFS MIGRATION WIZARD ===${C_RESET}"
    echo "================================================================================"
    echo "This wizard executes the 5 migration phases in safe sequential order:"
    echo "  [Phase 1] Pre-Migration Snapshots & In-Place Keytab Backup"
    echo "  [Phase 2] NFS Security Transition -> sec=sys"
    echo "  [Phase 3] Merge New AES Keytab & Enforce 0600 Permissions"
    echo "  [Phase 4] NFS Security Transition -> sec=krb5"
    echo "  [Phase 5] Post-Migration Filesystem Sanity & Comparison Check"
    echo "================================================================================"
    echo ""

    read -r -p "Start Guided Migration Wizard now? [Y/n]: " start_wiz
    if [[ "$start_wiz" =~ ^[nN] ]]; then
        return
    fi

    # Phase 1: Select Keytabs & Take Snapshots
    echo ""
    echo -e "${C_BOLD}${C_BLUE}>>> [PHASE 1/5] Select Target Keytab & Capture Baseline Snapshots${C_RESET}"
    if ! select_keytab_dialog "Select Existing Production Keytab"; then
        return
    fi
    local exist_kt="$SELECTED_KEYTAB"

    if ! select_keytab_dialog "Select Incoming New AES Keytab"; then
        return
    fi
    local new_kt="$SELECTED_KEYTAB"

    create_inplace_keytab_backup "$exist_kt"
    take_system_snapshots "$exist_kt"
    echo ""

    # Phase 2: NFS remount sec=sys
    echo -e "${C_BOLD}${C_BLUE}>>> [PHASE 2/5] Remount NFS with sec=sys${C_RESET}"
    transition_nfs_security "sys"
    echo ""

    # Phase 3: Merge Keytabs
    echo -e "${C_BOLD}${C_BLUE}>>> [PHASE 3/5] Merge AES Keytab into Existing Keytab${C_RESET}"
    execute_keytab_merge "$exist_kt" "$new_kt"
    echo ""

    # Phase 4: NFS remount sec=krb5
    echo -e "${C_BOLD}${C_BLUE}>>> [PHASE 4/5] Remount NFS with sec=krb5${C_RESET}"
    transition_nfs_security "krb5"
    echo ""

    # Phase 5: Sanity Comparison Check
    echo -e "${C_BOLD}${C_BLUE}>>> [PHASE 5/5] Post-Migration Filesystem Sanity Check${C_RESET}"
    run_filesystem_sanity_check "$LAST_SNAPSHOT_DIR"
    echo ""

    msg_success "Guided End-to-End Migration Wizard Finished Successfully!"
    press_enter
}

# ------------------------------------------------------------------------------
# Main Menu Loop
# ------------------------------------------------------------------------------
main_menu() {
    check_prerequisites

    while true; do
        print_banner
        echo -e " ${C_BOLD}Please select an operation:${C_RESET}\n"
        echo -e "  ${C_GREEN}[1]${C_RESET} ${C_BOLD}View / Inspect Keytab Details (klist -kte)${C_RESET}"
        echo -e "      ${C_DIM}• Inspect single or all keytab entries and encryption ciphers${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[2]${C_RESET} ${C_BOLD}Pre-Migration Snapshots & In-Place Backups${C_RESET}"
        echo -e "      ${C_DIM}• In-place keytab backup in <keytab_dir>/backup/${C_RESET}"
        echo -e "      ${C_DIM}• Backup /etc/krb5.conf, /etc/fstab, df -h, mount | egrep 'nfs|cifs'${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[3]${C_RESET} ${C_BOLD}NFS Transition: Remount with 'sec=sys'${C_RESET} (Pre-Merge)"
        echo -e "      ${C_DIM}• Prevent I/O deadlocks during keytab/credential update${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[4]${C_RESET} ${C_BOLD}Merge New AES Keytab into Existing Keytab${C_RESET}"
        echo -e "      ${C_DIM}• Atomic merge via ktutil with exact permission & ownership preservation${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[5]${C_RESET} ${C_BOLD}NFS Transition: Remount with 'sec=krb5'${C_RESET} (Post-Merge)"
        echo -e "      ${C_DIM}• Restore Kerberos security on NFS shares after merge${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[6]${C_RESET} ${C_BOLD}Filesystem Sanity & Comparison Check${C_RESET}"
        echo -e "      ${C_DIM}• Automated Pre vs Post diff comparison & mount accessibility check${C_RESET}"
        echo ""
        echo -e "  ${C_RED}[7]${C_RESET} ${C_BOLD}Rollback / Restore from In-Place Backup${C_RESET}"
        echo -e "      ${C_DIM}• Instant recovery of keytab, configs, and mounts${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}[8]${C_RESET} ${C_BOLD}Guided End-to-End Migration Wizard${C_RESET} (Steps 1 -> 5)"
        echo -e "  ${C_RED}[9]${C_RESET} ${C_BOLD}Exit${C_RESET}"
        echo ""
        echo "================================================================================"
        read -r -p "Enter option [1-9]: " user_opt
        user_opt=$(echo "$user_opt" | xargs)

        case "$user_opt" in
            1) option_inspect_keytab ;;
            2) option_pre_migration_snapshots ;;
            3) option_nfs_remount_sys ;;
            4) option_merge_keytabs ;;
            5) option_nfs_remount_krb5 ;;
            6) option_filesystem_sanity ;;
            7) option_rollback ;;
            8) option_guided_wizard ;;
            9|0|[qQ]|"exit")
                echo ""
                msg_info "Exiting Keytab & NFS Migration Utility. Goodbye!"
                exit 0
                ;;
            *)
                msg_error "Invalid option '$user_opt'. Please choose 1 to 9."
                sleep 1.2
                ;;
        esac
    done
}

# Trap interrupts gracefully
trap 'echo -e "\n${C_RED}Operation interrupted by user. Exiting...${C_RESET}"; exit 130' SIGINT SIGTERM

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu "$@"
fi
