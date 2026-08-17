#!/usr/bin/env bash
# ==============================================================================
# Script Name   : keytab_manager.sh
# Description   : Interactive Kerberos Keytab Management Utility for RHEL 7+
# Author        : Antigravity Assistant
# Compatibility : RHEL 7+, CentOS 7+, Rocky Linux 8/9, AlmaLinux 8/9, Fedora
# Requirements  : krb5-workstation (klist, ktutil), bash 4+, coreutils
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# Global Configuration & Paths
# ------------------------------------------------------------------------------
BACKUP_BASE_DIR="/var/tmp/keytab_backups"
MANIFEST_FILE="${BACKUP_BASE_DIR}/backup_manifest.log"
STANDARD_SEARCH_DIRS=(
    "/etc"
    "/etc/security/keytabs"
    "/var/kerberos"
    "/etc/krb5.keytab"
    "/etc/hadoop/conf"
    "/etc/hive/conf"
    "/etc/hbase/conf"
    "/opt"
)

# Standard Kerberos encryption types supported on RHEL 7/8/9
DEFAULT_ENCTYPES=(
    "aes256-cts-hmac-sha1-96"
    "aes128-cts-hmac-sha1-96"
    "arcfour-hmac"
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
    BG_BLUE='\033[44m'
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
    BG_BLUE=''
fi

# ------------------------------------------------------------------------------
# Helper Functions: Logging & UI
# ------------------------------------------------------------------------------
print_banner() {
    clear 2>/dev/null || true
    echo -e "${C_CYAN}${C_BOLD}"
    echo "================================================================================"
    echo "            KERBEROS KEYTAB MANAGEMENT UTILITY (RHEL 7 / 8 / 9)                "
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

press_enter_to_continue() {
    echo ""
    echo -e "${C_DIM}Press [ENTER] to return to the menu...${C_RESET}"
    read -r -s
}

# ------------------------------------------------------------------------------
# Dependency & Environment Checks
# ------------------------------------------------------------------------------
check_dependencies() {
    local missing_tools=()

    for tool in klist ktutil find chmod cp; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${C_RED}${C_BOLD}[FATAL] Missing required utilities: ${missing_tools[*]}${C_RESET}"
        echo -e "${C_YELLOW}Please install the Kerberos workstation package:${C_RESET}"
        echo -e "  - RHEL 7/8/9 / Rocky / AlmaLinux / CentOS: ${C_BOLD}sudo yum install -y krb5-workstation${C_RESET}"
        echo -e "  - Fedora: ${C_BOLD}sudo dnf install -y krb5-workstation${C_RESET}"
        echo ""
        exit 1
    fi

    # Create backup directory if not existing
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        mkdir -p "$BACKUP_BASE_DIR" 2>/dev/null || true
        chmod 0700 "$BACKUP_BASE_DIR" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# Core Utility: Discover Keytab Files
# ------------------------------------------------------------------------------
# Populates global array DISCOVERED_KEYTABS with unique readable keytab paths
DISCOVERED_KEYTABS=()

scan_keytabs() {
    local search_mode="${1:-standard}"
    DISCOVERED_KEYTABS=()
    local temp_list
    temp_list=$(mktemp 2>/dev/null || echo "/tmp/kt_scan.$$")

    if [[ "$search_mode" == "full" ]]; then
        msg_info "Performing full filesystem search for *.keytab files (excluding virtual fs)..."
        find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \
            -type f \( -name "*.keytab" -o -name "*keytab*" -o -name "krb5.keytab" \) -print 2>/dev/null >> "$temp_list"
    else
        for dir in "${STANDARD_SEARCH_DIRS[@]}"; do
            if [[ -f "$dir" ]]; then
                echo "$dir" >> "$temp_list"
            elif [[ -d "$dir" ]]; then
                find "$dir" -maxdepth 3 -type f \( -name "*.keytab" -o -name "*keytab*" -o -name "krb5.keytab" \) 2>/dev/null >> "$temp_list"
            fi
        done
    fi

    # Ensure /etc/krb5.keytab is added if it exists
    if [[ -f "/etc/krb5.keytab" ]]; then
        echo "/etc/krb5.keytab" >> "$temp_list"
    fi

    # Deduplicate and verify
    if [[ -f "$temp_list" ]]; then
        while IFS= read -r file_path; do
            [[ -z "$file_path" ]] && continue
            if [[ -f "$file_path" ]]; then
                # Verify if it's already in the list
                local already_exists=0
                for existing in "${DISCOVERED_KEYTABS[@]}"; do
                    if [[ "$existing" == "$file_path" ]]; then
                        already_exists=1
                        break
                    fi
                done
                if [[ $already_exists -eq 0 ]]; then
                    DISCOVERED_KEYTABS+=("$file_path")
                fi
            fi
        done < <(sort -u "$temp_list" 2>/dev/null)
        rm -f "$temp_list" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# Helper: Select Keytab from list or enter custom path
# ------------------------------------------------------------------------------
select_keytab_dialog() {
    local prompt_title="${1:-Select a Keytab File}"
    scan_keytabs "standard"

    echo -e "${C_BOLD}${C_CYAN}=== $prompt_title ===${C_RESET}"
    echo ""

    if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
        msg_warn "No keytab files automatically found in standard locations."
    else
        for i in "${!DISCOVERED_KEYTABS[@]}"; do
            local idx=$((i + 1))
            local kpath="${DISCOVERED_KEYTABS[$i]}"
            local perms owner group size
            perms=$(stat -c "%a" "$kpath" 2>/dev/null || stat -f "%Lp" "$kpath" 2>/dev/null || echo "???")
            owner=$(stat -c "%U" "$kpath" 2>/dev/null || stat -f "%Su" "$kpath" 2>/dev/null || echo "???")
            group=$(stat -c "%G" "$kpath" 2>/dev/null || stat -f "%Sg" "$kpath" 2>/dev/null || echo "???")
            size=$(stat -c "%s" "$kpath" 2>/dev/null || stat -f "%z" "$kpath" 2>/dev/null || echo "???")
            
            printf "  ${C_GREEN}[%2d]${C_RESET} %-42s ${C_DIM}(%s bytes, %s:%s, perms: %s)${C_RESET}\n" \
                "$idx" "$kpath" "$size" "$owner" "$group" "$perms"
        done
    fi

    echo ""
    echo -e "  ${C_YELLOW}[ C]${C_RESET} Enter custom file path manually"
    echo -e "  ${C_YELLOW}[ F]${C_RESET} Perform Deep Full-System Scan (/)"
    echo -e "  ${C_RED}[ 0]${C_RESET} Cancel / Go Back"
    echo ""

    while true; do
        read -r -p "Select an option [1-${#DISCOVERED_KEYTABS[@]}, C, F, 0]: " user_choice
        case "$user_choice" in
            0)
                SELECTED_KEYTAB=""
                return 1
                ;;
            [cC])
                echo ""
                read -r -p "Enter full path to keytab file: " custom_path
                custom_path=$(echo "$custom_path" | xargs) # trim whitespace
                if [[ -f "$custom_path" ]]; then
                    SELECTED_KEYTAB="$custom_path"
                    return 0
                else
                    msg_error "File does not exist: $custom_path"
                fi
                ;;
            [fF])
                scan_keytabs "full"
                select_keytab_dialog "$prompt_title"
                return $?
                ;;
            *)
                if [[ "$user_choice" =~ ^[0-9]+$ ]] && (( user_choice >= 1 && user_choice <= ${#DISCOVERED_KEYTABS[@]} )); then
                    SELECTED_KEYTAB="${DISCOVERED_KEYTABS[$((user_choice - 1))]}"
                    return 0
                else
                    msg_error "Invalid selection. Please enter a valid number or option."
                fi
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# OPTION 1: List Keytab Files in Server
# ------------------------------------------------------------------------------
option_list_keytabs() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 1] Discovered Keytab Files on this Server${C_RESET}"
    echo "================================================================================"
    echo ""

    scan_keytabs "standard"

    if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
        msg_warn "No keytabs found in standard search locations."
        echo ""
        read -r -p "Would you like to run a deep scan across the entire filesystem? (y/N): " run_full
        if [[ "$run_full" =~ ^[yY] ]]; then
            scan_keytabs "full"
        fi
    fi

    if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
        msg_error "No keytab files were found on this system."
    else
        echo -e "${C_BOLD}Found ${#DISCOVERED_KEYTABS[@]} keytab file(s):${C_RESET}"
        echo ""
        printf "${C_BOLD}%-4s %-45s %-12s %-15s %-8s %-10s${C_RESET}\n" "NUM" "KEYTAB PATH" "SIZE (BYTES)" "OWNER:GROUP" "PERMS" "ACCESSIBLE"
        echo "--------------------------------------------------------------------------------"

        for i in "${!DISCOVERED_KEYTABS[@]}"; do
            local idx=$((i + 1))
            local kpath="${DISCOVERED_KEYTABS[$i]}"
            local perms owner group size accessible="YES"
            
            perms=$(stat -c "%a" "$kpath" 2>/dev/null || stat -f "%Lp" "$kpath" 2>/dev/null || echo "???")
            owner=$(stat -c "%U" "$kpath" 2>/dev/null || stat -f "%Su" "$kpath" 2>/dev/null || echo "???")
            group=$(stat -c "%G" "$kpath" 2>/dev/null || stat -f "%Sg" "$kpath" 2>/dev/null || echo "???")
            size=$(stat -c "%s" "$kpath" 2>/dev/null || stat -f "%z" "$kpath" 2>/dev/null || echo "???")
            
            if [[ ! -r "$kpath" ]]; then
                accessible="NO (No Read)"
            elif [[ ! -w "$kpath" ]]; then
                accessible="RO (Read Only)"
            fi

            printf "%-4s %-45s %-12s %-15s %-8s %-10s\n" \
                "[$idx]" "$kpath" "$size" "$owner:$group" "$perms" "$accessible"
        done
    fi

    echo ""
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# OPTION 2: List `klist -kte` for Keytab Files
# ------------------------------------------------------------------------------
option_klist_keytabs() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 2] Inspect Keytab Content (klist -kte)${C_RESET}"
    echo "================================================================================"
    echo ""
    echo "Select inspection scope:"
    echo -e "  ${C_GREEN}[1]${C_RESET} Inspect ALL discovered keytab files"
    echo -e "  ${C_GREEN}[2]${C_RESET} Select a SPECIFIC keytab file"
    echo -e "  ${C_RED}[0]${C_RESET} Back to Main Menu"
    echo ""
    read -r -p "Enter choice [1, 2, 0]: " inspect_choice
    inspect_choice=$(echo "$inspect_choice" | xargs)

    case "$inspect_choice" in
        1)
            scan_keytabs "standard"
            if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
                msg_warn "No keytabs found in standard paths. Attempting full scan..."
                scan_keytabs "full"
            fi

            if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
                msg_error "No keytab files found to inspect."
                press_enter_to_continue
                return
            fi

            echo ""
            for kpath in "${DISCOVERED_KEYTABS[@]}"; do
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                echo -e "${C_BOLD}${C_WHITE}Keytab File : ${C_YELLOW}$kpath${C_RESET}"
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                if [[ ! -r "$kpath" ]]; then
                    msg_error "Cannot read file (Permission Denied). Please run with appropriate permissions or sudo."
                else
                    klist -kte "$kpath" 2>&1
                fi
                echo ""
            done
            ;;
        2)
            echo ""
            if select_keytab_dialog "Select Keytab to Inspect"; then
                echo ""
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                echo -e "${C_BOLD}${C_WHITE}Keytab File : ${C_YELLOW}$SELECTED_KEYTAB${C_RESET}"
                echo -e "${C_BOLD}${C_BLUE}======================================================================${C_RESET}"
                if [[ ! -r "$SELECTED_KEYTAB" ]]; then
                    msg_error "Cannot read file (Permission Denied)."
                else
                    klist -kte "$SELECTED_KEYTAB" 2>&1
                fi
                echo ""
            fi
            ;;
        0|[cC]|[qQ]|"")
            return
            ;;
        *)
            msg_error "Invalid selection."
            ;;
    esac

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Core Helper: Create Backup
# ------------------------------------------------------------------------------
create_backup_file() {
    local source_file="$1"
    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local filename
    filename=$(basename "$source_file")
    
    mkdir -p "$BACKUP_BASE_DIR" 2>/dev/null || true
    chmod 0700 "$BACKUP_BASE_DIR" 2>/dev/null || true

    local backup_target="${BACKUP_BASE_DIR}/${filename}.${timestamp}.bak"

    if cp -p "$source_file" "$backup_target" 2>/dev/null; then
        chmod 0600 "$backup_target" 2>/dev/null || true
        local sha_val
        sha_val=$(sha256sum "$backup_target" 2>/dev/null | awk '{print $1}' || echo "N/A")
        
        # Record in manifest
        echo "${timestamp}|${source_file}|${backup_target}|${sha_val}" >> "$MANIFEST_FILE" 2>/dev/null || true
        echo "$backup_target"
        return 0
    else
        # Try direct /var/tmp if directory failed
        local fallback_target="/var/tmp/${filename}.${timestamp}.bak"
        if cp -p "$source_file" "$fallback_target" 2>/dev/null; then
            chmod 0600 "$fallback_target" 2>/dev/null || true
            local sha_val
            sha_val=$(sha256sum "$fallback_target" 2>/dev/null | awk '{print $1}' || echo "N/A")
            echo "${timestamp}|${source_file}|${fallback_target}|${sha_val}" >> "/var/tmp/keytab_manifest.log" 2>/dev/null || true
            echo "$fallback_target"
            return 0
        fi
        return 1
    fi
}

# ------------------------------------------------------------------------------
# OPTION 3: Take Backup of Keytab File under /var/tmp
# ------------------------------------------------------------------------------
option_backup_keytabs() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 3] Backup Keytab Files to /var/tmp${C_RESET}"
    echo "================================================================================"
    echo ""
    echo -e "Backup Destination Directory: ${C_YELLOW}${BACKUP_BASE_DIR}${C_RESET} (or /var/tmp)"
    echo ""
    echo "Choose backup scope:"
    echo -e "  ${C_GREEN}[1]${C_RESET} Backup a SINGLE Keytab File"
    echo -e "  ${C_GREEN}[2]${C_RESET} Backup ALL Discovered Keytab Files"
    echo -e "  ${C_RED}[0]${C_RESET} Back to Main Menu"
    echo ""
    read -r -p "Enter choice [1, 2, 0]: " backup_choice
    backup_choice=$(echo "$backup_choice" | xargs)

    case "$backup_choice" in
        1)
            echo ""
            if select_keytab_dialog "Select Keytab to Backup"; then
                echo ""
                msg_info "Creating backup of $SELECTED_KEYTAB..."
                local backup_out
                backup_out=$(create_backup_file "$SELECTED_KEYTAB")
                if [[ $? -eq 0 && -n "$backup_out" ]]; then
                    msg_success "Backup successfully created:"
                    echo -e "  ${C_BOLD}Backup Path:${C_RESET} ${C_GREEN}$backup_out${C_RESET}"
                    echo -e "  ${C_BOLD}Permissions:${C_RESET} $(stat -c "%a (%U:%G)" "$backup_out" 2>/dev/null || echo "0600")"
                    echo -e "  ${C_BOLD}SHA256     :${C_RESET} $(sha256sum "$backup_out" 2>/dev/null | awk '{print $1}')"
                else
                    msg_error "Failed to create backup. Please check write permissions to /var/tmp."
                fi
            fi
            ;;
        2)
            scan_keytabs "standard"
            if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
                scan_keytabs "full"
            fi

            if [[ ${#DISCOVERED_KEYTABS[@]} -eq 0 ]]; then
                msg_error "No keytab files found to backup."
            else
                echo ""
                msg_info "Backing up ${#DISCOVERED_KEYTABS[@]} keytab files to $BACKUP_BASE_DIR..."
                local success_count=0
                for kpath in "${DISCOVERED_KEYTABS[@]}"; do
                    local backup_out
                    backup_out=$(create_backup_file "$kpath")
                    if [[ $? -eq 0 && -n "$backup_out" ]]; then
                        echo -e "  ${C_GREEN}✓${C_RESET} Backed up: $kpath -> ${C_YELLOW}$backup_out${C_RESET}"
                        ((success_count++))
                    else
                        echo -e "  ${C_RED}✗${C_RESET} Failed to backup: $kpath"
                    fi
                done
                echo ""
                msg_success "Completed: $success_count of ${#DISCOVERED_KEYTABS[@]} files backed up."
            fi
            ;;
        0|[cC]|[qQ]|"")
            return
            ;;
        *)
            msg_error "Invalid selection."
            ;;
    esac

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# OPTION 4: Add or Remove Principal from Keytab
# ------------------------------------------------------------------------------
option_modify_keytab() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 4] Add / Remove Principal from Keytab${C_RESET}"
    echo "================================================================================"
    echo ""

    if ! select_keytab_dialog "Select Target Keytab to Modify"; then
        return
    fi

    local target_keytab="$SELECTED_KEYTAB"

    # Pre-check write permissions
    if [[ ! -w "$target_keytab" ]]; then
        msg_warn "You do not have write permission for: $target_keytab"
        msg_warn "Modifications may fail unless you are root or running with sudo."
        echo ""
        read -r -p "Do you still want to proceed? (y/N): " force_proceed
        if [[ ! "$force_proceed" =~ ^[yY] ]]; then
            return
        fi
    fi

    # Safety prompt: take backup first
    echo ""
    echo -e "${C_YELLOW}${C_BOLD}[SAFETY RECOMMENDATION]${C_RESET} It is strongly advised to take a backup before modifying keytab entries."
    read -r -p "Create an automatic backup now? [Y/n]: " do_backup
    if [[ ! "$do_backup" =~ ^[nN] ]]; then
        local backup_res
        backup_res=$(create_backup_file "$target_keytab")
        if [[ $? -eq 0 && -n "$backup_res" ]]; then
            msg_success "Safety backup saved to: $backup_res"
        else
            msg_warn "Could not create backup. Proceed with caution."
        fi
    fi

    while true; do
        echo ""
        echo -e "${C_BOLD}Active Keytab:${C_RESET} ${C_YELLOW}$target_keytab${C_RESET}"
        echo "--------------------------------------------------------------------------------"
        echo "Choose operation:"
        echo -e "  ${C_GREEN}[1]${C_RESET} Add a Principal (with password & encryption types)"
        echo -e "  ${C_RED}[2]${C_RESET} Remove a Principal / Entry (by slot or principal name)"
        echo -e "  ${C_CYAN}[3]${C_RESET} View Current Keytab Entries (klist -kte)"
        echo -e "  ${C_YELLOW}[0]${C_RESET} Return to Main Menu"
        echo ""
        read -r -p "Enter operation [1, 2, 3, 0]: " mod_choice
        mod_choice=$(echo "$mod_choice" | xargs)

        case "$mod_choice" in
            1)
                sub_add_principal "$target_keytab"
                ;;
            2)
                sub_remove_principal "$target_keytab"
                ;;
            3)
                echo ""
                echo -e "${C_BOLD}${C_BLUE}--- Current Entries in $target_keytab ---${C_RESET}"
                klist -kte "$target_keytab" 2>&1
                echo ""
                ;;
            0|[cC]|[qQ]|"")
                return
                ;;
            *)
                msg_error "Invalid selection."
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Sub-Action 4A: Add Principal Step-by-Step
# ------------------------------------------------------------------------------
sub_add_principal() {
    local target_keytab="$1"
    echo ""
    echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}                 STEP-BY-STEP PRINCIPAL ADDITION                      ${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
    echo ""

    # Step 1: Principal Name
    echo -e "${C_BOLD}Step 1: Enter Principal Name${C_RESET} ${C_DIM}(Press ENTER or enter '0' / 'c' to cancel)${C_RESET}"
    echo -e "${C_DIM}Examples: user@EXAMPLE.COM, host/node1.example.com@EXAMPLE.COM, HTTP/web.corp.local@CORP.LOCAL${C_RESET}"
    local principal=""
    read -r -p "Principal: " principal
    principal=$(echo "$principal" | xargs)
    if [[ -z "$principal" || "$principal" == "0" || "$principal" =~ ^[cCQq]$ || "$principal" == "cancel" ]]; then
        msg_warn "Addition cancelled (no principal entered)."
        return
    fi

    # Step 2: Key Version Number (KVNO)
    echo ""
    echo -e "${C_BOLD}Step 2: Enter Key Version Number (KVNO)${C_RESET} ${C_DIM}(or 'c' to cancel)${C_RESET}"
    echo -e "${C_DIM}Default is 1. If syncing with an existing KDC account, enter its matching kvno.${C_RESET}"
    local kvno=""
    read -r -p "KVNO [Default: 1]: " kvno
    kvno=$(echo "$kvno" | xargs)
    if [[ "$kvno" =~ ^[cCQq]$ || "$kvno" == "cancel" ]]; then
        msg_warn "Addition cancelled by user."
        return
    fi
    kvno="${kvno:-1}"
    if [[ ! "$kvno" =~ ^[0-9]+$ ]]; then
        msg_warn "Invalid KVNO format. Falling back to 1."
        kvno=1
    fi

    # Step 3: Encryption Types Selection
    echo ""
    echo -e "${C_BOLD}Step 3: Select Encryption Types${C_RESET}"
    echo "  [1] Recommended Standard Set (aes256-cts-hmac-sha1-96, aes128-cts-hmac-sha1-96, arcfour-hmac)"
    echo "  [2] AES-256 Only (aes256-cts-hmac-sha1-96)"
    echo "  [3] AES-128 Only (aes128-cts-hmac-sha1-96)"
    echo "  [4] Custom Encryption Type string"
    echo -e "  ${C_RED}[0] Cancel / Return${C_RESET}"
    echo ""
    local enc_choice
    read -r -p "Select Encryption Type option [1-4, 0 - Default: 1]: " enc_choice
    enc_choice="${enc_choice:-1}"

    local selected_enctypes=()
    case "$enc_choice" in
        0|[cC]|[qQ])
            msg_warn "Addition cancelled by user."
            return
            ;;
        1)
            selected_enctypes=("aes256-cts-hmac-sha1-96" "aes128-cts-hmac-sha1-96" "arcfour-hmac")
            ;;
        2)
            selected_enctypes=("aes256-cts-hmac-sha1-96")
            ;;
        3)
            selected_enctypes=("aes128-cts-hmac-sha1-96")
            ;;
        4)
            read -r -p "Enter custom encryption type (e.g. aes256-cts-hmac-sha1-96): " custom_enc
            if [[ "$custom_enc" == "0" || "$custom_enc" =~ ^[cCQq]$ || -z "$custom_enc" ]]; then
                msg_warn "Addition cancelled by user."
                return
            fi
            selected_enctypes=("$custom_enc")
            ;;
        *)
            selected_enctypes=("aes256-cts-hmac-sha1-96" "aes128-cts-hmac-sha1-96" "arcfour-hmac")
            ;;
    esac

    # Step 4: Password Input (Securely masked with verification)
    echo ""
    echo -e "${C_BOLD}Step 4: Enter Principal Password${C_RESET} ${C_DIM}(Press ENTER with empty password to cancel)${C_RESET}"
    local pass1="" pass2=""
    while true; do
        read -r -s -p "Enter Password for $principal: " pass1
        echo ""
        if [[ -z "$pass1" ]]; then
            msg_warn "Password empty. Addition cancelled."
            return
        fi

        read -r -s -p "Confirm Password: " pass2
        echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            msg_error "Passwords do not match. Please try again (or press ENTER with blank password to cancel)."
        else
            break
        fi
    done

    # Step 5: Summary & Confirmation
    echo ""
    echo -e "${C_BOLD}--- Summary of Changes ---${C_RESET}"
    echo -e "  Target Keytab : ${C_YELLOW}$target_keytab${C_RESET}"
    echo -e "  Principal     : ${C_GREEN}$principal${C_RESET}"
    echo -e "  KVNO          : ${C_WHITE}$kvno${C_RESET}"
    echo -e "  Enc Types     : ${C_WHITE}${selected_enctypes[*]}${C_RESET}"
    echo ""
    read -r -p "Proceed with writing these entries to keytab? [Y/n]: " confirm_add
    if [[ "$confirm_add" =~ ^[nN] ]]; then
        msg_warn "Operation cancelled by user."
        return
    fi

    # Step 6: Execute via ktutil
    msg_info "Executing ktutil batch update..."
    local temp_keytab
    temp_keytab=$(mktemp "/var/tmp/kt_temp.XXXXXX" 2>/dev/null || echo "/var/tmp/kt_temp_$$")
    rm -f "$temp_keytab"

    # Build ktutil commands
    local kt_commands=""
    if [[ -f "$target_keytab" && -s "$target_keytab" ]]; then
        kt_commands+="rkt $target_keytab\n"
    fi

    for enc in "${selected_enctypes[@]}"; do
        # Note: addent in ktutil syntax: addent -password -p <princ> -k <kvno> -e <enctype>
        kt_commands+="addent -password -p $principal -k $kvno -e $enc\n$pass1\n"
    done
    kt_commands+="wkt $temp_keytab\nquit\n"

    local kt_out
    kt_out=$(echo -e "$kt_commands" | ktutil 2>&1)
    local kt_status=$?

    if [[ $kt_status -eq 0 && -f "$temp_keytab" && -s "$temp_keytab" ]]; then
        # Preserve original permissions & ownership
        if [[ -f "$target_keytab" ]]; then
            chmod --reference="$target_keytab" "$temp_keytab" 2>/dev/null || chmod 0600 "$temp_keytab"
            chown --reference="$target_keytab" "$temp_keytab" 2>/dev/null || true
        else
            chmod 0600 "$temp_keytab"
        fi

        # Move to target keytab atomically
        if cp "$temp_keytab" "$target_keytab" && rm -f "$temp_keytab"; then
            msg_success "Principal successfully added to $target_keytab!"
            echo ""
            echo -e "${C_BOLD}--- Updated Keytab Content ---${C_RESET}"
            klist -kte "$target_keytab"
        else
            msg_error "Failed to overwrite target keytab with updated contents."
            rm -f "$temp_keytab"
        fi
    else
        msg_error "ktutil operation failed."
        echo "$kt_out"
        rm -f "$temp_keytab"
    fi
}

# ------------------------------------------------------------------------------
# Sub-Action 4B: Remove Principal Step-by-Step
# ------------------------------------------------------------------------------
sub_remove_principal() {
    local target_keytab="$1"
    echo ""
    echo -e "${C_BOLD}${C_RED}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_RED}                 STEP-BY-STEP PRINCIPAL REMOVAL                       ${C_RESET}"
    echo -e "${C_BOLD}${C_RED}======================================================================${C_RESET}"
    echo ""

    if [[ ! -s "$target_keytab" ]]; then
        msg_error "Keytab is empty or does not exist."
        return
    fi

    # Read current entries via ktutil/klist
    echo -e "${C_BOLD}Current Keytab Entries:${C_RESET}"
    klist -kte "$target_keytab"
    echo ""

    # Parse slot lines using ktutil `list` command to get exact slot numbers
    local kt_list_output
    kt_list_output=$(echo -e "rkt $target_keytab\nlist\nquit\n" | ktutil 2>/dev/null)
    
    echo "Choose removal mode:"
    echo -e "  ${C_YELLOW}[1]${C_RESET} Remove by Exact Slot / Index Number"
    echo -e "  ${C_YELLOW}[2]${C_RESET} Remove ALL entries matching a specific Principal Name"
    echo -e "  ${C_RED}[0]${C_RESET} Cancel / Go Back"
    echo ""
    read -r -p "Select removal mode [1, 2, 0]: " del_mode

    case "$del_mode" in
        1)
            # Remove by slot
            echo ""
            echo -e "${C_CYAN}Current ktutil internal slot mappings:${C_RESET}"
            echo "$kt_list_output" | grep -E '^[[:space:]]*[0-9]+' || klist -kte "$target_keytab"
            echo ""
            echo -e "${C_DIM}(Enter 0 or 'c' to cancel and go back)${C_RESET}"
            read -r -p "Enter Slot Number to delete: " slot_num
            slot_num=$(echo "$slot_num" | xargs)
            if [[ "$slot_num" == "0" || "$slot_num" =~ ^[cCQq]$ || "$slot_num" == "cancel" || -z "$slot_num" ]]; then
                msg_warn "Deletion cancelled."
                return
            fi

            if [[ ! "$slot_num" =~ ^[0-9]+$ ]]; then
                msg_error "Invalid slot number: $slot_num"
                return
            fi

            read -r -p "Are you sure you want to delete Slot #$slot_num? [y/N]: " confirm_del
            if [[ ! "$confirm_del" =~ ^[yY] ]]; then
                msg_warn "Deletion cancelled."
                return
            fi

            local temp_keytab
            temp_keytab=$(mktemp "/var/tmp/kt_temp.XXXXXX" 2>/dev/null || echo "/var/tmp/kt_temp_$$")
            rm -f "$temp_keytab"
            
            local kt_cmds="rkt $target_keytab\ndelent $slot_num\nwkt $temp_keytab\nquit\n"
            echo -e "$kt_cmds" | ktutil 2>&1 >/dev/null

            if [[ -f "$temp_keytab" ]]; then
                chmod --reference="$target_keytab" "$temp_keytab" 2>/dev/null || chmod 0600 "$temp_keytab"
                cp "$temp_keytab" "$target_keytab" && rm -f "$temp_keytab"
                msg_success "Slot #$slot_num removed successfully!"
                echo ""
                echo -e "${C_BOLD}--- Remaining Keytab Entries ---${C_RESET}"
                klist -kte "$target_keytab"
            else
                msg_error "Failed to remove slot from keytab."
                rm -f "$temp_keytab"
            fi
            ;;
        2)
            # Remove all slots for a given principal
            echo ""
            echo -e "${C_DIM}(Enter 0 or 'c' to cancel and go back)${C_RESET}"
            read -r -p "Enter full Principal name to remove (e.g. appuser@EXAMPLE.COM): " target_princ
            target_princ=$(echo "$target_princ" | xargs)
            if [[ "$target_princ" == "0" || "$target_princ" =~ ^[cCQq]$ || "$target_princ" == "cancel" || -z "$target_princ" ]]; then
                msg_warn "Deletion cancelled."
                return
            fi

            # Find matching slots in reverse order (so deletion doesn't shift remaining indices)
            local matching_slots=()
            while IFS= read -r line; do
                if echo "$line" | grep -q "$target_princ"; then
                    local s_num
                    s_num=$(echo "$line" | awk '{print $1}' | tr -dc '0-9')
                    if [[ -n "$s_num" ]]; then
                        matching_slots+=("$s_num")
                    fi
                fi
            done < <(echo "$kt_list_output" | grep -E '^[[:space:]]*[0-9]+')

            if [[ ${#matching_slots[@]} -eq 0 ]]; then
                msg_error "No entries found matching principal: $target_princ"
                return
            fi

            echo ""
            echo -e "${C_YELLOW}Found ${#matching_slots[@]} matching slot(s): ${matching_slots[*]}${C_RESET}"
            read -r -p "Are you sure you want to remove ALL entries for $target_princ? [y/N]: " confirm_del
            if [[ ! "$confirm_del" =~ ^[yY] ]]; then
                msg_warn "Deletion cancelled."
                return
            fi

            # Sort slots descending so deleting slot 5 doesn't re-index slot 2
            IFS=$'\n' sorted_slots=($(sort -nr <<<"${matching_slots[*]}"))
            unset IFS

            local temp_keytab
            temp_keytab=$(mktemp "/var/tmp/kt_temp.XXXXXX" 2>/dev/null || echo "/var/tmp/kt_temp_$$")
            rm -f "$temp_keytab"

            local kt_cmds="rkt $target_keytab\n"
            for slot in "${sorted_slots[@]}"; do
                kt_cmds+="delent $slot\n"
            done
            kt_cmds+="wkt $temp_keytab\nquit\n"

            echo -e "$kt_cmds" | ktutil 2>&1 >/dev/null

            if [[ -f "$temp_keytab" ]]; then
                chmod --reference="$target_keytab" "$temp_keytab" 2>/dev/null || chmod 0600 "$temp_keytab"
                cp "$temp_keytab" "$target_keytab" && rm -f "$temp_keytab"
                msg_success "Principal $target_princ removed successfully!"
                echo ""
                echo -e "${C_BOLD}--- Remaining Keytab Entries ---${C_RESET}"
                klist -kte "$target_keytab"
            else
                msg_error "Failed to remove principal entries."
                rm -f "$temp_keytab"
            fi
            ;;
        0|[cC]|[qQ]|"")
            msg_warn "Removal cancelled."
            return
            ;;
        *)
            msg_error "Invalid selection."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# OPTION 5: Create a New Keytab File
# ------------------------------------------------------------------------------
option_create_keytab() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 5] Create a New Keytab File${C_RESET}"
    echo "================================================================================"
    echo ""

    echo -e "${C_BOLD}Step 1: Enter New Keytab File Path${C_RESET} ${C_DIM}(Press ENTER or '0' to cancel)${C_RESET}"
    echo -e "${C_DIM}Examples: /etc/security/keytabs/myapp.keytab, /etc/krb5.keytab, /var/kerberos/service.keytab${C_RESET}"
    local new_keytab=""
    read -r -p "New Keytab Path: " new_keytab
    new_keytab=$(echo "$new_keytab" | xargs)

    if [[ -z "$new_keytab" || "$new_keytab" == "0" || "$new_keytab" =~ ^[cCQq]$ || "$new_keytab" == "cancel" ]]; then
        msg_warn "Keytab creation cancelled."
        press_enter_to_continue
        return
    fi

    # Check if file already exists
    if [[ -f "$new_keytab" ]]; then
        msg_warn "File already exists: $new_keytab"
        read -r -p "Do you want to overwrite this existing file? [y/N]: " confirm_ovw
        if [[ ! "$confirm_ovw" =~ ^[yY] ]]; then
            msg_warn "Creation aborted to avoid overwriting existing keytab."
            press_enter_to_continue
            return
        fi
        # Offer backup before overwriting
        read -r -p "Create a safety backup before overwriting? [Y/n]: " do_bak
        if [[ ! "$do_bak" =~ ^[nN] ]]; then
            create_backup_file "$new_keytab" >/dev/null 2>&1 || true
        fi
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$new_keytab")
    if [[ ! -d "$parent_dir" ]]; then
        msg_info "Creating directory: $parent_dir"
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
            msg_error "Failed to create directory $parent_dir. Run with sudo / check permissions."
            press_enter_to_continue
            return
        fi
    fi

    echo ""
    msg_info "Initializing empty keytab and adding initial principal..."
    
    # Step 2: Prompt for initial principal details
    echo ""
    echo -e "${C_BOLD}Step 2: Enter Principal Name${C_RESET} ${C_DIM}(Press ENTER or '0' to cancel)${C_RESET}"
    echo -e "${C_DIM}Examples: myapp/server.corp.local@CORP.LOCAL, appuser@CORP.LOCAL${C_RESET}"
    local principal=""
    read -r -p "Principal: " principal
    principal=$(echo "$principal" | xargs)
    if [[ -z "$principal" || "$principal" == "0" || "$principal" =~ ^[cCQq]$ || "$principal" == "cancel" ]]; then
        msg_warn "Creation cancelled (no principal entered)."
        press_enter_to_continue
        return
    fi

    # KVNO
    local kvno=""
    read -r -p "KVNO [Default: 1]: " kvno
    kvno=$(echo "$kvno" | xargs)
    if [[ "$kvno" =~ ^[cCQq]$ || "$kvno" == "cancel" ]]; then
        msg_warn "Creation cancelled."
        press_enter_to_continue
        return
    fi
    kvno="${kvno:-1}"
    [[ ! "$kvno" =~ ^[0-9]+$ ]] && kvno=1

    # Enctypes
    echo ""
    echo -e "${C_BOLD}Step 3: Select Encryption Types${C_RESET}"
    echo "  [1] Recommended Standard Set (aes256-cts-hmac-sha1-96, aes128-cts-hmac-sha1-96, arcfour-hmac)"
    echo "  [2] AES-256 Only (aes256-cts-hmac-sha1-96)"
    echo "  [3] AES-128 Only (aes128-cts-hmac-sha1-96)"
    echo "  [0] Cancel"
    local enc_choice
    read -r -p "Select Encryption Option [1-3, 0 - Default: 1]: " enc_choice
    enc_choice="${enc_choice:-1}"
    if [[ "$enc_choice" == "0" || "$enc_choice" =~ ^[cCQq]$ ]]; then
        msg_warn "Creation cancelled."
        press_enter_to_continue
        return
    fi

    local selected_enctypes=()
    case "$enc_choice" in
        2) selected_enctypes=("aes256-cts-hmac-sha1-96") ;;
        3) selected_enctypes=("aes128-cts-hmac-sha1-96") ;;
        *) selected_enctypes=("aes256-cts-hmac-sha1-96" "aes128-cts-hmac-sha1-96" "arcfour-hmac") ;;
    esac

    # Password
    echo ""
    echo -e "${C_BOLD}Step 4: Enter Principal Password${C_RESET}"
    local pass1="" pass2=""
    while true; do
        read -r -s -p "Enter Password for $principal: " pass1
        echo ""
        if [[ -z "$pass1" ]]; then
            msg_warn "Password empty. Creation cancelled."
            press_enter_to_continue
            return
        fi

        read -r -s -p "Confirm Password: " pass2
        echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            msg_error "Passwords do not match. Please try again."
        else
            break
        fi
    done

    # Generate keytab using ktutil
    local temp_keytab
    temp_keytab=$(mktemp "/var/tmp/kt_temp.XXXXXX" 2>/dev/null || echo "/var/tmp/kt_temp_$$")
    rm -f "$temp_keytab"

    local kt_commands=""
    for enc in "${selected_enctypes[@]}"; do
        kt_commands+="addent -password -p $principal -k $kvno -e $enc\n$pass1\n"
    done
    kt_commands+="wkt $temp_keytab\nquit\n"

    local kt_out
    kt_out=$(echo -e "$kt_commands" | ktutil 2>&1)
    local kt_status=$?

    if [[ $kt_status -eq 0 && -f "$temp_keytab" && -s "$temp_keytab" ]]; then
        chmod 0600 "$temp_keytab"
        if cp "$temp_keytab" "$new_keytab" && rm -f "$temp_keytab"; then
            chmod 0600 "$new_keytab"
            msg_success "New keytab created successfully at: $new_keytab"
            echo ""
            echo -e "${C_BOLD}--- Keytab Content (klist -kte) ---${C_RESET}"
            klist -kte "$new_keytab"
        else
            msg_error "Failed to write keytab to destination: $new_keytab"
            rm -f "$temp_keytab"
        fi
    else
        msg_error "ktutil failed to generate keytab."
        echo "$kt_out"
        rm -f "$temp_keytab"
    fi

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# OPTION 6: Delete / Remove an Existing Keytab File
# ------------------------------------------------------------------------------
option_delete_keytab() {
    print_banner
    echo -e "${C_BOLD}${C_RED}[OPTION 6] Delete / Remove an Existing Keytab File${C_RESET}"
    echo "================================================================================"
    echo ""

    if ! select_keytab_dialog "Select Keytab File to Delete"; then
        return
    fi

    local target_keytab="$SELECTED_KEYTAB"

    echo ""
    echo -e "${C_BOLD}Selected Keytab for Deletion:${C_RESET} ${C_YELLOW}$target_keytab${C_RESET}"
    echo ""
    echo -e "${C_BOLD}${C_BLUE}--- Current Keytab Entries ---${C_RESET}"
    klist -kte "$target_keytab" 2>&1
    echo ""

    # Safety: Prompt to take backup before deleting
    echo -e "${C_YELLOW}${C_BOLD}[SAFETY RECOMMENDATION]${C_RESET} It is strongly recommended to backup the file before deleting."
    read -r -p "Create a backup in /var/tmp before deleting? [Y/n]: " do_backup
    if [[ ! "$do_backup" =~ ^[nN] ]]; then
        local bres
        bres=$(create_backup_file "$target_keytab")
        if [[ $? -eq 0 && -n "$bres" ]]; then
            msg_success "Safety backup saved to: $bres"
        else
            msg_warn "Could not create backup. Proceeding carefully."
        fi
    fi

    # Explicit confirmation
    echo ""
    echo -e "${C_RED}${C_BOLD}[WARNING] This will permanently remove the keytab file from the server!${C_RESET}"
    read -r -p "Are you sure you want to PERMANENTLY DELETE '$target_keytab'? [type YES or y to confirm]: " confirm_delete

    if [[ "$confirm_delete" == "YES" || "$confirm_delete" == "yes" || "$confirm_delete" == "y" || "$confirm_delete" == "Y" ]]; then
        if rm -f "$target_keytab"; then
            msg_success "Keytab file successfully deleted: $target_keytab"
        else
            msg_error "Failed to delete keytab file. Please check write permissions / sudo."
        fi
    else
        msg_warn "Deletion aborted by user."
    fi

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# OPTION 7: Restore from Backup
# ------------------------------------------------------------------------------
option_restore_keytab() {
    print_banner
    echo -e "${C_BOLD}${C_CYAN}[OPTION 7] Restore Keytab from /var/tmp Backup${C_RESET}"
    echo "================================================================================"
    echo ""

    # Find backup files in /var/tmp and /var/tmp/keytab_backups
    local backup_files=()
    while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && backup_files+=("$f")
    done < <(find /var/tmp -maxdepth 2 -type f \( -name "*.bak" -o -name "*keytab*" \) ! -name "*.log" ! -name "kt_temp*" 2>/dev/null | sort -r)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        msg_error "No backup keytab files found under /var/tmp or $BACKUP_BASE_DIR."
        press_enter_to_continue
        return
    fi

    echo -e "${C_BOLD}Available Backups in /var/tmp:${C_RESET}"
    echo ""
    printf "${C_BOLD}%-4s %-50s %-12s %-20s${C_RESET}\n" "NUM" "BACKUP FILE" "SIZE" "MODIFIED DATE"
    echo "--------------------------------------------------------------------------------"

    for i in "${!backup_files[@]}"; do
        local idx=$((i + 1))
        local bfile="${backup_files[$i]}"
        local bsize bdate
        bsize=$(stat -c "%s bytes" "$bfile" 2>/dev/null || stat -f "%z bytes" "$bfile" 2>/dev/null || echo "???")
        bdate=$(stat -c "%y" "$bfile" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$bfile" 2>/dev/null || echo "???")
        printf "%-4s %-50s %-12s %-20s\n" "[$idx]" "$bfile" "$bsize" "$bdate"
    done

    echo ""
    echo -e "  ${C_RED}[ 0]${C_RESET} Cancel / Back to Main Menu"
    echo ""

    local sel_backup=""
    while true; do
        read -r -p "Select Backup to Restore [1-${#backup_files[@]}, 0]: " bchoice
        if [[ "$bchoice" == "0" ]]; then
            return
        elif [[ "$bchoice" =~ ^[0-9]+$ ]] && (( bchoice >= 1 && bchoice <= ${#backup_files[@]} )); then
            sel_backup="${backup_files[$((bchoice - 1))]}"
            break
        else
            msg_error "Invalid selection."
        fi
    done

    echo ""
    echo -e "${C_BOLD}Selected Backup:${C_RESET} ${C_YELLOW}$sel_backup${C_RESET}"
    
    # Inspect backup keytab content
    echo ""
    echo -e "${C_BOLD}${C_BLUE}--- Content of Selected Backup (klist -kte) ---${C_RESET}"
    klist -kte "$sel_backup" 2>&1
    echo ""

    # Determine suggested restore target path from manifest or filename
    local suggested_target=""
    if [[ -f "$MANIFEST_FILE" ]]; then
        suggested_target=$(grep "|${sel_backup}|" "$MANIFEST_FILE" 2>/dev/null | tail -n1 | awk -F'|' '{print $2}')
    fi

    if [[ -z "$suggested_target" ]]; then
        # Guess from base filename: e.g. /etc/krb5.keytab if named krb5.keytab.*.bak
        local base_fname
        base_fname=$(basename "$sel_backup" | sed -E 's/\.[0-9]{8}_[0-9]{6}\.bak$//' | sed 's/\.bak$//')
        if [[ "$base_fname" == "krb5.keytab" ]]; then
            suggested_target="/etc/krb5.keytab"
        else
            suggested_target="/etc/security/keytabs/$base_fname"
        fi
    fi

    echo -e "Suggested Restore Destination: ${C_CYAN}${suggested_target}${C_RESET}"
    read -r -p "Enter Target Destination Path [Default: $suggested_target]: " restore_dest
    restore_dest="${restore_dest:-$suggested_target}"
    restore_dest=$(echo "$restore_dest" | xargs)

    if [[ -z "$restore_dest" ]]; then
        msg_error "Destination path cannot be empty."
        press_enter_to_continue
        return
    fi

    # Confirm overwrite if target exists
    if [[ -f "$restore_dest" ]]; then
        msg_warn "Target file already exists: $restore_dest"
        read -r -p "Are you sure you want to OVERWRITE this file? [y/N]: " confirm_overwrite
        if [[ ! "$confirm_overwrite" =~ ^[yY] ]]; then
            msg_warn "Restore aborted by user."
            press_enter_to_continue
            return
        fi
    fi

    # Ensure target parent directory exists
    local target_dir
    target_dir=$(dirname "$restore_dest")
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" 2>/dev/null || true
    fi

    # Perform restoration
    msg_info "Restoring $sel_backup -> $restore_dest ..."
    if cp -p "$sel_backup" "$restore_dest" 2>/dev/null; then
        chmod 0600 "$restore_dest" 2>/dev/null || true
        msg_success "Keytab successfully restored to: $restore_dest"
        echo ""
        echo -e "${C_BOLD}--- Restored Keytab Verification (klist -kte) ---${C_RESET}"
        klist -kte "$restore_dest"
    else
        msg_error "Failed to copy backup to $restore_dest. Check write permissions / sudo."
    fi

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Main Menu & Controller Loop
# ------------------------------------------------------------------------------
main_menu() {
    check_dependencies

    while true; do
        print_banner
        echo -e " ${C_BOLD}Please select an option:${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} ${C_BOLD}List Keytab Files${C_RESET} in the server"
        echo -e "  ${C_GREEN}[2]${C_RESET} ${C_BOLD}Inspect Keytab Details${C_RESET} (klist -kte for all or specific keytabs)"
        echo -e "  ${C_GREEN}[3]${C_RESET} ${C_BOLD}Take Backup${C_RESET} of keytab file(s) under /var/tmp"
        echo -e "  ${C_GREEN}[4]${C_RESET} ${C_BOLD}Add or Remove Principal${C_RESET} from a keytab file"
        echo -e "  ${C_GREEN}[5]${C_RESET} ${C_BOLD}Create a New Keytab File${C_RESET} (with initial principal)"
        echo -e "  ${C_RED}[6]${C_RESET} ${C_BOLD}Delete / Remove a Keytab File${C_RESET} (with safety backup)"
        echo -e "  ${C_GREEN}[7]${C_RESET} ${C_BOLD}Restore Keytab from Backup${C_RESET} (/var/tmp)"
        echo -e "  ${C_RED}[8]${C_RESET} ${C_BOLD}Exit${C_RESET}"
        echo ""
        echo "================================================================================"
        read -r -p "Enter option [1-8]: " user_opt

        case "$user_opt" in
            1) option_list_keytabs ;;
            2) option_klist_keytabs ;;
            3) option_backup_keytabs ;;
            4) option_modify_keytab ;;
            5) option_create_keytab ;;
            6) option_delete_keytab ;;
            7) option_restore_keytab ;;
            8)
                echo ""
                msg_info "Exiting Keytab Management Utility. Goodbye!"
                exit 0
                ;;
            *)
                msg_error "Invalid option '$user_opt'. Please enter a number from 1 to 8."
                sleep 1.5
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------------------------
# Trap Interrupts for graceful termination
trap 'echo -e "\n${C_RED}Operation interrupted by user. Exiting...${C_RESET}"; exit 130' SIGINT SIGTERM

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu "$@"
fi
