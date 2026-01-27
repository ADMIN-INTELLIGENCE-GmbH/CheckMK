#!/bin/bash
############################################################
#    _   ___  __  __ ___ _  _                              #
#   /_\ |   \|  \/  |_ _| \| |                             #
#  / _ \| |) | |\/| || || .` |                             #
# /_/ \_\___/|_|  |_|___|_|\_|                             #
#  ___ _  _ _____ ___ _    _    ___ ___ ___ _  _  ___ ___  #
# |_ _| \| |_   _| __| |  | |  |_ _/ __| __| \| |/ __| __| #
#  | || .` | | | | _|| |__| |__ | | (_ | _|| .` | (__| _|  #
# |___|_|\_| |_| |___|____|____|___\___|___|_|\_|\___|___| #
#   ___       _    _  _                                    #
#  / __|_ __ | |__| || |                                   #
# | (_ | '  \| '_ \ __ |                                   #
#  \___|_|_|_|_.__/_||_|                                   #
#                                                          #
############################################################
############################################################
# Universal script to install the Checkmk agent (RAW and Enterprise/Cloud/MSP) with
# - Agent registration (Enterprise/Cloud/MSP)
# - Agent updater (Enterprise/Cloud/MSP)
# - Plugin management & configuration
# - Local Check Management
# - Remove Checkmk / Cleanup
# - Additional tools and scripts
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2025-11-06
# Version: 2.1.0
# Web: www.admin-intelligence.de
############################################################
# Table of contents
# - 1. Global configuration variables
# --- 1.1 Color schemes for different message types
# --- 1.2 Logging
# - 1.3 Helper Scripts
# - 2. User Interface
# --- 2.1 Additional Menues
# ----- 2.1.1 PVE Menues
# ----- 2.1.2 Site selection
# ----- 2.1.3 Additional Menues
# - 3. Key and config checks
# - 4. Installation and update logic
# - 5. Plugin managent and configuration
# - 6. Local checks management
# --- 6.1 PVE backup configuration
# - 7. Registration and agent management for cloud sites
# - 8. Main functions and logic
############################################################

HEADER="\nADMIN INTELLIGENCE GmbH | v2.1.0 | Sascha Jelinek | 2025-11-06"

############################################################
# === 1. Global configuration variables ===
############################################################

# Declare associative arrays for cloud and raw sites configurations.
# Set this block if you want to save the parameter for future usage, but you need to download the script and put it on your own instance
# the field "register" if you want to register the agent with your instance
# the field "updateuserpass" is needed if you want to set up automatic updates via the agent bakery (only enterprise or higher)
# the field "agent_package" is needed if you did provide your own agent with some predefined settings for the bakery
# just uncomment a complete "SITE_CLOUD_LIST" block or "SITE_RAW_LIST" block and fill it with your own contents

declare -A SITE_CLOUD_LIST
# SITE_CLOUD_LIST["site_1_url"]="" #mandatory
# SITE_CLOUD_LIST["site_1_register"]=""
# SITE_CLOUD_LIST["site_1_name"]="" #mandatory
# SITE_CLOUD_LIST["site_1_text"]=""
# SITE_CLOUD_LIST["site_1_updateuserpass"]=""
# SITE_CLOUD_LIST["site_1_update_protocol"]=""
# SITE_CLOUD_LIST["site_1_agent_package"]=""
# SITE_CLOUD_LIST["site_1_agent_version"]="2.4.*" #mandatory

declare -A SITE_RAW_LIST
# SITE_RAW_LIST["site_1_url"]=""
# SITE_RAW_LIST["site_1_register"]=""
# SITE_RAW_LIST["site_1_name"]="" #mandatory
# SITE_RAW_LIST["site_1_text"]=""
# SITE_RAW_LIST["site_1_agent_package"]=""
# SITE_RAW_LIST["site_1_agent_version"]="2.4.*" #mandatory

# Other global parameters
PYTHON_DOCKER_PACKAGE="python3-docker"  # Package name required for Python Docker integration

# Command-line parameters parsing for optional key and host inputs (--key / -k, --host / -h)
KEY=""
HOSTNAME_PARAM=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -k=*|--key=*)       # Parameter --key=<value>
            KEY="${1#*=}"
            shift
            ;;
        -k|--key)           # Parameter --key <value>
            KEY="$2"
            shift 2
            ;;
        -h=*|--host=*)      # Parameter --host=<value>
            HOSTNAME_PARAM="${1#*=}"
            shift
            ;;
        -h|--host)          # Parameter --host <value>
            HOSTNAME_PARAM="$2"
            shift 2
            ;;
        *)                  # Ignore unknown parameters
            shift
            ;;
    esac
done

# Expected SHA256 hash value for validating the provided key
EXPECTED_HASH="e33c8010c6c261928c0bc0c424c19dae7d259e5384593e3879dff4499ebdc8e6"
# URL to download the configuration file, including the token parameter for authentication
CONFIG_URL="https://monitoring-config.admin-intelligence.de/config_MliTLmcYAeXKbMuwVA3AcmhL8ItsJ0aflmr8rkvJnXcKHxvucgIe8kwfAVoAVoV6.txt?token=$KEY"

# Descriptions used for menu entries, keyed by menu item identifier
declare -A MENU_DESCRIPTIONS=(
    [cloud]="| Cloud       | Installation with registration |"
    [raw]="| RAW         | Standard installation          |"
    [plugins]="|             | Manage plugins                 |"
    [plugin_config]="|             | Plugin configuration           |"
    [local_checks]="|             | Manage local checks            |"
    [local_checks_config]="|             | Configure local checks         |"
    [cleanup]="|             | Remove Checkmk / cleanup       |"
    [tools]="|             | Additional tools               |"
)

# Default menu keys without cloud
MENU_KEYS_DEFAULT=(raw plugins plugin_config local_checks local_checks_config cleanup tools)

# Menu keys including cloud option
MENU_KEYS_CLOUD=(cloud "${MENU_KEYS_DEFAULT[@]}")

############################################################
# === 1.1 Color schemes for different message types ===
############################################################
NEWT_COLORS_STANDARD='
    root=black,blue
    window=black,brightblue
    border=black,brightblue
    shadow=black,black
    title=black,brightblue
    textbox=black,brightblue
    button=brightblue,black
    actbutton=black,brightblue
'

NEWT_COLORS_SUCCESS='
    root=black,blue
    window=black,green
    border=black,green
    shadow=black,black
    title=black,green
    textbox=black,green
    button=green,black
    actbutton=black,green
'

NEWT_COLORS_ERROR='
    root=black,blue
    window=black,red
    border=black,red
    shadow=black,black
    title=black,red
    textbox=black,red
    button=red,black
    actbutton=black,red
'

NEWT_COLORS_WARNING='
    root=white,blue
    window=black,brown
    border=black,brown
    shadow=black,black
    title=black,brown
    textbox=black,brown
    button=brown,black
    actbutton=black,brown
'

############################################################
# === 1.2 Logging ===
############################################################

# Log file path for storing script execution logs
LOGFILE="/var/log/checkmk-agent-install.log"

# General logging function
# - Accepts a message string as parameter
# - Prepends a timestamp to the message
# - Outputs to console and appends to the log file
log() {
    local msg="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $msg" | tee -a "$LOGFILE"
}


############################################################
# === 1.3 Helper Scripts ===
############################################################

# Function to check if the script is executed with root privileges
# - Exits with an error message if not running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_error_box "This script must be run as root!"
        exit 1
    fi
}

# Function to abort the script on an unrecoverable error
# - Displays an error message, clears the screen, and exits
abort_script() {
    show_error_box "Operation aborted. The script will exit."
    clear
    exit 1
}

# Function to terminate the script gracefully
# - Clears the screen and exits without error message
end_script() {
    clear
    exit 1
}

# Helper function to check if a package is installed
# - Works for Debian/Ubuntu (apt/dpkg), RPM-based distros, or checks if command exists
# - Returns 0 (success) if installed, 1 otherwise
is_installed() {
    # Debian/Ubuntu package check using dpkg-query
    if command -v dpkg &>/dev/null; then
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" && return 0
    fi

    # RPM package check
    if command -v rpm &>/dev/null; then
        rpm -q "$1" &>/dev/null && return 0
    fi

    # Fallback: check if executable command exists
    command -v "$1" &>/dev/null && return 0

    return 1
}

# Helper function to check if a process is running by exact name
is_process_running() {
    pgrep -x "$1" &>/dev/null
}

# Helper function to check if a file exists
file_exists() {
    [[ -f "$1" ]]
}

# Helper function to check if a directory exists
dir_exists() {
    [[ -d "$1" ]]
}

# Function to truncate a description string to a maximum length
# - Adds ellipsis (…) if string was truncated
truncate_desc() {
    local desc="$1"
    local max_len="$2"
    if ((${#desc} > max_len)); then
        echo "${desc:0:max_len}…"
    else
        echo "$desc"
    fi
}

# Function to remove duplicate entries from a list of arguments
# - Returns unique values preserving order
make_unique() {
    declare -A tmp
    local out=()
    for i in "$@"; do
        [[ -z "${tmp[$i]}" ]] && out+=("$i") && tmp[$i]=1
    done
    echo "${out[@]}"
}

############################################################
# === 2. User Interface ===
############################################################

# Helper function to show a success message box
# - Logs the message as SUCCESS
# - Uses custom color theme for success dialogs
show_success_box() {
    log "SUCCESS: $1"
    export NEWT_COLORS="$NEWT_COLORS_SUCCESS"
    whiptail --title "Success" --msgbox "$1" 10 60
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
}

# Helper function to show an error message box
# - Logs the message as ERROR
# - Uses custom color theme for error dialogs
show_error_box() {
    log "ERROR: $1"
    export NEWT_COLORS="$NEWT_COLORS_ERROR"
    whiptail --title "Error" --msgbox "$1" 8 60
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
}

# Helper function to show a warning message box (smaller size)
# - Logs as WARNING
show_warning_box() {
    log "WARNING: $1"
    export NEWT_COLORS="$NEWT_COLORS_WARNING"
    whiptail --title "Warning" --msgbox "$1" 8 60
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
}

# Helper function to show a warning message box (larger size)
# - Logs as WARNING
show_warning_box_large() {
    log "WARNING: $1"
    export NEWT_COLORS="$NEWT_COLORS_WARNING"
    whiptail --title "Warning" --msgbox "$1" 10 70
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
}

# Helper function to show an informational message box
# - Logs as INFO
show_info_box() {
    log "INFO: $1"
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
    whiptail --title "Information" --msgbox "$1" 8 60
}

# Function: Presents a menu for the user to choose a monitoring site
# - Builds the options list from configured cloud and raw sites
# - Shows an error and exits if no sites are found
# - If only one site is available, selects it by default
choose_site() {
    local options=()
    local keys=()
    local idx
    local text

    # Build menu entries for Cloud sites
    for key in "${!SITE_CLOUD_LIST[@]}"; do
        if [[ "$key" =~ ^site_([0-9]+)_url$ ]]; then
            idx="${BASH_REMATCH[1]}"
            text="${SITE_CLOUD_LIST["site_${idx}_text"]}"
            [[ -z "$text" ]] && text="Cloud Site $idx"
            options+=( "cloud_site_${idx}" "| $text (Cloud)" )
            keys+=( "cloud_site_${idx}" )
        fi
    done

    # Build menu entries for Raw sites
    for key in "${!SITE_RAW_LIST[@]}"; do
        if [[ "$key" =~ ^site_([0-9]+)_url$ ]]; then
            idx="${BASH_REMATCH[1]}"
            text="${SITE_RAW_LIST["site_${idx}_text"]}"
            [[ -z "$text" ]] && text="Raw Site $idx"
            options+=( "raw_site_${idx}" "| $text (Raw)" )
            keys+=( "raw_site_${idx}" )
        fi
    done

    # Exit with error if no sites found
    if (( ${#keys[@]} == 0 )); then
        show_error_box "No sites (Cloud or Raw) found."
        exit 1

    # If only one site available, return it immediately
    elif (( ${#keys[@]} == 1 )); then
        echo "${keys[0]}"
        return 0
    fi

    # Show site selection menu using whiptail
    local choice
    choice=$(whiptail --title "Site Selection" --menu "Please choose a site:" 15 60 5 "${options[@]}" 3>&1 1>&2 2>&3)

    # Return the selected site or error out if none chosen
    if [[ $? -eq 0 ]] && [[ -n "$choice" ]]; then
        echo "$choice"
        return 0
    else
        show_error_box "No site selected. Script will exit."
        exit 1
    fi
}

# Function: Prompt user to manually input site variables
# - Requests site URL, registration endpoint, name, description, and optional update user password
# - Validates mandatory fields site URL and site name
# - Shows success message on completion
input_site_variables() {
    local ic="$1"
    if [[ "$ic" -ne 1 ]]; then
        return
    fi
    SITE_URL=$(whiptail --inputbox "Enter the Site URL:" 10 60 "" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$SITE_URL" ]; then
        show_error_box "Site URL is required!"
        exit 1
    fi

    SITE_REGISTER=$(whiptail --inputbox "Enter the Site registration endpoint:" 10 60 "" 3>&1 1>&2 2>&3)
    SITE_NAME=$(whiptail --inputbox "Enter the Site name:" 10 60 "" 3>&1 1>&2 2>&3)
    SITE_TEXT=$(whiptail --inputbox "Enter the Site description:" 10 60 "" 3>&1 1>&2 2>&3)
    SITE_UPDATEUSERPASS=$(whiptail --passwordbox "Enter the update user password (optional):" 10 60 "" 3>&1 1>&2 2>&3)

    if [ -z "$SITE_NAME" ] || [ -z "$SITE_URL" ]; then
        show_error_box "Site name and URL are required."
        exit 1
    fi

    show_success_box "Manual site configuration completed."
}

# Function: Display start menu dialog with selectable installation modes
# - Dynamically builds menu from passed keys and global descriptions
# - Adjusts menu height based on number of options
# - Returns user's choice or exit code
show_start_box() {
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"

    local menu_keys=("$@")  # Use all parameters as array
    local height=$(( ${#menu_keys[@]} + 11 ))
    (( height < 20 )) && height=20

    local menu_lines=()
    for key in "${menu_keys[@]}"; do
        menu_lines+=("$key" "${MENU_DESCRIPTIONS[$key]}")
    done

    CHOICE=$(whiptail --title "Checkmk Agent Installation" --menu \
        "$HEADER\n-------- Please choose the desired installation mode --------" \
        "$height" 70 "${#menu_keys[@]}" \
        "${menu_lines[@]}" 3>&1 1>&2 2>&3)

    return $?
}

# Function: Show plugin configuration menu with available plugins for user selection
# - Checks for existence of known plugin files before showing options
# - Includes options for mysql, apache, nginx, file monitoring, and cancel
show_plugin_box() {
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"

    PLUGIN_PATH="/usr/lib/check_mk_agent/plugins/mk_mysql"
    if [[ -f "$PLUGIN_PATH" ]]; then
        MYSQL_OPTION="\"mysql\" \"| MySQL                 |\""
    else
        MYSQL_OPTION=""
    fi
    PLUGIN_PATH="/usr/lib/check_mk_agent/plugins/apache_status.py"
    if [[ -f "$PLUGIN_PATH" ]]; then
        APACHE_OPTION="\"apache\" \"| Apache /server-status  |\""
    else
        APACHE_OPTION=""
    fi
    PLUGIN_PATH="/usr/lib/check_mk_agent/plugins/nginx_status.py"
    if [[ -f "$PLUGIN_PATH" ]]; then
        NGINX_OPTION="\"nginx\" \"| NGINX /nginx-status    |\""
    else
        NGINX_OPTION=""
    fi

    # Dynamically build menu and capture user selection
    eval "PLUGINCHOICE=\$(whiptail --title \"Checkmk plugin configuration\" --menu \
    \"$HEADER\n\nPlease choose the desired plugin to be configured:\" 16 70 4 \
    $MYSQL_OPTION \
    $APACHE_OPTION \
    $NGINX_OPTION \
    \"file\" \"| File monitoring        |\" \
    \"cancel\" \"| ------- cancel ------- |\" \
    3>&1 1>&2 2>&3)"

    return $?
}

# Function: Show checklist menu for selecting multiple plugins to install or remove
# - Adjusts window size based on terminal size, ensuring min/max limits
# - Saves selected plugins to a temporary file, reads back into array
# - If cancelled or error, returns to main menu
show_plugin_selection_menu() {
    whiptail_width=$((width - 10))
    whiptail_height=$((height - 3))
    if ((whiptail_width < 60)); then whiptail_width=60; fi
    if ((whiptail_height < 20)); then whiptail_height=20; fi
    visible_entries=$((whiptail_height - 11))
    if ((visible_entries < 10)); then visible_entries=10; fi
    if ((visible_entries > 40)); then visible_entries=40; fi

    {
    whiptail --title "Select Checkmk Plugins" \
        --checklist "\nPlease select the plugins to be installed/removed:\n\n[Space = select, Tab = next]\nSelected = to be installed, not selected = will be removed / not installed" \
        "$whiptail_height" "$whiptail_width" "$visible_entries" \
        "${PLUGINS[@]}" \
        --separate-output \
        3>&1 1>&2 2>&3
    } > /tmp/selected_plugins.txt
    local retcode=$?
    mapfile -t SELECTED_PLUGINS < /tmp/selected_plugins.txt
    rm /tmp/selected_plugins.txt
    if [[ $retcode -ne 0 ]]; then
        main
        return
    fi
}

# Function: Show a summary of plugin installation/removal results
# - Categorizes plugins into installed, removed, and untouched
# - Presents a message box with summary lists
# - Returns to main menu afterwards
show_installation_summary() {
    # Plugins installed and still selected (untouched)
    untouched_plugins=()
    for p in "${installed_plugins_basenames[@]}"; do
        for sel in "${unique_selected_plugins[@]}"; do
            if [[ "$p" == "$sel" ]]; then
                untouched_plugins+=("$p")
                break
            fi
        done
    done

    # Convert arrays to comma-separated strings or "none" if empty
    installed_str=$([[ ${#plugins_to_install[@]} -gt 0 ]] && (
        IFS=", "
        echo "${plugins_to_install[*]}"
    ) || echo "none")
    removed_str=$([[ ${#plugins_to_remove[@]} -gt 0 ]] && (
        IFS=", "
        echo "${plugins_to_remove[*]}"
    ) || echo "none")
    untouched_str=$([[ ${#untouched_plugins[@]} -gt 0 ]] && (
        IFS=", "
        echo "${untouched_plugins[*]}"
    ) || echo "none")

    summary_message="Plugin installation summary:\n"
    summary_message+="Installed: $installed_str"
    summary_message+="\nRemoved: $removed_str"
    summary_message+="\nUntouched: $untouched_str"
    whiptail --title "Plugin installation finished" --msgbox "$summary_message" 15 70
    main
}

############################################################
# === 2.1 Additional Menues ===
############################################################

# Backupfile configuration dialog
# - Ask user if they want to use default file patterns or specify their own
# - Calls respective functions based on selection
backupfile_check() {
    log "[backupfile] Starting backup file configuration dialog."
    CHOICE=$(whiptail --title "Backupfile Configuration" --menu \
        "Would you like to use the default file patterns or specify your own?" 12 70 2 \
        "d" "Use default file patterns" \
        "f" "Specify your own file patterns" \
        3>&1 1>&2 2>&3)
    case "$CHOICE" in
    d)
        backupfile_default 1
        ;;
    f)
        backupfile_own
        ;;
    *)
        log "[backupfile] Invalid selection in backupfile_check."
        show_error_box "Invalid selection. Operation aborted." 8 60
        ;;
    esac
}


# Local checks installation menu
# - Detect if Proxmox VE (PVE) environment is present
# - Defines URLs of available local check scripts, adds PVE-specific check if applicable
# - Detects currently installed local checks in the agent directory
# - Builds checklist dialog with installed checks pre-selected
# - Installs or updates selected checks by downloading fresh copies
# - If PVE backup config was selected, installs cron jobs for it
# - Removes local checks that were previously installed but not selected now
# - Shows a summary and returns to main menu
install_local_checks_menu() {
    # Detect PVE presence by checking /etc/pve directory
    local is_pve=0
    if [[ -d /etc/pve ]]; then
        is_pve=1
    fi

    # URLs of local check scripts available for installation
    declare -A LOCAL_CHECKS=(
        ["98_local_checks_bakery"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/local_checks_bakery/98_local_checks_bakery"
        ["check_borg_backup"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/main/local_checks/borg_backup/check_borg_backup"
        ["check_sql_dump"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/main/local_checks/sql_dump/check_sql_dump"
        ["reboot_required"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/reboot_required/reboot_required"
        ["pve_monitored_guests"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/pve_discovery/pve_monitored_guests"
    )
    # Add PVE backup config check if running on Proxmox VE
    if [[ $is_pve -eq 1 ]]; then
        LOCAL_CHECKS["pve_backup_config_check"]="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/pve_backup_config/pve_backup_config_check"
    fi

    # Descriptions to display next to each local check for user clarity
    declare -A DESCRIPTIONS=(
        ["98_local_checks_bakery"]="| Check_MK local checks bakery"
        ["check_borg_backup"]="| BorgBackup monitoring"
        ["check_sql_dump"]="| SQL-Dump check"
        ["reboot_required"]="| Reboot required"
        ["pve_monitored_guests"]="| PVE monitored guests"
    )
    if [[ $is_pve -eq 1 ]]; then
        DESCRIPTIONS["pve_backup_config_check"]="| PVE backup config monitoring"
    fi

    LOCAL_CHECKS_DIR="/usr/lib/check_mk_agent/local"

    # Discover which local checks are already installed
    local installed_local_checks=()
    if [[ -d "$LOCAL_CHECKS_DIR" ]]; then
        for f in "$LOCAL_CHECKS_DIR"/*; do
            [[ -f "$f" ]] && installed_local_checks+=("$(basename "$f")")
        done
    fi

    # Build checklist items: local check filename, description, and ON/OFF status
    local CHECKLIST_ITEMS=()
    for check in "${!LOCAL_CHECKS[@]}"; do
        local status="OFF"
        for installed in "${installed_local_checks[@]}"; do
            [[ "$installed" == "$check" ]] && status="ON"
        done
        CHECKLIST_ITEMS+=("$check" "${DESCRIPTIONS[$check]}" "$status")
    done

    # Add own checks to the list to prevent from removal
    for owncheck in "${installed_local_checks[@]}"; do
        local found=0
        for check in "${!LOCAL_CHECKS[@]}"; do
            [[ "$owncheck" == "$check" ]] && found=1
        done
        if [[ $found -eq 0 ]]; then
            CHECKLIST_ITEMS+=("$owncheck" "| OWN SCRIPT" "ON")
        fi
    done

    # Show checklist dialog for user to select which local checks to install/manage
    local selected_local_checks=()
    {
        whiptail --title "Local checks management" \
            --checklist "Please select your local checks:" \
            20 80 10 \
            "${CHECKLIST_ITEMS[@]}" \
            --separate-output 3>&1 1>&2 2>&3
    } > /tmp/selected_local_checks.txt
    local retcode=$?
    mapfile -t selected_local_checks < /tmp/selected_local_checks.txt
    rm /tmp/selected_local_checks.txt
    if [[ $retcode -ne 0 ]]; then
        main  # Return to main menu on cancel or error
        return
    fi

    # Install/update all selected local checks by downloading anew
    for check in "${selected_local_checks[@]}"; do
        install_local_check_file "$check" "${LOCAL_CHECKS[$check]}"
    done

    # Special handling if PVE backup config check was selected
    if [[ " ${selected_local_checks[*]} " == *" pve_backup_config_check "* ]]; then
        install_pve_backup_config_cron_script
        setup_pve_backup_config_cronjob
    fi

    # Remove previously installed but now unselected local checks
    for check in "${installed_local_checks[@]}"; do
        local still_selected=0
        for selected in "${selected_local_checks[@]}"; do
            [[ "$selected" == "$check" ]] && still_selected=1
        done
        # Check if local check is not managed by the script (not part of LOCAL_CHECKS)
        local is_ownscript=1
        for known in "${!LOCAL_CHECKS[@]}"; do
            [[ "$check" == "$known" ]] && is_ownscript=0
        done
        # Do not remove OWN SCRIPTS
        if [[ $still_selected -eq 0 && $is_ownscript -eq 0 ]]; then
            remove_local_check_file "$check"
        fi
    done

    # Show summary of the operation and return to main menu
    local installed_count=${#selected_local_checks[@]}
    local installed_list=""
    for check in "${selected_local_checks[@]}"; do
        installed_list+="$check, "
    done

    show_success_box "Local checks updated. $installed_count scripts are installed:\n\n$installed_list"
    log "[INFO] Local checks installed ($installed_count):"
    for check in "${selected_local_checks[@]}"; do
        log "  - $check"
    done
    main
}

# Local checks configuration menu
# - Loops until user chooses to return
# - Adds "Configure PVE VM Blacklist Local Check" menu item only if Checkmk site is active
# - Calls appropriate function based on user's choice
configure_local_checks_menu() {
    while true; do
        local MENU_ITEMS=()

        # Add PVE configuration option if Checkmk site is active
        if is_checkmk_active; then
            MENU_ITEMS+=("Configure_PVE" "Configure PVE VM Blacklist Local Check")
        fi

        MENU_ITEMS+=("Return" "Return to previous menu")

        OPTION=$(whiptail --title "Local Checks Configuration" --menu \
            "Please choose a local check configuration to manage:" 15 60 4 \
            "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

        case "$OPTION" in
            Configure_PVE)
                configure_pve_local_check
                ;;
            Return|"")
                main
                ;;
            *)
                whiptail --msgbox "Invalid option. Please try again." 8 40
                ;;
        esac
    done
}

############################################################
# === 2.1.1 PVE Menues ===
############################################################

# Function: Select a Proxmox VE host
# - Loads previously saved host IPs/hostnames from the file /etc/check_mk/pve_discovery_server.txt
# - Presents a menu to select an existing host or add a new one via input box
# - If no hosts are stored yet, asks for input directly
# - Saves new entries if not already present in the file
# - Returns the selected or newly added host IP/hostname string
select_pve_host() {
    local SERVER_FILE="/etc/check_mk/pve_discovery_server.txt"
    mkdir -p "$(dirname "$SERVER_FILE")"
    touch "$SERVER_FILE"

    # Read stored server IPs if any
    local server_ips=()
    if [[ -s "$SERVER_FILE" ]]; then
        mapfile -t server_ips < "$SERVER_FILE"
    fi

    if (( ${#server_ips[@]} > 0 )); then
        # Build a menu list with existing hosts plus an option to add a new one
        local menu_options=()
        local idx=1
        for ip in "${server_ips[@]}"; do
            menu_options+=("$idx" "$ip")
            ((idx++))
        done
        menu_options+=("$idx" "New PVE server")

        # Show the menu and let user select or opt to add new host
        local choice
        choice=$(whiptail --title "Select Proxmox VE server" --menu \
            "Select a Proxmox VE host IP or choose to add a new one:" 15 60 6 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3) || return 1

        if [[ "$choice" == "$idx" ]]; then
            # Input box for new host IP/hostname
            local new_ip
            new_ip=$(whiptail --inputbox "Enter new Proxmox VE Host IP or hostname:" 10 60 3>&1 1>&2 2>&3) || return 1
            if [[ -z "$new_ip" ]]; then
                whiptail --msgbox "No host entered. Please try again." 10 50
                return 2
            fi
            # Save new IP if it doesn't already exist in the file
            if ! grep -Fxq "$new_ip" "$SERVER_FILE"; then
                echo "$new_ip" >> "$SERVER_FILE"
            fi
            echo "$new_ip"
        else
            # Return the selected existing host IP/hostname
            local idx_choice=$((choice-1))
            echo "${server_ips[$idx_choice]}"
        fi

    else
        # No stored hosts, prompt for IP/hostname input directly
        local input_ip
        input_ip=$(whiptail --inputbox "Enter Proxmox VE Host IP or hostname:" 10 60 3>&1 1>&2 2>&3) || return 1
        if [[ -z "$input_ip" ]]; then
            whiptail --msgbox "No host entered. Please try again." 10 50
            return 2
        fi
        # Save newly input IP
        if ! grep -Fxq "$input_ip" "$SERVER_FILE"; then
            echo "$input_ip" >> "$SERVER_FILE"
        fi
        echo "$input_ip"
    fi
}

# Function: Manage the VM blacklist for a given Proxmox VE host
# - Reads existing blacklist entries for the host from pve_discovery_blacklist.txt
# - Retrieves the list of VMs on the host using qm list command (via helper function get_qm_list)
# - Presents a checklist for the user to select which VMs should be blacklisted (excluded from discovery)
# - Writes the updated blacklist entries back, removing old entries for the host
manage_vm_blacklist() {
    local host="$1"
    local BLACKLIST_FILE="/etc/check_mk/pve_discovery_blacklist.txt"
    mkdir -p "$(dirname "$BLACKLIST_FILE")"
    touch "$BLACKLIST_FILE"

    # Get VM inventory from the Proxmox host
    local qm_list
    qm_list=$(get_qm_list "$host") || {
        whiptail --msgbox "Failed to get 'qm list' from $host. Check SSH access and try again." 10 60
        return 1
    }

    # Get LXC inventory from the Proxmox host
    local pct_list
    pct_list=$(get_pct_list "$host") || {
        whiptail --msgbox "Failed to get 'lxc list' from $host. Check SSH access and try again." 10 60
        return 1
    }

    # Read current blacklist VM IDs for the host
    mapfile -t existing_blacklist < <(grep "^$host:" "$BLACKLIST_FILE" 2>/dev/null | cut -d: -f2)

    # Build checklist parameters from the VM list (skip header)
    local -a checklist_params=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        vmid=$(awk '{print $1}' <<< "$line")
        name=$(awk '{print $2}' <<< "$line")
        status=$(awk '{print $3}' <<< "$line")

        # Determine if VM is currently blacklisted
        local checked="OFF"
        for b in "${existing_blacklist[@]}"; do
            [[ "$b" == "$vmid" ]] && checked="ON" && break
        done

        checklist_params+=("$vmid" "VM: $name Status: $status" "$checked")
    done < <(echo "$qm_list" | tail -n +2)

    # If no VMs found, notify user and exit cleanly
    if [ ${#checklist_params[@]} -eq 0 ]; then
        whiptail --msgbox "No VMs found on $host." 10 50
        return 0
    fi

    # Build checklist parameters from the LXC list (skip header)
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # skip header
        if [[ "$line" =~ ^VMID[[:space:]] ]]; then
            continue
        fi
        ctid=$(awk '{print $1}' <<< "$line")
        cstatus=$(awk '{print $2}' <<< "$line")
        cname=$(awk '{print $3}' <<< "$line")
        #cname=$(awk '{for (i=4; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); }' <<< "$line")

        local checked="OFF"
        for b in "${existing_blacklist[@]}"; do
            if [ "$b" = "$ctid" ]; then
                checked="ON"
                break
            fi
        done
        checklist_params+=("$ctid" "CT: $cname: $cstatus" "$checked")
    done < <(echo "$pct_list" | tail -n +2)

    # Present checklist dialog for user to select VMs for blacklisting
    local selected
    selected=$(whiptail --title "Blacklist PVE guests on $host" --checklist \
        "Select VMs/LXCs to blacklist (ignored by discovery):" 22 78 15 \
        "${checklist_params[@]}" 3>&1 1>&2 2>&3) || return 1

    # Remove quotes from selected IDs
    IFS=' ' read -r -a selected_array <<< "$selected"
    for i in "${!selected_array[@]}"; do
        selected_array[$i]="${selected_array[$i]//\"/}"
    done

    # Rewrite blacklist file by removing old host entries and adding new selections
    grep -v "^$host:" "$BLACKLIST_FILE" 2>/dev/null > "${BLACKLIST_FILE}.tmp"
    for vmid in "${selected_array[@]}"; do
        echo "$host:$vmid" >> "${BLACKLIST_FILE}.tmp"
    done
    mv "${BLACKLIST_FILE}.tmp" "$BLACKLIST_FILE"

    whiptail --msgbox "Blacklist updated for $host.\nThe host IP is saved for local checks." 10 60
}

# Function: Configure local checks related to Proxmox VE hosts
# - Loops to select one or more PVE hosts and manage their VM blacklist
# - Continues asking if another host should be configured until user cancels
configure_pve_local_check() {
    local continue_config=1
    while (( continue_config )); do
        # Prompt to select a Proxmox VE host
        local pve_host
        pve_host=$(select_pve_host) || return
        if [[ -z "$pve_host" ]]; then
            whiptail --msgbox "No Proxmox VE Host selected. Aborting." 10 50
            return
        fi

        # Manage VM blacklist for the selected host
        manage_vm_blacklist "$pve_host" || continue

        # Ask user whether to configure another host
        whiptail --yesno "Configure another Proxmox VE host?" 10 50
        continue_config=$?
        if (( continue_config != 0 )); then
            break
        fi
    done
}

############################################################
# === 2.1.2 Site selection ===
############################################################

# Function: Select a monitoring site and load its configuration
# - If a KEY is set, attempts to load configuration based on the key
# - If key is invalid or config is unreadable, shows error and exits
# - If no sites are predefined, either requests manual input or directly returns for RAW mode
# - If sites are available, prompts user to choose one from cloud or raw sites
# - Validates the selected site format and extracts type and index
# - Assigns the selected site's details (URLs, names, versions, etc.) to variables
# - Checks and prompts for mandatory fields relevant to the site type (cloud/raw)
select_site_and_load_config() {
    # If KEY exists, load config associated with key and validate it
    if [[ -n "$KEY" ]]; then
        if ! load_config_if_key_valid; then
            show_error_box "Key invalid or config file not readable."
            exit 1
        fi
        SITE_PLUGIN_URL="https://monitoring.admin-intelligence.de/checkmk/check_mk/agents/plugins"
    else
        # If no sites defined and cloud inclusion is enabled
        if [[ ${#SITE_CLOUD_LIST[@]} -eq 0 && ${#SITE_RAW_LIST[@]} -eq 0 ]]; then
            if [[ "$include_cloud" -eq 1 ]]; then
                log "[INFO] No predefined sites found - starting manual input"
                # Ask user for manual site input
                input_site_variables "$include_cloud"
                return
            else
                # RAW site mode: no input needed, start directly
                return
            fi
        fi
        # Show normal site selection menu if sites exist
        SELECTED_SITE=$(choose_site)
        if [[ $? -ne 0 || -z "$SELECTED_SITE" ]]; then
            show_error_box "No site selected. Exiting."
            exit 1
        fi

        # Validate the format of the chosen site: cloud_site_## or raw_site_##
        if [[ "$SELECTED_SITE" =~ ^(cloud|raw)_site_([0-9]+)$ ]]; then
            type="${BASH_REMATCH[1]}"
            idx="${BASH_REMATCH[2]}"
        else
            show_error_box "Invalid site selection."
            exit 1
        fi

        # Reference the correct associative array depending on type
        if [[ "$type" == "cloud" ]]; then
            declare -n SITE_REF=SITE_CLOUD_LIST
        elif [[ "$type" == "raw" ]]; then
            declare -n SITE_REF=SITE_RAW_LIST
        fi

        # Load site configuration details into variables from site list
        SITE_URL="${SITE_REF["site_${idx}_url"]}"
        SITE_REGISTER="${SITE_REF["site_${idx}_register"]}"
        SITE_NAME="${SITE_REF["site_${idx}_name"]}"
        SITE_TEXT="${SITE_REF["site_${idx}_text"]}"
        SITE_UPDATEUSERPASS="${SITE_REF["site_${idx}_updateuserpass"]}"
        SITE_AGENT_PACKAGE="${SITE_REF["site_${idx}_agent_package"]}"
        SITE_AGENT_VERSION="${SITE_REF["site_${idx}_agent_version"]}"
        SITE_AGENT_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/"
        # SITE_PLUGIN_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/plugins"
        SITE_PLUGIN_URL="https://monitoring.admin-intelligence.de/checkmk/check_mk/agents/plugins"

        # Check mandatory fields for the selected site and ask if missing
        check_and_ask_mandatory_fields "$type" "$idx"
    fi
}

############################################################
# === 2.1.3 Additional Menues ===
############################################################

# Function: Show a menu for selecting additional tools or scripts
# - Currently provides a placeholder option indicating no tools available
# - Uses whiptail menu dialog for user interaction
additional_tools_menu() {
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"

    TOOLHEADER="\nSelect an additional tool or script"

    TOOLCHOICE=$(whiptail --title "Checkmk tools selector" --menu \
        "$TOOLHEADER" 12 70 2 \
        "TBD" "| no additional tools available" \
        3>&1 1>&2 2>&3)
    return $?
}


############################################################
# === 3. Key and config checks ===
############################################################

# Function: Verify that the provided key matches the expected SHA256 hash
# - Takes an input key string, hashes it with sha256sum
# - Compares against global EXPECTED_HASH, returns success if match
check_key() {
    local input_key="$1"
    local input_hash
    input_hash=$(echo -n "$input_key" | sha256sum | awk '{print $1}')
    [[ "$input_hash" == "$EXPECTED_HASH" ]]
}

# Function: Load configuration if the provided key is valid
# - Validates key with check_key
# - Downloads configuration from CONFIG_URL using curl
# - Evaluates downloaded config content to load associative arrays SITE_CLOUD_LIST and SITE_RAW_LIST
# - If KEY is present, automatically selects a site without menu; otherwise falls back to interactive selection
# - Checks that at least one cloud or raw site exists; otherwise shows error and exits
# - Calls check_and_ask_mandatory_fields() to prompt for any missing required values
load_config_if_key_valid() {
    if check_key "$KEY"; then
        CONFIG_CONTENT=$(curl -fsSL4 "$CONFIG_URL")
        if [[ $? -ne 0 ]] || [[ -z "$CONFIG_CONTENT" ]]; then
            show_error_box "Cannot open configuration file or configuration is empty."
            exit 1
        fi

        # Clear old site arrays then evaluate new config content
        unset SITE_CLOUD_LIST
        unset SITE_RAW_LIST
        eval "$CONFIG_CONTENT"

        # Automatic selection of site if KEY is present (no menu)
        if [[ -n "$KEY" ]]; then
            # Find first cloud site available
            for key in "${!SITE_CLOUD_LIST[@]}"; do
                if [[ "$key" =~ ^site_([0-9]+)_url$ ]]; then
                    idx="${BASH_REMATCH[1]}"
                    type="cloud"
                    break
                fi
            done

            # If no cloud site found, fallback to raw site
            if [[ -z "$idx" ]]; then
                for key in "${!SITE_RAW_LIST[@]}"; do
                    if [[ "$key" =~ ^site_([0-9]+)_url$ ]]; then
                        idx="${BASH_REMATCH[1]}"
                        type="raw"
                        break
                    fi
                done
            fi

            # If no valid site found, error out
            if [[ -z "$idx" ]]; then
                show_error_box "No cloud site definition found in config file."
                exit 1
            fi

            # Set selected site string and log it
            SELECTED_SITE="${type}_site_${idx}"
            log "[INFO] Auto-selected site: $SELECTED_SITE (via KEY)"

        else
            # Otherwise prompt interactive selection
            SELECTED_SITE=$(choose_site)
            if [[ $? -ne 0 ]] || [[ -z "$SELECTED_SITE" ]]; then
                show_error_box "No site selected. Exiting."
                exit 1
            fi
            check_and_ask_mandatory_fields "$type" "$idx"
        fi

        # Parse selected site type and index, then load its config data
        if [[ "$SELECTED_SITE" =~ ^(cloud|raw)_site_([0-9]+)$ ]]; then
            type="${BASH_REMATCH[1]}"
            idx="${BASH_REMATCH[2]}"
            if [[ "$type" == "cloud" ]]; then
                check_and_ask_mandatory_fields "$type" "$idx"
            fi

            # Declare SITE_REF as a nameref to the appropriate associative array
            if [[ "$type" == "cloud" ]]; then
                declare -n SITE_REF=SITE_CLOUD_LIST
            elif [[ "$type" == "raw" ]]; then
                declare -n SITE_REF=SITE_RAW_LIST
            fi

            # Extract selected site details into variables for later use
            SITE_URL="${SITE_REF["site_${idx}_url"]}"
            SITE_REGISTER="${SITE_REF["site_${idx}_register"]}"
            SITE_NAME="${SITE_REF["site_${idx}_name"]}"
            SITE_TEXT="${SITE_REF["site_${idx}_text"]}"
            SITE_UPDATEUSERPASS="${SITE_REF["site_${idx}_updateuserpass"]}"
            SITE_UPDATE_PROTOCOL="${SITE_REF["site_${idx}_update_protocol"]}"
            SITE_AGENT_PACKAGE="${SITE_REF["site_${idx}_agent_package"]}"
            SITE_AGENT_VERSION="${SITE_REF["site_${idx}_agent_version"]}"
            SITE_AGENT_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/"
            # SITE_PLUGIN_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/plugins"
            SITE_PLUGIN_URL="https://monitoring.admin-intelligence.de/checkmk/check_mk/agents/plugins"

            # Log successful config load
            log "Configuration loaded for site \"$SITE_TEXT\""

        else
            show_error_box "Wrong site selection."
            exit 1
        fi

    else
        # Key not valid or missing
        show_error_box "Wrong or missing key, Access denied."
        exit 1
    fi
}

# Function: Check for missing mandatory fields in the selected site configuration and prompt user to input them
# - site_type: "cloud" or "raw"
# - site_index: numerical index of the site (e.g., 1,2,...)
# - Prompts user for required fields, including URL and name for cloud, name for raw
# - Also prompts optionally for update user password in cloud sites
# - Updates the respective SITE_CLOUD_LIST or SITE_RAW_LIST associative array by reference
check_and_ask_mandatory_fields() {
    local site_type="$1"     # cloud or raw
    local site_index="$2"    # e.g., 1, 2, ...

    if [[ "$site_type" != "cloud" ]]; then
        return
    fi

    local -n arr_ref        # Nameref to associative array SITE_CLOUD_LIST or SITE_RAW_LIST

    # Determine array and mandatory fields based on site type
    if [[ "$site_type" == "cloud" ]]; then
        arr_ref=SITE_CLOUD_LIST
        local fields=("url" "name" "register")
    else
        arr_ref=SITE_RAW_LIST
        local fields=("name")
    fi

    local missing_fields=()
    local field_val=""
    local prompt=""

    # Find which mandatory fields are missing or empty
    for field in "${fields[@]}"; do
        field_val="${arr_ref["site_${site_index}_$field"]}"
        if [[ -z "$field_val" ]]; then
            missing_fields+=("$field")
        fi
    done

    # For cloud sites, also check optional update user password field
    if [[ "$sitetype" == "cloud" ]] && [[ " ${missing_fields[*]} " =~ " url " ]]; then
        if [[ -z "${arr_ref["site_${site_index}_updateuserpass"]}" ]]; then
            missing_fields+=("updateuserpass_optional")
        fi
    fi

    # Prompt for each missing field, handling optional or mandatory accordingly
    for missing in "${missing_fields[@]}"; do
        case "$missing" in
            url)
                prompt="Enter the Site URL (e.g. https://monitoring.example.com):"
                ;;
            register)
                prompt="Enter the Site registration endpoint:"
                ;;
            name)
                prompt="Enter the Site name:"
                ;;
            text)
                prompt="Enter the Site description:"
                ;;
            protocol)
                prompt="Enter the used protocol (http / https):"
                ;;
            updateuserpass_optional)
                prompt="Enter the update user password (optional):"
                ;;
        esac

        if [[ "$missing" == "updateuserpass_optional" ]]; then
            # Optional: allow empty input
            val=$(whiptail --title "Mandatory field" --inputbox "$prompt" 10 80 "" 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                arr_ref["site_${site_index}_updateuserpass"]="$val"
            fi
        else
            # Mandatory: reprompt until non-empty input or user cancels (exit script)
            while :; do
                val=$(whiptail --title "Mandatory field" --inputbox "$prompt" 10 80 "" 3>&1 1>&2 2>&3)
                if [[ $? -ne 0 ]]; then
                    whiptail --title "Error" --msgbox "This field is required. The script will exit." 8 60
                    exit 1
                fi
                if [[ -n "$val" ]]; then
                    arr_ref["site_${site_index}_$missing"]="$val"
                    break
                fi
            done
        fi
    done

    # After updates, reload site variables for consistency
    SITE_URL="${SITE_REF["site_${idx}_url"]}"
    SITE_REGISTER="${SITE_REF["site_${idx}_register"]}"
    SITE_NAME="${SITE_REF["site_${idx}_name"]}"
    SITE_TEXT="${SITE_REF["site_${idx}_text"]}"
    SITE_UPDATEUSERPASS="${SITE_REF["site_${idx}_updateuserpass"]}"
    SITE_UPDATE_PROTOCOL="${SITE_REF["site_${idx}_update_protocol"]}"
    SITE_AGENT_PACKAGE="${SITE_REF["site_${idx}_agent_package"]}"
    SITE_AGENT_VERSION="${SITE_REF["site_${idx}_agent_version"]}"
    SITE_AGENT_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/"
    # SITE_PLUGIN_URL="${SITE_URL}/${SITE_NAME}/check_mk/agents/plugins"
    SITE_PLUGIN_URL="https://monitoring.admin-intelligence.de/checkmk/check_mk/agents/plugins"
}

############################################################
# === 4. Installation and update logic ===
############################################################

# Function: Download or install the Checkmk agent package
# - Uses SITE_AGENT_PACKAGE and SITE_AGENT_URL variables for target package
# - Supports two actions via parameter: "download" and "install"
# - Downloads agent package via wget
# - Installs package using dpkg -i, aborts on error
download_and_install() {
    SITE_AGENT_PACKAGE="check-mk-agent_2.4.0p5-1_all.deb"
    SITE_AGENT_URL="https://github.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/raw/main/programs/"
    case "$1" in
    download)
        wget --no-check-certificate "${SITE_AGENT_URL}${SITE_AGENT_PACKAGE}" -O "$SITE_AGENT_PACKAGE" || {
            show_error_box "Error during download! Script will exit."
            abort_script
        }
        ;;
    install)
        dpkg -i --force-confnew ./"$SITE_AGENT_PACKAGE" || {
            show_error_box "Error during installation! Script will exit."
            abort_script
        }
        ;;
    esac
}

# Function: Install python3-docker package quietly, show error on failure
install_python3_docker() {
    apt install -y python3-docker >/dev/null 2>&1 || show_error_box "Error installing python3-docker!"
}

# Function: Delete old Checkmk agent configuration using cmk-agent-ctl
delete_old_config() {
    cmk-agent-ctl delete-all --enable-insecure-connections >/dev/null 2>&1
}

# Function: Configure firewall to allow port 6556 for Checkmk agent
# - Supports UFW or iptables
# - Creates backups of iptables rules before modification
# - Skips configuration if no firewall or rules detected
install_firewall() {
    log "[firewall] Checking firewall status"
    if command -v ufw >/dev/null 2>&1; then
        ufw status | grep "Status: active" >/dev/null 2>&1
        if [[ $? == 0 ]]; then
            ufw status | grep "6556" >/dev/null 2>&1
            if [[ $? == 0 ]]; then
                log "[firewall] UFW: port 6556 already opened"
            else
                log "[firewall] UFW detected - opening port 6556"
                ufw allow 6556
                log "[firewall] UFW: port 6556 is now open"
            fi
        else
            log "[firewall] UFW is installed but not active. Skipping UFW configuration."
        fi
    else
        IPTABLES_RULES="/etc/iptables/rules.v4"
        TIMESTAMP=$(date '+%Y%m%d%H%M%S')
        if [[ -f "$IPTABLES_RULES" ]]; then
            # Check if iptables rules exist
            if grep -qE '^(:[A-Z]+|-[A-Z])' "$IPTABLES_RULES"; then
                # Backup existing iptables rules
                cp "$IPTABLES_RULES" "${IPTABLES_RULES}.bak_${TIMESTAMP}"
                log "[firewall] iptables: backup created: ${IPTABLES_RULES}.bak_${TIMESTAMP}"

                # Save current rules
                iptables-save >"$IPTABLES_RULES"
                log "[firewall] iptables: actual rules saved"

                # Check if port 6556 rule exists
                grep -q -- '-A INPUT -p tcp --dport 6556 -j ACCEPT' "$IPTABLES_RULES"
                if [[ $? -ne 0 ]]; then
                    # Add iptables rule for TCP port 6556
                    sed -i '/^:OUTPUT/a -A INPUT -p tcp --dport 6556 -j ACCEPT' "$IPTABLES_RULES"
                    log "[firewall] iptables: Added rule for tcp/6556"
                else
                    log "[firewall] iptables: Port 6556 already opened"
                fi

                # Reload iptables rules
                iptables-restore <"$IPTABLES_RULES"
                log "[firewall] iptables: Rules reloaded"
            else
                log "[firewall] No iptables rules present. Skipping iptables configuration."
            fi
        else
            log "[firewall] No active firewall detected or no iptables rules found. No changes made."
        fi
    fi
}

# Function: Download and install the 'local_checks_bakery' script
# - Places it in the appropriate agent local checks directory and makes executable
install_local_checks_bakery_script() {
    local url="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/local_checks_bakery/98_local_checks_bakery"
    local dest_file="/usr/lib/check_mk_agent/local/98_local_checks_bakery"

    curl -s -o "$dest_file" "$url"
    if [[ $? -ne 0 ]]; then
        show_error_box "Error while downloading bakery script."
        return 1
    fi

    chmod +x "$dest_file"
}

# Function: Download and install the 'reboot_required' local check script
install_local_reboot_required() {
    local url="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/reboot_required/reboot_required"
    local dest_file="/usr/lib/check_mk_agent/local/reboot_required"

    curl -s -o "$dest_file" "$url"
    if [[ $? -ne 0 ]]; then
        show_error_box "Error while downloading reboot script."
        return 1
    fi

    chmod +x "$dest_file"
}

# Function: Full installation routine for raw installation mode
# - Shows progress gauge for download and install
# - Deletes old config, installs dependencies and local checks
# - Checks for Java warning
# - Launches plugin menu, prompts plugin configuration if selected
# - Sets backup file defaults and shows completion success box
install_raw() {
    show_progress_gauge "Checkmk Agent Installation" "\n\nCheckmk Agent is being downloaded and installed..." download_and_install
    delete_old_config
    install_python3_docker
    install_local_checks_bakery_script
    install_local_reboot_required
    check_java_warning_for_checkmk
    plugin_menu
    if [[ " ${SELECTED_PLUGINS[*]} " == *" mk_mysql "* ]]; then
        if whiptail --title "MySQL Plugin" --yesno "Would you like to configure the MySQL plugin now?" 10 60; then
            configure_mysql_plugin
        fi
    fi
    if [[ " ${SELECTED_PLUGINS[*]} " == *" apache_status.py "* ]]; then
        if whiptail --title "Apache Plugin" --yesno "Would you like to configure the Apache /server-status plugin now?" 10 70; then
            configure_apache_server_status
        fi
    fi
    backupfile_default
    show_success_box "All steps completed successfully.\nThank you for using the installation script.\nBest regards,\nSascha"
    clear
}

# Function: Install Checkmk agent and dependencies showing progress bar
# - Checks installed Checkmk agent version against required version
# - Downloads package if needed
# - Installs agent and resolves dependencies if any missing
# - Installs python3-docker if missing
# - Provides real-time progress updates via whiptail gauge dialog
install_agent_with_progress() {
    packages=("check-mk-agent" "python3-docker")
    agent_package="$SITE_AGENT_PACKAGE"
    agent_url="${SITE_AGENT_URL}${SITE_AGENT_PACKAGE}"

    version_check() {
        local installed_version=$(dpkg-query -W -f='${Version}' check-mk-agent 2>/dev/null)
        local required_version="$SITE_AGENT_VERSION"
        if [[ -z "$installed_version" ]]; then
            return 1
        fi
        if [[ ! $installed_version =~ ^$required_version ]]; then
            return 2
        fi
        return 0
    }

    (
        log "Checking Checkmk Agent version..."
        echo -e "XXX\n5\nChecking Checkmk Agent version...\nXXX"
        sleep 1

        if version_check; then
            log "Checkmk Agent is already installed in the required version."
            echo -e "XXX\n20\nCheckmk Agent is already installed in the required version.\nXXX"
            sleep 1
        else
            log "Downloading $agent_package..."
            echo -e "XXX\n15\nDownloading $agent_package...\nXXX"
            rm -f "$agent_package"
            if wget -q --inet4-only --timeout=3 --tries=5 "$agent_url"; then
                log "Installing $agent_package..."
                echo -e "XXX\n30\nInstalling $agent_package...\nXXX"
                sleep 1
                if dpkg -i "$agent_package"; then
                    log "$agent_package installed."
                    echo -e "XXX\n40\n$agent_package installed.\nXXX"
                    sleep 1
                else
                    log "Installing missing dependencies..."
                    echo -e "XXX\n35\nInstalling missing dependencies...\nXXX"
                    apt-get install -f -y
                    dpkg -i "$agent_package"
                    log "$agent_package installed (after resolving dependencies)."
                    echo -e "XXX\n40\n$agent_package installed (after resolving dependencies).\nXXX"
                    sleep 1
                fi
                rm -f "$agent_package"
            else
                log "Error: Download of Check_MK Agent package failed."
                echo -e "XXX\n100\nError: Download of Check_MK Agent package failed.\nXXX"
                sleep 2
                exit 1
            fi
        fi

        if dpkg -s "$PYTHON_DOCKER_PACKAGE" &>/dev/null; then
            log "$PYTHON_DOCKER_PACKAGE is already installed."
            echo -e "XXX\n60\n$PYTHON_DOCKER_PACKAGE is already installed.\nXXX"
            sleep 1
        else
            log "Installing $PYTHON_DOCKER_PACKAGE..."
            echo -e "XXX\n50\nInstalling $PYTHON_DOCKER_PACKAGE...\nXXX"
            apt install -y "$PYTHON_DOCKER_PACKAGE"
            log "$PYTHON_DOCKER_PACKAGE installed."
            echo -e "XXX\n60\n$PYTHON_DOCKER_PACKAGE installed.\nXXX"
            sleep 1
        fi

        log "Cleanup and finishing..."
        echo -e "XXX\n80\nCleanup and finishing...\nXXX"
        sleep 1

        log "Installation completed."
        echo -e "XXX\n100\nInstallation completed.\nXXX"
        sleep 1
    ) | whiptail --title "Checkmk Agent Installation" --gauge "Checkmk Agent and dependencies are being installed..." 8 70 0

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        show_error_box "Error during download or installation of Checkmk Agent!"
        abort_script
    fi
}

# Function: Uninstall Checkmk agent and perform cleanup
# - Prompts the user for confirmation
# - Purges package and removes related directories and files
# - Shows success or error messages accordingly
uninstall_and_cleanup() {
    if whiptail --title "Remove and cleanup Checkmk agent" --yesno "Checkmk agent and according plugins and configurations will be removed. Proceed?" 10 60; then
        if apt purge -y check-mk-agent && rm -rfv /var/lib/cmk-agent /var/lib/check_mk_agent /etc/check_mk /usr/lib/check_mk_agent; then
            show_success_box "Checkmk agent has been removed and all files has been cleaned up."
        else
            show_error_box "Error while removing / cleanup"
        fi
    else
        show_info_box "Removal and cleanup canceled"
    fi
    main
}

# Function: Shows a whiptail progress gauge for various installation phases
# - Parameters: Title, message, function to run (download_and_install), max percent (optional)
# - Provides step updates and logs output lines of the function
show_progress_gauge() {
    # Parameter: $1 = title, $2 = message, $3 = function, $4 = max percent
    log "Starting progress gauge: $1 - $2"
    (
        echo "10"
        sleep 0.5
        log "Starting download..."
        echo -e "XXX\n30\n# Starting download...\nXXX"
        $3 download > >(while read line; do log "[download] $line"; done) 2>&1 && echo "50"
        log "Installation in progress..."
        echo -e "XXX\n60\n# Installation in progress...\nXXX"
        $3 install > >(while read line; do log "[install] $line"; done) 2>&1 && echo "80"
        log "Opening firewall..."
        install_firewall
        echo -e "XXX\n90\n# Opening Firewall...\nXXX"
        sleep 0.5
        log "Finishing..."
        echo -e "XXX\n95\n# Finishing...\nXXX"
        sleep 0.5
        echo "100"
        sleep 0.5
    ) | whiptail --gauge "$2" 10 60 0 --title "$1"
    log "Finished installation progress: $1"
}

############################################################
# === 5. Plugin managent and configuration ===
############################################################

# Directory where Checkmk agent plugins are located
PLUGIN_DIR="/usr/lib/check_mk_agent/plugins"

# Default plugins (always enabled)
# Format: plugin_name description default_status
DEFAULT_PLUGINS=(
    "lvm" "Linux Logical Volume Manager: monitors LVM volumes and their usage on Linux systems." "ON"
    "mk_apt" "APT package management monitoring: monitors pending updates and package status on Debian/Ubuntu systems." "ON"
    "mk_logins" "Login monitoring: monitors user logins and login attempts on the system." "ON"
    "mk_sshd_config" "SSHD configuration monitoring: monitors and checks the configuration of the SSH daemon." "ON"
)

# Database related plugins (default off)
DB_PLUGINS=(
    "mk_mysql" "MySQL/MariaDB monitoring: monitors MySQL/MariaDB databases for status and performance." "OFF"
    "mk_postgres.py" "PostgreSQL monitoring: monitors PostgreSQL databases for status and performance." "OFF"
    "mk_mongodb.py" "MongoDB monitoring: monitors the status, performance, and replication of MongoDB databases." "OFF"
    "mk_redis" "Redis monitoring: monitors the status and performance of a Redis server." "OFF"
    "mk_sap.py" "SAP monitoring: monitors the status and performance of SAP systems." "OFF"
    "mk_sap_hana" "SAP HANA monitoring: monitors SAP HANA databases and their performance." "OFF"

    # Alternative plugins (not active, full description below)
    # "mk_postgres_2.py" "PostgreSQL monitoring alternative: alternative version to monitor PostgreSQL databases." "OFF"
    # "mk_mongodb_2.py" "MongoDB monitoring alternative: alternative version to monitor MongoDB databases." "OFF"
    # "mk_sap_2.py" "SAP monitoring alternative: alternative version to monitor SAP systems." "OFF"
    # "mk_sap.aix" "SAP monitoring for AIX systems." "OFF"
    # "mk_oracle" "Oracle database monitoring: comprehensive monitoring of Oracle databases and their components." "OFF"
    # "mk_oracle_crs" "Oracle Clusterware monitoring: monitors Oracle Clusterware components." "OFF"
    # "mk_db2.linux" "IBM DB2 monitoring for Linux: monitors IBM DB2 databases on Linux systems." "OFF"
    # "mk_db2.aix" "IBM DB2 monitoring for AIX: monitors IBM DB2 databases on AIX systems." "OFF"
    # "mk_informix" "Informix database monitoring: monitors the status and performance of an Informix database." "OFF"
    # "db2_mem" "IBM DB2 memory monitoring: monitors memory usage of DB2 databases." "OFF"
    # "ibm_mq" "IBM MQ monitoring: monitors IBM Message Queue systems." "OFF"
)

# Storage plugins (default off)
STORAGE_PLUGINS=(
    "mk_ceph.py" "Ceph storage cluster monitoring: monitors the status and performance of a Ceph storage cluster." "OFF"
    "mk_filestats.py" "Filesystem statistics: collects and monitors detailed statistics about files and filesystems." "OFF"
    "lnx_quota" "Linux filesystem quota: monitors user and group quotas on Linux filesystems." "OFF"
    "smart" "SMART monitoring: monitors disks using SMART for errors and status." "OFF"

    # Alternative plugins
    # "mk_ceph_2.py" "Ceph storage monitoring alternative: alternative version to monitor a Ceph cluster." "OFF"
    # "mk_filestats_2.py" "Filesystem statistics alternative: alternative version to monitor filesystems." "OFF"
    # "smart_posix" "SMART monitoring alternative for POSIX systems." "OFF"
    # "asmcmd.sh" "Oracle ASM command monitoring: monitors Oracle ASM Automatic Storage Management using asmcmd commands." "OFF"
    # "vxvm" "Veritas Volume Manager monitoring: monitors Veritas Volume Manager volumes and their status." "OFF"
)

# Webserver plugins (default off)
WEBSERVER_PLUGINS=(
    "apache_status.py" "Apache status monitoring: monitors the status and performance of an Apache web server." "OFF"
    "nginx_status.py" "NGINX status monitoring: monitors the status and performance of an NGINX web server." "OFF"

    # Alternative plugins
    # "apache_status_2.py" "Apache status monitoring alternative: alternative version to monitor an Apache web server." "OFF"
    # "nginx_status_2.py" "NGINX status monitoring alternative: alternative version to monitor an NGINX web server." "OFF"
)

# Network plugins (default off)
NETWORK_PLUGINS=(
    "netstat.linux" "Network status Linux: monitors network connections and ports on Linux systems." "OFF"
    "mk_iptables" "IPTables firewall monitoring: monitors the status and configuration of the IPTables firewall on Linux." "OFF"
    "dnsclient" "DNS client monitoring: monitors DNS resolution and response times on the system." "OFF"
    "mtr.py" "Network path analysis (MTR): performs MTR analyses (traceroute, ping) for network diagnostics." "OFF"

    # Alternative plugins
    # "zorp" "Zorp firewall monitoring: monitors the status and configuration of the Zorp firewall." "OFF"
    # "netstat.aix" "Network status AIX: monitors network connections and ports on AIX systems." "OFF"
    # "netstat.solaris" "Network status Solaris: monitors network connections and ports on Solaris systems." "OFF"
    # "mtr_2.py" "Network path analysis (MTR) alternative: alternative version for network diagnostics." "OFF"
    # "lnx_container_host_if.linux" "Linux container host interface monitoring." "OFF"
)

# Security plugins (default off)
SECURITY_PLUGINS=(
    "kaspersky_av" "Kaspersky Antivirus monitoring: monitors the status and update state of Kaspersky Antivirus installations." "OFF"
    "symantec_av" "Symantec Antivirus monitoring: monitors the status and update state of Symantec Antivirus installations." "OFF"
    "jar_signature" "JAR signature check: checks digital signatures of JAR files for validity." "OFF"

    # Alternative disabled (none present, but example)
    # "runas" "RunAs monitoring: monitors the use of RunAs and sudo on the system." "OFF"
)

# Monitoring tools plugins (default off)
MONITORING_PLUGINS=(
    "cmk-update-agent" "Checkmk agent update tool: manage and update the Checkmk agent on monitored systems." "OFF"
    "mk_logwatch.py" "Logfile monitoring: monitors defined log files for errors, warnings, and patterns." "OFF"
    "mk_tsm" "IBM Tivoli Storage Manager monitoring: monitors the state and backups of IBM TSM." "OFF"
    "mk_tinkerforge.py" "Tinkerforge monitoring: monitors Tinkerforge sensors and modules." "OFF"
    "mk_suseconnect" "SUSE Connect monitoring: monitors SUSE registration and updates." "OFF"
    "mk_zypper" "Zypper package management monitoring: monitors package status on SUSE systems." "OFF"
    "mk_omreport" "Dell OpenManage monitoring: monitors Dell hardware and system status." "OFF"
    "robotmk_agent_plugin" "Robotmk monitoring plugin." "OFF"

    # Alternative plugins (commented out, with description)
    # "plesk_backups.py" "Plesk backup monitoring: monitors backup status in Plesk." "OFF"
    # "plesk_domains.py" "Plesk domain monitoring: monitors domains in Plesk." "OFF"
    # "unitrends_backup" "Unitrends backup monitoring." "OFF"
    # "unitrends_replication.py" "Unitrends replication monitoring." "OFF"
    # "cmkupdateagent.py" "Checkmk agent update Python plugin: Python module for controlling and monitoring agent updates." "OFF"
    # "mk_logwatch_2.py" "Logfile monitoring alternative: alternative version for monitoring log files." "OFF"
    # "mk_tinkerforge_2.py" "Tinkerforge monitoring alternative: alternative version for monitoring Tinkerforge." "OFF"
    # "plesk_backups_2.py" "Plesk backup monitoring alternative." "OFF"
    # "plesk_domains_2.py" "Plesk domain monitoring alternative." "OFF"
    # "unitrends_replication_2.py" "Unitrends replication monitoring alternative." "OFF"
)

# Miscellaneous plugins (default off)
MISC_PLUGINS=(
    "mk_docker.py" "Docker container monitoring: monitors running containers, images, and resource usage on Docker hosts." "OFF"
    "mk_inotify.py" "Linux inotify monitoring: monitors file and directory changes using inotify on Linux systems." "OFF"
    "mk_inventory.linux" "Hardware/software inventory Linux: collects inventory data about hardware and software on Linux systems." "OFF"
    # "mk_inventory.aix" "Hardware/software inventory AIX." "OFF"
    # "mk_inventory.solaris" "Hardware/software inventory Solaris." "OFF"
    "mk_site_object_counts" "Checkmk site object counter: counts and monitors the number of objects (hosts, services) in a Checkmk site." "OFF"
    "mk_filehandler" "File operations monitoring." "OFF"
    "mk_scaleio" "Dell EMC ScaleIO monitoring." "OFF"
    "mk_nfsiostat" "NFS IO statistics monitoring." "OFF"
    "nfsexports" "NFS export monitoring." "OFF"
    "nfsexports.solaris" "NFS export monitoring for Solaris." "OFF"
    "mailman2_lists" "Mailman 2 lists monitoring." "OFF"
    "mailman3_lists" "Mailman 3 lists monitoring." "OFF"
    "isc_dhcpd.py" "ISC DHCP server monitoring." "OFF"
    "nvidia_smi" "NVIDIA GPU monitoring." "OFF"

    # Alternatives & outdated variants (disabled, commented)
    # "mk_docker_2.py" "Docker container monitoring alternative: alternative version for monitoring Docker containers." "OFF"
    # "mk_inotify_2.py" "Linux inotify monitoring alternative: alternative version for monitoring file changes." "OFF"
    # "isc_dhcpd_2.py" "ISC DHCP server monitoring alternative." "OFF"
    # "db2_mem" "IBM DB2 memory monitoring (alternative)." "OFF"
)

# =================================================================
# Recommendation functions used to check environment suitability
# Each function returns 0 if plugin is recommended (present), 1 otherwise

# Default plugins (always recommended)
recommend_lvm() { is_installed lvm2; }
recommend_mk_apt() { is_installed apt; }
recommend_mk_logins() { return 0; } # Immer sinnvoll
recommend_mk_sshd_config() { is_installed sshd || file_exists /etc/ssh/sshd_config; }

# Database plugin recommendations, e.g. check if relevant DB server/package installed or running process exists
recommend_mk_db2_linux() { is_installed db2 || dir_exists /opt/ibm/db2; }
recommend_mk_db2_aix() { is_installed db2 || dir_exists /opt/ibm/db2; }
recommend_mk_mysql() { is_installed mysql-server || is_installed mariadb-server || is_process_running mysqld; }
recommend_mk_postgres_py() { is_installed postgresql || is_process_running postgres; }
recommend_mk_postgres_2_py() { is_installed postgresql || is_process_running postgres; }
recommend_mk_oracle() { dir_exists /opt/oracle || dir_exists /u01/app/oracle; }
recommend_mk_oracle_crs() { dir_exists /u01/app/11.2.0/grid; }
recommend_mk_mongodb_py() { is_installed mongodb-org || is_installed mongod || is_process_running mongod; }
recommend_mk_mongodb_2_py() { is_installed mongodb-org || is_installed mongod || is_process_running mongod; }
recommend_mk_redis() { is_installed redis-server || is_process_running redis-server; }
recommend_mk_informix() { dir_exists /opt/ibm/informix || is_process_running oninit; }
recommend_mk_sap_hana() { dir_exists /usr/sap || is_process_running hdbnameserver; }
recommend_mk_sap_py() { dir_exists /usr/sap || is_process_running sapstartsrv; }
recommend_mk_sap_2_py() { dir_exists /usr/sap || is_process_running sapstartsrv; }
recommend_mk_sap_aix() { dir_exists /usr/sap || is_process_running sapstartsrv; }
recommend_db2_mem() { is_installed db2 || dir_exists /opt/ibm/db2; }
recommend_ibm_mq() { is_installed mqm || dir_exists /opt/mqm || is_process_running amqzmgr0; }

# Storage plugin recommendations, e.g. ceph service or package detected
recommend_asmcmd_sh() { is_installed asmcmd || dir_exists /u01/app/oracle; }
recommend_vxvm() { is_installed vxvm || dir_exists /etc/vx; }
recommend_mk_ceph_py() { is_installed ceph || is_process_running ceph-mon; }
recommend_mk_ceph_2_py() { is_installed ceph || is_process_running ceph-mon; }
recommend_mk_filestats_py() { return 0; }
recommend_mk_filestats_2_py() { return 1; }
recommend_lnx_quota() { is_installed quota; }
recommend_smart() {
    if is_installed smartmontools; then
        # Check if it is a physical server
        if command -v systemd-detect-virt &>/dev/null; then
            [[ "$(systemd-detect-virt)" == "none" ]] && return 0
        else
            # Fallback: Check with dmidecode (optional)
            if command -v dmidecode &>/dev/null; then
                local manufacturer
                manufacturer="$(dmidecode -s system-manufacturer 2>/dev/null)"
                # Common VM strings (adjustable)
                case "$manufacturer" in
                    *KVM*|*VMware*|*VirtualBox*|*QEMU*|*Microsoft*) return 1 ;;
                    *) return 0 ;;
                esac
            else
                # Cannot detect virtualization, do not recommend plugin
                return 1
            fi
        fi
    fi
    return 1
}
recommend_smart_posix() { is_installed smartmontools; }

# Webserver plugin recommendations (Apache/Nginx package or running service)
recommend_apache_status_py() { is_installed apache2 || is_installed httpd || is_process_running apache2 || is_process_running httpd; }
recommend_apache_status_2_py() { is_installed apache2 || is_installed httpd || is_process_running apache2 || is_process_running httpd; }
recommend_nginx_status_py() { is_installed nginx || is_process_running nginx; }
recommend_nginx_status_2_py() { is_installed nginx || is_process_running nginx; }

# Network plugin recommendations (netstat, iptables, mtr, zorp firewall detected, etc)
recommend_netstat_linux() { is_installed net-tools || is_installed ss; }
recommend_netstat_aix() { uname | grep -qi aix; }
recommend_netstat_solaris() { uname | grep -qi solaris; }
# recommend_mk_iptables() { is_installed iptables; }
recommend_dnsclient() { return 0; }
recommend_mtr_py() { is_installed mtr; }
recommend_mtr_2_py() { is_installed mtr; }
recommend_zorp() { is_installed zorp; }
recommend_lnx_container_host_if_linux() {
  # Check if Docker is installed
  if is_installed docker; then
    # Check if at least one container exists (running or stopped)
    if [ "$(docker ps -a --format '{{.ID}}' | wc -l)" -gt 0 ]; then
      return 0
    fi
  fi

  # Check if Podman is installed
  if is_installed podman; then
    # Check if at least one container exists
    if [ "$(podman ps -a --format '{{.ID}}' | wc -l)" -gt 0 ]; then
      return 0
    fi
  fi

  # No suitable containers found → no recommendation
  return 1
}

# Security plugin recommendations
recommend_kaspersky_av() { is_installed kav4fs-control || is_installed kav4ws-control; }
recommend_symantec_av() { is_installed sav-protect; }
recommend_runas() { return 1; }
recommend_jar_signature() { is_installed java && is_process_running java; }

# Monitoring tool recommendations
recommend_cmk_update_agent() { return 1; }
recommend_cmkupdateagent_py() { return 1; }
recommend_mk_logwatch_py() { return 1; }
recommend_mk_logwatch_2_py() { return 1; }
recommend_mk_tsm() { is_installed dsmc; }
recommend_mk_tinkerforge_py() { is_installed tinkerforge; }
recommend_mk_tinkerforge_2_py() { is_installed tinkerforge; }
recommend_mk_suseconnect() { is_installed SUSEConnect; }
recommend_mk_zypper() { is_installed zypper; }
recommend_mk_omreport() { is_installed omreport; }
recommend_plesk_backups_py() { is_installed plesk; }
recommend_plesk_backups_2_py() { is_installed plesk; }
recommend_plesk_domains_py() { is_installed plesk; }
recommend_plesk_domains_2_py() { is_installed plesk; }
recommend_unitrends_backup() { is_installed unitrends; }
recommend_unitrends_replication_py() { is_installed unitrends; }
recommend_unitrends_replication_2_py() { is_installed unitrends; }
recommend_robotmk_agent_plugin() { return 1; }

# Other plugin recommendations for docker, inotify, inventory, etc
recommend_mk_docker_py() { is_installed docker || is_process_running dockerd; }
recommend_mk_docker_2_py() { is_installed docker || is_process_running dockerd; }
recommend_mk_inotify_py() { is_installed inotify-tools; }
recommend_mk_inotify_2_py() { is_installed inotify-tools; }
recommend_mk_inventory_linux() { return 0; }
recommend_mk_inventory_aix() { uname | grep -qi aix; }
recommend_mk_inventory_solaris() { uname | grep -qi solaris; }
recommend_mk_site_object_counts() { return 1; }
recommend_mk_filehandler() { return 1; }
recommend_mk_scaleio() { is_installed scaleio; }
# NFS monitoring plugin recommendations check package presence and mount status
recommend_mk_nfsiostat() {
    # Check whether the package is installed AND if an active NFS mount exists
    if is_installed nfs-common || is_installed nfs-utils; then
        mount | grep -qE 'type nfs' && return 0
    fi
    return 1
}
recommend_nfsexports() {
    # Check whether the package is installed AND if /etc/exports exists and contains a meaningful configuration
    if is_installed nfs-common || is_installed nfs-utils; then
        [[ -s /etc/exports ]] && grep -vqE '^\s*#|^\s*$' /etc/exports && return 0
    fi
    return 1
}
recommend_nfsexports_solaris() { uname | grep -qi solaris; }
# Mailman and DHCP daemon plugin recommendations by installed packages and running
recommend_mailman2_lists() { is_installed mailman; }
recommend_mailman3_lists() { is_installed mailman3; }
recommend_isc_dhcpd_py() { is_installed isc-dhcp-server || is_process_running dhcpd; }
recommend_isc_dhcpd_2_py() { is_installed isc-dhcp-server || is_process_running dhcpd; }
recommend_nvidia_smi() { is_installed nvidia-smi; }

# Mapping from plugin name to recommendation function for dynamic checks
declare -A RECOMMENDATION_CHECKS=(
    [lvm]=recommend_lvm
    [mk_apt]=recommend_mk_apt
    [mk_logins]=recommend_mk_logins
    [mk_sshd_config]=recommend_mk_sshd_config

    [mk_db2.linux]=recommend_mk_db2_linux
    [mk_db2.aix]=recommend_mk_db2_aix
    [mk_mysql]=recommend_mk_mysql
    [mk_postgres.py]=recommend_mk_postgres_py
    [mk_postgres_2.py]=recommend_mk_postgres_2_py
    [mk_oracle]=recommend_mk_oracle
    [mk_oracle_crs]=recommend_mk_oracle_crs
    [mk_mongodb.py]=recommend_mk_mongodb_py
    [mk_mongodb_2.py]=recommend_mk_mongodb_2_py
    [mk_redis]=recommend_mk_redis
    [mk_informix]=recommend_mk_informix
    [mk_sap_hana]=recommend_mk_sap_hana
    [mk_sap.py]=recommend_mk_sap_py
    [mk_sap_2.py]=recommend_mk_sap_2_py
    [mk_sap.aix]=recommend_mk_sap_aix
    [db2_mem]=recommend_db2_mem
    [ibm_mq]=recommend_ibm_mq

    [asmcmd.sh]=recommend_asmcmd_sh
    [vxvm]=recommend_vxvm
    [mk_ceph.py]=recommend_mk_ceph_py
    [mk_ceph_2.py]=recommend_mk_ceph_2_py
    [mk_filestats.py]=recommend_mk_filestats_py
    [mk_filestats_2.py]=recommend_mk_filestats_2_py
    [lnx_quota]=recommend_lnx_quota
    [smart]=recommend_smart
    [smart_posix]=recommend_smart_posix

    [apache_status.py]=recommend_apache_status_py
    [apache_status_2.py]=recommend_apache_status_2_py
    [nginx_status.py]=recommend_nginx_status_py
    [nginx_status_2.py]=recommend_nginx_status_2_py

    [netstat.linux]=recommend_netstat_linux
    [netstat.aix]=recommend_netstat_aix
    [netstat.solaris]=recommend_netstat_solaris
    [mk_iptables]=recommend_mk_iptables
    [dnsclient]=recommend_dnsclient
    [mtr.py]=recommend_mtr_py
    [mtr_2.py]=recommend_mtr_2_py
    [zorp]=recommend_zorp
    [lnx_container_host_if.linux]=recommend_lnx_container_host_if_linux

    [kaspersky_av]=recommend_kaspersky_av
    [symantec_av]=recommend_symantec_av
    [runas]=recommend_runas
    [jar_signature]=recommend_jar_signature

    [cmk - update - agent]=recommend_cmk_update_agent
    [cmkupdateagent.py]=recommend_cmkupdateagent_py
    [mk_logwatch.py]=recommend_mk_logwatch_py
    [mk_logwatch_2.py]=recommend_mk_logwatch_2_py
    [mk_tsm]=recommend_mk_tsm
    [mk_tinkerforge.py]=recommend_mk_tinkerforge_py
    [mk_tinkerforge_2.py]=recommend_mk_tinkerforge_2_py
    [mk_suseconnect]=recommend_mk_suseconnect
    [mk_zypper]=recommend_mk_zypper
    [mk_omreport]=recommend_mk_omreport
    [plesk_backups.py]=recommend_plesk_backups_py
    [plesk_backups_2.py]=recommend_plesk_backups_2_py
    [plesk_domains.py]=recommend_plesk_domains_py
    [plesk_domains_2.py]=recommend_plesk_domains_2_py
    [unitrends_backup]=recommend_unitrends_backup
    [unitrends_replication.py]=recommend_unitrends_replication_py
    [unitrends_replication_2.py]=recommend_unitrends_replication_2_py
    [robotmk_agent_plugin]=recommend_robotmk_agent_plugin

    [mk_docker.py]=recommend_mk_docker_py
    [mk_docker_2.py]=recommend_mk_docker_2_py
    [mk_inotify.py]=recommend_mk_inotify_py
    [mk_inotify_2.py]=recommend_mk_inotify_2_py
    [mk_inventory.linux]=recommend_mk_inventory_linux
    [mk_inventory.aix]=recommend_mk_inventory_aix
    [mk_inventory.solaris]=recommend_mk_inventory_solaris
    [mk_site_object_counts]=recommend_mk_site_object_counts
    [mk_filehandler]=recommend_mk_filehandler
    [mk_scaleio]=recommend_mk_scaleio
    [mk_nfsiostat]=recommend_mk_nfsiostat
    [nfsexports]=recommend_nfsexports
    [nfsexports.solaris]=recommend_nfsexports_solaris
    [mailman2_lists]=recommend_mailman2_lists
    [mailman3_lists]=recommend_mailman3_lists
    [isc_dhcpd.py]=recommend_isc_dhcpd_py
    [isc_dhcpd_2.py]=recommend_isc_dhcpd_2_py
    [nvidia_smi]=recommend_nvidia_smi
)

# Function: Determine installed plugins by listing files in plugin directory
# - Sets installed_plugins array with full relative paths
# - Sets installed_plugins_basenames array containing only file names (no paths)
get_installed_plugins() {
    mapfile -t installed_plugins < <(find "$PLUGIN_DIR" -type f -printf "%P\n" 2>/dev/null)
    installed_plugins_basenames=()
    for p in "${installed_plugins[@]}"; do
        installed_plugins_basenames+=("$(basename "$p")")
    done
}

# Function: Determine preselected plugins for configuration dialog
# - If no plugins installed, preselects important defaults ("lvm", "mk_apt", "mk_logins", "mk_sshd_config")
# - Otherwise preselects installed plugins to preserve current setup
get_preselected_plugins() {
    if [[ ${#installed_plugins_basenames[@]} -eq 0 ]]; then
        preselected_plugins=("lvm" "mk_apt" "mk_logins" "mk_sshd_config")
    else
        preselected_plugins=("${installed_plugins_basenames[@]}")
    fi
}

# Function: Build array strings suitable for whiptail menu from a given plugin group array
# - Takes a nameref to an array containing plugins in groups of three: name, description, default flag
# - Sets ON/OFF flag based on whether the plugin is in preselected_plugins list
# - Calls associated recommendation function if defined, can influence display
# - Truncates description to max length for readability
build_menu_array() {
    local -n arr=$1
    for ((i = 0; i < ${#arr[@]}; i += 3)); do
        local name="${arr[i]}"
        local desc="${arr[i + 1]}"
        local flag="OFF"
        # Mark as ON if in preselected plugins list
        if [[ " ${preselected_plugins[*]} " =~ " $name " ]]; then
            flag="ON"
        fi
        # Call recommendation check function if defined
        local check_func="${RECOMMENDATION_CHECKS[$name]}"
        local display_name="$name"
        if [[ -n "$check_func" ]] && $check_func; then
            display_name="${name}"
        fi
        desc=$(truncate_desc "$desc" "$max_desc_len")
        printf "%s\t%s\t%s\n" "$display_name" "$desc" "$flag"
    done
}

# Function: Build an array of recommended plugins according to environment checks
# - Iterates groups of plugins and filters plugins recommended by their check functions
# - Avoids duplicates using already_listed array
# - Sets ON/OFF flag according to preselection
build_recommended_array() {
    local flag
    local already_listed=()
    for group in DEFAULT_PLUGINS DB_PLUGINS STORAGE_PLUGINS WEBSERVER_PLUGINS NETWORK_PLUGINS SECURITY_PLUGINS MONITORING_PLUGINS MISC_PLUGINS; do
        local -n arr=$group
        for ((i = 0; i < ${#arr[@]}; i += 3)); do
            local name="${arr[i]}"
            local desc="${arr[i + 1]}"
            local check_func="${RECOMMENDATION_CHECKS[$name]}"
            if [[ -n "$check_func" ]] && $check_func; then
                if [[ " ${already_listed[*]} " =~ " $name " ]]; then continue; fi
                already_listed+=("$name")
                flag="OFF"
                if [[ " ${preselected_plugins[*]} " =~ " $name " ]]; then
                    flag="ON"
                fi
                desc=$(truncate_desc "$desc" "$max_desc_len")
                printf "%s\t%s\t%s\n" "$name" "$desc" "$flag"
            fi
        done
    done
}

# Function: Build the complete plugin menu array for whiptail selection dialog
# - Determines terminal size and adjusts widths and maximum description length
# - Builds the plugin list grouped by categories: Default, Recommended, Databases, Storage, Webserver, etc.
# - Avoids duplication by checking if plugins already included in default or recommended groups
build_plugin_menu_array() {
    # Get terminal size for adaptive UI
    width=$(tput cols)
    height=$(tput lines)
    whiptail_width=$((width - 10))
    if ((whiptail_width < 60)); then whiptail_width=60; fi
    max_desc_len=$((whiptail_width - 45))
    if ((max_desc_len < 10)); then max_desc_len=10; fi

    PLUGINS=()
    # Default plugins group header
    PLUGINS+=("======= Default" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        PLUGINS+=("$name" "$desc" "$flag")
        default_plugins+=("$name")
    done < <(build_menu_array DEFAULT_PLUGINS)
    is_in_default() {
        local n="$1"
        for r in "${default_plugins[@]}"; do
            [[ "$r" == "$n" ]] && return 0
        done
        return 1
    }

    # Recommended group header
    PLUGINS+=("======= Recommended" "" "off")
    recommended_plugins=()
    while IFS=$'\t' read -r name desc flag; do
        is_in_default "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
        recommended_plugins+=("$name")
    done < <(build_recommended_array)
    is_in_hidden() {
        local n="$1"
        for r in "${recommended_plugins[@]}" "${default_plugins[@]}"; do
            [[ "$r" == "$n" ]] && return 0
        done
        return 1
    }

    # Remaining categories follow similar logic, avoiding duplicates:
    # Databases
    PLUGINS+=("======= Databases" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array DB_PLUGINS)
    # Storage
    PLUGINS+=("======= Storage" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array STORAGE_PLUGINS)
    # Webserver
    PLUGINS+=("======= Webserver" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array WEBSERVER_PLUGINS)
    # Network
    PLUGINS+=("======= Network" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array NETWORK_PLUGINS)
    # Security
    PLUGINS+=("======= Security" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array SECURITY_PLUGINS)
    # Monitoring
    PLUGINS+=("======= Monitoring" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array MONITORING_PLUGINS)
    # Other
    PLUGINS+=("======= Other" "" "off")
    while IFS=$'\t' read -r name desc flag; do
        is_in_hidden "$name" && continue
        PLUGINS+=("$name" "$desc" "$flag")
    done < <(build_menu_array MISC_PLUGINS)
}

# Function: Execute installation and removal of plugins based on user selection
handle_plugin_installation_removal() {
    plugins_to_remove=()
    plugins_to_install=()
    unique_selected_plugins=($(make_unique "${SELECTED_PLUGINS[@]}"))

    # Determine plugins to remove: installed but not selected
    for p in "${installed_plugins_basenames[@]}"; do
        found=0
        for sel in "${unique_selected_plugins[@]}"; do
            if [[ "$sel" == "$p" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            plugins_to_remove+=("$p")
        fi
    done

    # Remove plugins that are no longer selected
    for p in "${plugins_to_remove[@]}"; do
        find "$PLUGIN_DIR" -type f -name "$p" -exec rm -f {} \;
        log "[INFO] plugin deleted: $p"
    done

    # Install new plugins selected by user
    for p in "${SELECTED_PLUGINS[@]}"; do
        # Skip category headers used in menu
        [[ "$p" == "======="* ]] && continue
        # Only install if not already installed
        if [[ ! " ${installed_plugins_basenames[*]} " =~ " $p " ]]; then
            plugins_to_install+=("$p")
        fi
        # Special handling to create subdirectory for mk_apt plugin
        if [[ "$p" == "mk_apt" ]]; then
            TARGET_DIR="${PLUGIN_DIR}/3600"
            mkdir -p "$TARGET_DIR"
        else
            TARGET_DIR="$PLUGIN_DIR"
        fi

        pluginurl="https://monitoring.admin-intelligence.de/checkmk/check_mk/agents/plugins/${p}"
        # Download the plugin file from configured SITE_PLUGIN_URL and set executable
        if curl -fsSL "${pluginurl}" -o "${TARGET_DIR}/${p}"; then
            chmod +x "${TARGET_DIR}/${p}"
            log "[INFO] plugin installed: $p"
        else
            show_error_box "Error downloading $p!"
        fi
    done
}

# Function: Restart the Checkmk agent socket service
# - Uses systemctl to restart check-mk-agent.socket if active
# - Otherwise shows warning and aborts script for manual intervention
restart_checkmk_agent() {
    if systemctl is-active --quiet check-mk-agent.socket; then
        systemctl restart check-mk-agent.socket
    else
        show_warning_box "Checkmk agent could not be restarted automatically. Please check manually."
        abort_script
    fi
}

# Main plugin management function
# - Retrieves installed plugins and preselected plugins
# - Builds the plugin selection menu
# - Shows the selection dialog to the user
# - Handles installation/removal based on selection
# - Shows installation summary and restarts agent
plugin_menu() {
    get_installed_plugins
    get_preselected_plugins
    build_plugin_menu_array
    show_plugin_selection_menu
    handle_plugin_installation_removal
    show_installation_summary
    restart_checkmk_agent
}

# Function: Configure Apache server-status plugin
# - Checks if apache2 or httpd is installed
# - Detects OS type (Debian/Ubuntu vs RHEL/CentOS) by config paths
# - Enables mod_status, configures /server-status URL with access only for localhost
# - Reloads Apache service and shows success message
configure_apache_server_status() {
    if ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1; then
        show_error_box "Apache web server is not installed!"
        log "[apache] Apache not detected, aborting configuration."
        return
    fi

    if [ -d "/etc/apache2" ]; then
        a2enmod status
        if ! grep -q "Location /server-status" /etc/apache2/sites-available/000-default.conf && ! grep -q "Location /server-status" /etc/apache2/conf-available/*.conf; then
            cat <<EOL >/etc/apache2/conf-available/server-status.conf
<IfModule mod_status.c>
    <Location /server-status>
        SetHandler server-status
        Require local
    </Location>
    ExtendedStatus On
</IfModule>
EOL
            a2enconf server-status
        fi
        systemctl reload apache2
        show_success_box "/server-status enabled for Apache."
        log "[apache] /server-status successfully enabled on Debian/Ubuntu."
    elif [ -d "/etc/httpd" ]; then
        if ! grep -q "Location /server-status" /etc/httpd/conf/httpd.conf && ! grep -q "Location /server-status" /etc/httpd/conf.d/*.conf; then
            cat <<EOL >>/etc/httpd/conf.d/server-status.conf
<Location /server-status>
    SetHandler server-status
    Require local
</Location>
ExtendedStatus On
EOL
        fi
        systemctl reload httpd
        show_success_box "/server-status enabled for Apache."
        log "[apache] /server-status successfully enabled on RHEL/CentOS."
    else
        show_error_box "Unknown Apache configuration directory."
        log "[apache] Could not determine Apache configuration directory."
    fi
}

# Function: Configure NGINX stub_status plugin
# - Checks if NGINX is installed and config directory exists
# - Checks if /nginx_status location is already configured to prevent duplicates
# - Writes nginx_status.conf with access only for localhost and stub_status enabled
# - Tests nginx config and reloads if valid, otherwise warns or errors
configure_nginx_status() {
    if ! command -v nginx >/dev/null 2>&1; then
        show_error_box "NGINX web server is not installed or not found!"
        log "[nginx] NGINX not detected, aborting configuration."
        return
    fi

    if [[ ! -d /etc/nginx/conf.d ]]; then
        show_error_box "/etc/nginx/conf.d directory does not exist. Cannot configure NGINX status."
        log "[nginx] Missing /etc/nginx/conf.d directory."
        return
    fi

    if grep -qr 'location /nginx_status' /etc/nginx/*; then
        show_info_box "NGINX /nginx_status location is already configured."
        log "[nginx] /nginx_status location already configured."
        return
    fi

    cat <<'EOF' > /etc/nginx/conf.d/nginx_status.conf
location /nginx_status {
    stub_status;              # enables status output
    access_log off;           # optionally disable logging
    allow 127.0.0.1;          # allow localhost only
    deny all;                 # deny all others
}
EOF

    log "[nginx] Created /etc/nginx/conf.d/nginx_status.conf file with stub_status location."

    if nginx -t >/dev/null 2>&1; then
        if systemctl reload nginx; then
            show_success_box "NGINX configuration test successful.\nNGINX reloaded successfully to apply changes."
            log "[nginx] nginx -t successful and nginx reloaded."
        else
            show_warning_box "NGINX configuration test successful, but failed to reload NGINX.\nPlease reload manually."
            log "[nginx] nginx -t successful but reload failed."
        fi
    else
        show_error_box "NGINX configuration test failed. Please check the nginx config manually."
        log "[nginx] nginx -t failed after adding stub_status config."
    fi
}

# Function: Prompt for custom user backup file pattern input
# - Validates input and appends to /etc/check_mk/fileinfo.cfg
backupfile_own() {
    log "[backupfile] Prompting for custom backup file pattern."
    PATTERN=$(whiptail --title "Custom Backup Files" --inputbox \
        "Please enter your file pattern:\n\nExamples:\n- /dir/file.ext (single file)\n- /dir/*.ext (wildcard)\n- /dir/*/* (multiple wildcards)" \
        15 70 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 || -z "$PATTERN" ]]; then
        log "[backupfile] No input for custom pattern. Aborted."
        show_error_box "No input provided. Operation aborted." 8 60
        return
    fi
    if [[ -f "/etc/check_mk/fileinfo.cfg" ]]; then
        echo "$PATTERN" >>/etc/check_mk/fileinfo.cfg
    else
        echo >/etc/check_mk/fileinfo.cfg
        echo "$PATTERN" >>/etc/check_mk/fileinfo.cfg
    fi
    log "[backupfile] Custom pattern \"$PATTERN\" added."
    show_success_box "Your file pattern \"$PATTERN\" was successfully added." 8 60
}

# Function: Write default backup file patterns to /etc/check_mk/fileinfo.cfg
# - Skips writing if patterns already present
backupfile_default() {
    local show_success="${1:-0}"
    if [[ -f "/etc/check_mk/fileinfo.cfg" ]]; then
        grep mysql /etc/check_mk/fileinfo.cfg >/dev/null
        if [[ $? == 0 ]]; then
            log "[backupfile] Default patterns already present, skipping."
            if [[ "$show_success" == "1" ]]; then
                show_success_box "Default file patterns are already present. Skipping." 8 60
            fi
            return
        fi
    fi
    echo >/etc/check_mk/fileinfo.cfg
    echo "/sicherung/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/mysql/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/mongodb/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/docker/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/etc/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/www/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/bookstack/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/home/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/opt/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/volumes/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/postgres/*" >>/etc/check_mk/fileinfo.cfg
    echo "/sicherung/databases/*" >>/etc/check_mk/fileinfo.cfg
    log "[backupfile] Default file patterns written."
    if [[ "$show_success" == "1" ]]; then
        show_success_box "All default file patterns were added." 8 60
    fi
}

# Function: Configure MySQL plugin
# - Verifies if MySQL client is installed
# - Checks for existing /etc/check_mk/mysql.cfg configuration file
# - If user agrees, prepares MySQL commands for user creation and permissions
# - Secures generated password, writes config file with credentials
configure_mysql_plugin() {
    # Check MySQL client availability
    if ! command -v mysql >/dev/null 2>&1; then
        show_info_box "MySQL not found. Skipping configuration." 10 60
        log "[mysql] MySQL not found. Skipping configuration."
        return
    fi

    # Check for existing configuration user 'checkmk'
    if [[ -s /etc/check_mk/mysql.cfg ]] && grep -q "user=checkmk" /etc/check_mk/mysql.cfg; then
        if whiptail --title "MySQL Plugin" --yesno "The configuration file /etc/check_mk/mysql.cfg already contains the user 'checkmk'.\n\nDo you want to reconfigure the MySQL user anyway?" 12 70; then
            log "[mysql] Reconfiguring user due to user confirmation."
        else
            show_info_box "Configuration skipped."
            log "[mysql] Skipping MySQL configuration per user's choice."
            return
        fi
    fi

    # Prepare MySQL root login command
    local MYSQL_CMD
    if mysql -u root -e "SHOW DATABASES;" >/dev/null 2>&1; then
        MYSQL_CMD="mysql -u root"
    else
        local MYSQLPASS
        MYSQLPASS=$(whiptail --title "MySQL root password" --inputbox "Please enter the MySQL root password:" 10 60 3>&1 1>&2 2>&3)
        if [[ -z "$MYSQLPASS" ]]; then
            show_error_box "No password provided, aborting."
            return
        fi
        MYSQL_CMD="mysql -u root -p$MYSQLPASS"
    fi

    # Check if MySQL user 'checkmk' exists
    user_exists=$($MYSQL_CMD -Bse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'checkmk' AND host = 'localhost');")

    if [[ "$user_exists" == "1" ]]; then
        if ! whiptail --title "MySQL Plugin" --yesno "The MySQL user 'checkmk' already exists.\n\nDo you want to recreate this user (drop and create anew)?" 12 70; then
            show_info_box "MySQL user will not be recreated."
            log "[mysql] User 'checkmk' exists, user creation aborted by user."
            return
        fi
    fi

    # Generate random password for 'checkmk' MySQL user
    SQL_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # SQL statements for user recreation and privilege grant
    SQL_DROP_USER="DROP USER IF EXISTS 'checkmk'@'localhost';"
    SQL_CREATE_USER="CREATE USER 'checkmk'@'localhost' IDENTIFIED BY '${SQL_PASS}!';"
    SQL_GRANT="GRANT SELECT, SHOW DATABASES ON *.* TO 'checkmk'@'localhost';"
    SQL_FLUSH="FLUSH PRIVILEGES;"

    # Execute SQL commands
    $MYSQL_CMD <<EOF
$SQL_DROP_USER
$SQL_CREATE_USER
$SQL_GRANT
$SQL_FLUSH
EOF

    # On success, save new credentials to configuration file with tight permissions
    if [[ $? -eq 0 ]]; then
        mkdir -p /etc/check_mk
        echo "[client]" >/etc/check_mk/mysql.cfg
        echo "user=checkmk" >>/etc/check_mk/mysql.cfg
        echo "password=${SQL_PASS}!" >>/etc/check_mk/mysql.cfg
        chmod 600 /etc/check_mk/mysql.cfg
        show_success_box "MySQL user 'checkmk' successfully created and configuration saved." 10 60
        log "[mysql] MySQL user 'checkmk' successfully created and configuration saved."
    else
        show_error_box "Error creating MySQL user. Please add the user manually."
        echo "Error creating MySQL user. Please add the user manually with the following SQL command:"
        echo "${MYSQL_CMD}"
        echo "${SQL_CREATE_USER} ${SQL_GRANT} ${SQL_FLUSH}"
        log "[mysql] Error creating MySQL user 'checkmk'."
    fi
}

############################################################
# === 6. Local checks management ===
############################################################

# Function: Install or update a local check script
# - Parameters:
#   $1 = local check script filename
#   $2 = URL from which to download the script
# - Creates local check directory if not existing
# - Downloads the script, cleans Windows line endings if present, sets executable bit
# - Logs success or shows error on failure
install_local_check_file() {
    local check="$1"
    local url="$2"
    local local_file="$LOCAL_CHECKS_DIR/$check"

    mkdir -p "$LOCAL_CHECKS_DIR"

    if curl -fsSL "$url" -o "$local_file"; then
        sed -i 's/\r$//' "$local_file"  # Remove Windows carriage returns if any
        chmod +x "$local_file"
        # show_success_box "Local check installed/updated: $check"
        log "[INFO] Local check installed/updated: $check"
    else
        show_error_box "Download of $check failed!"
        log "[ERROR] Download failed: $check"
    fi
}

# Function: Remove a local check script file if it exists
# - Parameter:
#   $1 = local check script filename
# - Removes the file and logs the removal
remove_local_check_file() {
    local check="$1"
    if [[ -f "$LOCAL_CHECKS_DIR/$check" ]]; then
        rm -f "$LOCAL_CHECKS_DIR/$check"
        # show_success_box "Local check removed: $check"
        log "[INFO] Local check removed: $check"
    fi
}

############################################################
# === 6.1 PVE backup configuration ===
############################################################

# Function: Install the PVE backup config cron script
# - Downloads the script to agent directory and makes it executable
# - Logs success or error accordingly
install_pve_backup_config_cron_script() {
    local cron_url="https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/refs/heads/main/local_checks/pve_backup_config/check_pve_backup_config_cron.sh"
    local cron_dest="/usr/lib/check_mk_agent/check_pve_backup_config_cron.sh"

    curl -fsSL "$cron_url" -o "$cron_dest"
    if [[ $? -ne 0 ]]; then
        show_error_box "Error downloading PVE backup config cron script."
        log "[ERROR] Failed to download cron script from $cron_url"
        return 1
    fi

    chmod +x "$cron_dest"
    log "[INFO] PVE backup config cron script installed at $cron_dest"
}

# Function: Setup cronjob for PVE backup config script to run every 10 minutes
# - Checks if job is already in root crontab, adds otherwise
# - Logs actions taken
setup_pve_backup_config_cronjob() {
    local cron_job="*/10 * * * * /usr/lib/check_mk_agent/check_pve_backup_config_cron.sh >/dev/null 2>&1"

    # Check if cron job is already installed for root
    if crontab -l -u root 2>/dev/null | grep -Fq "$cron_job"; then
        log "[INFO] PVE backup config cronjob already present in root crontab."
    else
        (crontab -l -u root 2>/dev/null; echo "$cron_job") | crontab -u root -
        log "[INFO] PVE backup config cronjob added to root crontab."
    fi
}

# Function: Retrieve VM list by executing 'qm list' command on remote PVE host via SSH
# - Uses SSH with batch mode, 5 second timeout, no strict host key checks
# - Returns output of 'qm list' command or empty string on failure
get_qm_list() {
    local host="$1"
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" qm list 2>/dev/null
}

# Function: Retrieve LXC list by executing 'pct list' command on remote PVE host via SSH
# - Uses SSH with batch mode, 5 second timeout, no strict host key checks
# - Returns output of 'pct list' command or empty string on failure
get_pct_list() {
    local host="$1"
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" pct list 2>/dev/null
}

# Function: Check if any Checkmk site is active
# - Requires 'omd' command
# - Lists all omd sites, checks if any site has status 'running'
# - Returns 0 (true) if a running site exists, 1 (false) otherwise
is_checkmk_active() {
    # Check if omd command exists
    if ! command -v omd >/dev/null 2>&1; then
        return 1
    fi

    # Get all OMD sites
    local sites
    sites=$(omd sites --bare 2>/dev/null)
    [ -z "$sites" ] && return 1

    # Check if any site is running
    for site in $sites; do
        if omd status "$site" 2>/dev/null | grep -q "running"; then
            return 0
        fi
    done

    return 1
}

############################################################
# === 7. Registration and agent management for cloud sites ===
############################################################

# Function: Register the Checkmk agent with a cloud site
# - Accepts optional hostname parameter or prompts user input
# - Displays a summary of installation details and confirms before proceeding
# - Checks for Java processes and warns user if any found
# - Installs the agent with progress
# - Prompts user to create and activate the host in Checkmk
# - Prompts user for certificate and Vaultwarden password during registration
# - Registers agent for updates and runs agent updater
# - Shows final success message and clears the screen
register_agent_cloud() {
    local hostname_param="$1"
    local hostname=""
    if [ -n "$hostname_param" ]; then
        hostname="$hostname_param"
    else
        hostname=$(whiptail --inputbox "Please enter the hostname\ne.g. push.admin-intelligence.de:" 10 60 "" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && abort_script
        if [ -z "$hostname" ]; then
            show_error_box "No hostname specified!"
            abort_script
        fi
    fi

    # Summary display for confirmation
    summary="Summary of the cloud installation:\n\nHostname: $hostname\nSite: $SITE_TEXT\n\nPlease check the information and confirm with OK to start the installation."
    log "[INFO] $summary"
    whiptail --title "Summary" --yes-button "OK" --no-button "Cancel" --yesno "$summary" 15 70
    [ $? -ne 0 ] && abort_script

    check_java_warning_for_checkmk
    install_agent_with_progress

    # Prompt to create and activate host in Checkmk site
    show_warning_box_large "Please create the host named \"$hostname\" in Checkmk in the correct site and save. Then activate the configuration. Press Enter when done."
    log "[INFO] Server \"$hostname\" has been created and activated in the Checkmk site."

    # Provide registration credentials prompt
    show_info_box "Please answer the certificate question with \"Y\" and enter the password for the \"agent_registration\" entry from Vaultwarden."
    log "[INFO] Registration credentials has been provided"

    # Register agent with Checkmk site
    cmk-agent-ctl register --server ${SITE_REGISTER} --site ${SITE_NAME} --hostname "$hostname" --user agent_registration
    if [[ $? -ne 0 ]]; then
        log "[ERROR] Error while registering: Error code $?"
    else
        log "[SUCCESS] Agent was successfully registered at the Checkmk site."
    fi

    # Register agent updater for automatic updates and run update
    cmk-update-agent register -s "$(echo ${SITE_URL} | sed -e 's|^https\?://||')" -i ${SITE_NAME} -H "$hostname" -p ${SITE_UPDATE_PROTOCOL} -U agent_updater -S ${SITE_UPDATEUSERPASS} -v
    if [[ $? -ne 0 ]]; then
        log "[ERROR] Error while registering for updates: Error code $?"
    else
        log "[SUCCESS] Agent was successfully registered for updates at the Checkmk site."
    fi
    cmk-update-agent -vf

    show_success_box "Agent registration completed.\nThank you for using the installation script.\nBest regards,\nSascha"
    clear
}

# Function: Warn user if Java process found on host
check_java_warning_for_checkmk() {
    if pgrep -x java &>/dev/null; then
        show_warning_box "Warning: A Java process is running on this host. Please make sure to check 'Java Process' in the host configuration in Checkmk."
    fi
}

############################################################
# === 8. Main functions and logic ===
############################################################

# Function: Automatically register cloud agent if both hostname and key parameters provided
check_and_install_cloud_if_params_set() {
    if [[ -n "$HOSTNAME_PARAM" && -n "$KEY" ]]; then
        register_agent_cloud "$HOSTNAME_PARAM"
        exit 0
    fi
}

# Main entry point of the script
# - Sets color scheme, checks for root user
# - Handles command line args (e.g. "raw" for raw install)
# - Decides whether to include cloud options based on KEY and user input
# - Loads available sites and configuration
# - Displays menu and dispatches actions based on user selection
main() {
    export NEWT_COLORS="$NEWT_COLORS_STANDARD"
    check_root

    # Raw mode shortcut to install Checkmk agent and exit
    if [ "${1,,}" == "raw" ]; then
        install_raw
        exit 0
    fi

    # Determine if to include cloud in menu options
    if [[ -z "$include_cloud" ]]; then
        if [[ -n "$KEY" ]]; then
            include_cloud=1
        elif ! declare -p include_cloud &>/dev/null; then
            # Not set yet: ask user if menu should exclude cloud
            if whiptail --title "Quick start option" --yesno "No predefined Cloud or Raw sites detected...\nShow menu without Cloud option?" 10 70; then
                include_cloud=0
            else
                include_cloud=1
            fi
        else
            # If sites exist, cloud menu included by default
            include_cloud=1
        fi
    fi

    local menu_order=()

    if [[ "$include_cloud" -eq 1 ]]; then
        # Menu with cloud as first entry
        menu_order=("${MENU_KEYS_CLOUD[@]}")
    else
        # Menu without cloud option
        menu_order=("${MENU_KEYS_DEFAULT[@]}")
    fi

    # Load sites and config
    select_site_and_load_config
    check_and_install_cloud_if_params_set

    # Show main menu with selected items
    show_start_box "${menu_order[@]}"

    if [[ $? -ne 0 || -z "$CHOICE" ]]; then
        end_script
    fi

    # Dispatch menu choice to specific function calls
    case "$CHOICE" in
    cloud)
        register_agent_cloud
        ;;
    raw)
        install_raw
        ;;
    plugins)
        plugin_menu
        # Offer plugin configuration dialogs if relevant plugins selected
        if [[ " ${SELECTED_PLUGINS[*]} " == *" mk_mysql "* ]]; then
            if whiptail --title "MySQL Plugin" --yesno "Would you like to configure the MySQL plugin now?" 10 60; then
                configure_mysql_plugin
            fi
        fi
        if [[ " ${SELECTED_PLUGINS[*]} " == *" apache_status.py "* ]]; then
            if whiptail --title "Apache Plugin" --yesno "Would you like to configure the Apache /server-status plugin now?" 10 70; then
                configure_apache_server_status
            fi
        fi
        if [[ " ${SELECTED_PLUGINS[*]} " == *" nginx_status.py "* ]]; then
            if whiptail --title "NGINX Plugin" --yesno "Would you like to configure the NGINX /nginx-status plugin now?" 10 70; then
                configure_nginx_status
            fi
        fi
        show_success_box "Plugin installation completed.\nThank you for using the installation script.\nBest regards,\nSascha"
        clear
        ;;
    plugin_config)
        show_plugin_box
        if [[ $? -ne 0 || "$PLUGINCHOICE" == "cancel" || -z "$PLUGINCHOICE" ]]; then
            main
        fi
        case "$PLUGINCHOICE" in
        mysql)
            configure_mysql_plugin
            ;;
        apache)
            configure_apache_server_status
            ;;
        nginx)
            configure_nginx_status
            ;;
        file)
            backupfile_check
            ;;
        *)
            main
            ;;
        esac
        ;;
    local_checks)
        install_local_checks_menu
        ;;
    local_checks_config)
        configure_local_checks_menu
        ;;
    cleanup)
        uninstall_and_cleanup
        ;;
    tools)
        additional_tools_menu
        case "$TOOLCHOICE" in
        *)
            main
            ;;
        esac
        ;;
    *)
        abort_script
        ;;
    esac
}

############################################################
# === Start the script ===
############################################################
main "$@"
