#!/bin/bash
# ===================================================================
# DwemerDistro Service Startup Script
# ===================================================================
# This script initializes and starts all services required for the
# DwemerDistro AI Agent environment including web servers, AI services,
# and supporting components.
# 
# Author: DwemerDistro Team
# Version: 2.0
# Last Modified: $(date +%Y-%m-%d)
# ===================================================================

# Enable strict error handling
set -euo pipefail

# Configuration Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log"
readonly TMP_CLEANUP_DAYS=7
readonly DEFAULT_RETRIES=30
readonly DEFAULT_WAIT_TIME=2

# Service Configuration
readonly APACHE_LOG_DIR="/var/www/html/HerikaServer/log"
readonly APACHE_ERROR_LOG="${APACHE_LOG_DIR}/apache_error.log"
readonly DWEMER_HOME="/home/dwemer"

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global service status flags
declare -g L_MINIME=""
declare -g L_MIMIC=""
declare -g L_MELOTTS=""
declare -g L_WHISPER=""
declare -g L_XTTSV2=""

#######################################
# Print colored log messages
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, SUCCESS)
#   $2 - Message
#######################################
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" ;;
        *) echo "[$level] ${timestamp} - $message" ;;
    esac
}

#######################################
# Display the application logo/banner
#######################################
display_banner() {
    log_message "INFO" "Displaying DwemerDistro banner"
    if [[ -x "/usr/local/bin/print_logo" ]]; then
        /usr/local/bin/print_logo
    else
        log_message "WARN" "Logo script not found at /usr/local/bin/print_logo"
    fi
}

#######################################
# Update DwemerDistro from git repository
#######################################
update_dwemer_distro() {
    log_message "INFO" "Running git operations and update script..."
    
    if su dwemer -- bash -c "cd /home/dwemer/dwemerdistro && git fetch origin && git reset --hard origin/main && chmod +x update.sh && echo 'dwemer' | sudo -S ./update.sh"; then
        log_message "SUCCESS" "CHIM distro update complete"
    else
        log_message "ERROR" "Failed to update DwemerDistro"
        return 1
    fi
}

#######################################
# Update GWS (Game World Server)
#######################################
update_gws() {
    log_message "INFO" "Running GWS update script..."
    
    if [[ -x "/usr/local/bin/update_gws" ]]; then
        if su dwemer /usr/local/bin/update_gws; then
            log_message "SUCCESS" "GWS update complete"
        else
            log_message "ERROR" "Failed to update GWS"
            return 1
        fi
    else
        log_message "WARN" "GWS update script not found or not executable: /usr/local/bin/update_gws"
    fi
}

#######################################
# Clean temporary files older than specified days
# Arguments:
#   $1 - Number of days (optional, defaults to TMP_CLEANUP_DAYS)
#######################################
cleanup_temp_files() {
    local cleanup_days="${1:-$TMP_CLEANUP_DAYS}"
    
    log_message "INFO" "Cleaning temporary files older than ${cleanup_days} days"
    
    # Clean temporary files
    if find /tmp -type f -mtime +${cleanup_days} -delete 2>/dev/null; then
        log_message "SUCCESS" "Temporary files cleaned successfully"
    else
        log_message "WARN" "Some temporary files could not be cleaned"
    fi
    
    # Clean empty temporary directories
    find /tmp/ -type d -mtime +${cleanup_days} -exec rm -fr {} \; 2>/dev/null || true
}

#######################################
# Check if a service port is listening
# Arguments:
#   $1 - Port number to check
#   $2 - Service name (for logging)
#   $3 - Retries (optional, defaults to DEFAULT_RETRIES)
#   $4 - Wait time between retries (optional, defaults to DEFAULT_WAIT_TIME)
# Returns:
#   0 if port is listening, 1 otherwise
#######################################
check_port() {
    local port="$1"
    local service_name="${2:-Service}"
    local retries="${3:-$DEFAULT_RETRIES}"
    local wait_time="${4:-$DEFAULT_WAIT_TIME}"
    local attempt=1

    log_message "INFO" "Checking if ${service_name} is listening on port ${port}"

    while (( attempt <= retries )); do
        if netstat -lnp 2>/dev/null | grep ":${port}" &>/dev/null; then
            log_message "SUCCESS" "${service_name} started successfully on port ${port}"
            return 0
        else
            echo -ne "."
            if (( attempt < retries )); then
                sleep "$wait_time"
            fi
        fi
        ((attempt++))
    done

    log_message "ERROR" "${service_name} failed to start on port ${port} after ${retries} attempts"
    return 1
}

#######################################
# Start core system services (Apache/PHP and PostgreSQL)
#######################################
start_core_services() {
    log_message "INFO" "Starting core services (Apache/PHP/PostgreSQL)"
    
    # Start Apache with error handling
    if /etc/init.d/apache2 restart &>/dev/null; then
        log_message "SUCCESS" "Apache2 service started successfully"
    else
        log_message "ERROR" "Failed to start Apache2 service"
        return 1
    fi
    
    # Start PostgreSQL with error handling
    if /etc/init.d/postgresql restart; then
        log_message "SUCCESS" "PostgreSQL service started successfully"
    else
        log_message "ERROR" "Failed to start PostgreSQL service"
        return 1
    fi
}

#######################################
# Setup Apache error log symbolic link
#######################################
setup_apache_logging() {
    log_message "INFO" "Setting up Apache error log symlink"
    
    # Create log directory if it doesn't exist
    if [[ ! -d "$APACHE_LOG_DIR" ]]; then
        mkdir -p "$APACHE_LOG_DIR"
        log_message "INFO" "Created Apache log directory: $APACHE_LOG_DIR"
    fi
    
    # Create symbolic link for Apache error log if it doesn't exist
    if [[ ! -e "$APACHE_ERROR_LOG" ]]; then
        if ln -sf /var/log/apache2/error.log "$APACHE_ERROR_LOG"; then
            log_message "SUCCESS" "Apache error log symlink created successfully"
        else
            log_message "ERROR" "Failed to create Apache error log symlink"
            return 1
        fi
    else
        log_message "INFO" "Apache error log symlink already exists"
    fi
}

#######################################
# Start a service with user context
# Arguments:
#   $1 - Service name
#   $2 - Script path
#   $3 - Port number
#   $4 - Flag variable name
#######################################
start_service() {
    local service_name="$1"
    local script_path="$2"
    local port="$3"
    local flag_var="$4"
    
    if [[ -f "$script_path" ]]; then
        log_message "INFO" "Starting $service_name"
        echo -ne "Starting $service_name "
        
        if su dwemer -c "$script_path"; then
            if check_port "$port" "$service_name"; then
                log_message "SUCCESS" "$service_name started successfully"
            else
                log_message "ERROR" "$service_name failed to start (port check failed)"
                declare -g "$flag_var=1"
            fi
        else
            log_message "ERROR" "Failed to execute $service_name startup script"
            declare -g "$flag_var=1"
        fi
    else
        log_message "WARN" "Skipping $service_name (startup script not found: $script_path)"
        declare -g "$flag_var=1"
    fi
}

#######################################
# Start all AI and supporting services
#######################################
start_ai_services() {
    log_message "INFO" "Starting AI and supporting services"
    
    # Start Minime-T5/TXT2VEC service (Text vectorization)
    start_service "Minime-T5/TXT2VEC service" \
                  "$DWEMER_HOME/minime-t5/start.sh" \
                  "8082" \
                  "L_MINIME"
    
    # Start Mimic3 TTS (Text-to-Speech)
    start_service "Mimic3 TTS" \
                  "$DWEMER_HOME/mimic3/start.sh" \
                  "59125" \
                  "L_MIMIC"
    
    # Start MeloTTS (Alternative Text-to-Speech)
    start_service "MeloTTS" \
                  "$DWEMER_HOME/MeloTTS/start.sh" \
                  "8084" \
                  "L_MELOTTS"
    
    # Start LocalWhisper Server (Speech-to-Text)
    if [[ -f "$DWEMER_HOME/remote-faster-whisper/config.yaml" ]]; then
        start_service "LocalWhisper Server" \
                      "$DWEMER_HOME/remote-faster-whisper/start.sh" \
                      "9876" \
                      "L_WHISPER"
    else
        L_WHISPER=1
        log_message "WARN" "Skipping LocalWhisper Server (config not found)"
    fi
    
    # Start CHIM XTTS server (Advanced Text-to-Speech)
    start_service "CHIM XTTS server" \
                  "$DWEMER_HOME/xtts-api-server/start.sh" \
                  "8020" \
                  "L_XTTSV2"
}

#######################################
# Get container IP address
# Returns:
#   IP address string
#######################################
get_container_ip() {
    local ip_script="/usr/local/bin/get_ip"
    
    if [[ -x "$ip_script" ]]; then
        local ip_address
        ip_address=$("$ip_script")
        if [[ -n "$ip_address" ]]; then
            echo "$ip_address"
        else
            log_message "ERROR" "Failed to get IP address from $ip_script"
            echo "localhost"
        fi
    else
        log_message "WARN" "IP script not found, using localhost"
        echo "localhost"
    fi
}

#######################################
# Display connection information and service status
#######################################
display_service_info() {
    local ipaddress
    ipaddress=$(get_container_ip)
    
    log_message "INFO" "Displaying service connection information"
    
    cat << EOF
=======================================
Download AIAgent.ini under Server Actions!
AIAgent.ini Network Settings:
----------------------------
SERVER=$ipaddress
PORT=8081
PATH=/HerikaServer/comm.php
POLINT=1
----------------------------
DwemerDistro Local IP Address: $ipaddress
CHIM WebServer URL: http://$ipaddress:8081

Running Components:
EOF

    # Display URLs for each running service
    [[ -z "$L_MINIME" ]] && echo "Minime-T5/TXT2VEC API: http://$ipaddress:8082"
    [[ -z "$L_WHISPER" ]] && echo "LocalWhisper API: http://$ipaddress:9876"
    [[ -z "$L_XTTSV2" ]] && echo "CHIM XTTS API: http://$ipaddress:8020"
    [[ -z "$L_MIMIC" ]] && echo "Mimic3 API: http://$ipaddress:59125"
    [[ -z "$L_MELOTTS" ]] && echo "MelotTTS API: http://$ipaddress:8084"
    
    echo "======================================="
}

#######################################
# Start log monitoring (keeps container running)
#######################################
start_log_monitoring() {
    log_message "INFO" "Starting log file monitoring to keep container running"
    
    local log_files=(
        "/var/log/apache2/error.log"
        "/var/log/apache2/access.log"
    )
    
    # Check if log files exist before tailing
    local existing_logs=()
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            existing_logs+=("$log_file")
        else
            log_message "WARN" "Log file not found: $log_file"
        fi
    done
    
    if [[ ${#existing_logs[@]} -gt 0 ]]; then
        log_message "INFO" "Monitoring log files: ${existing_logs[*]}"
        tail -f "${existing_logs[@]}"
    else
        log_message "ERROR" "No log files found to monitor. Container will exit."
        return 1
    fi
}

#######################################
# Main execution function
#######################################
main() {
    log_message "INFO" "Starting DwemerDistro service initialization"
    
    # Display banner
    display_banner
    
    # Update DwemerDistro from git repository
    update_dwemer_distro
    
    # Update GWS (Game World Server)
    update_gws
    
    # Clean temporary files
    cleanup_temp_files
    
    # Start core services
    start_core_services
    
    # Setup Apache logging
    setup_apache_logging
    
    # Start AI services
    start_ai_services
    
    # Display service information
    display_service_info
    
    # Start log monitoring (this will run indefinitely)
    start_log_monitoring
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# ===================================================================
# END OF DwemerDistro Service Startup Script
# ===================================================================