#!/bin/bash

#==============================================================================
# CHIM Environment Startup Script
#==============================================================================
# Description: Starts the DwemerDistro environment with all required services
# Author: DwemerDistro Team
# Version: 2.0
# Last Modified: $(date +%Y-%m-%d)
#==============================================================================

# Enable strict error handling
set -euo pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================

# Service check configuration
readonly CHECK_RETRIES=30
readonly CHECK_WAIT_TIME=2

# Service status tracking variables
declare -g L_MINIME=""
declare -g L_WHISPER=""
declare -g L_XTTSV2=""
declare -g L_MIMIC=""
declare -g L_MELOTTS=""

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Function: log_info
# Description: Logs an informational message with timestamp
# Parameters: $1 - Message to log
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

# Function: log_error
# Description: Logs an error message with timestamp
# Parameters: $1 - Error message to log
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Function: cleanup_temp_files
# Description: Removes temporary files older than 7 days to free up disk space
cleanup_temp_files() {
    log_info "Cleaning up temporary files older than 7 days..."
    
    # Remove files older than 7 days
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    
    # Remove empty directories older than 7 days
    find /tmp -type d -mtime +7 -empty -delete 2>/dev/null || true
    
    log_info "Temporary file cleanup completed"
}

# Function: check_port
# Description: Checks if a service is listening on the specified port
# Parameters: $1 - Port number to check
# Returns: 0 if port is active, 1 if not active after all retries
check_port() {
    local port=$1
    local attempt=1

    log_info "Checking if service is running on port $port..."
    
    while (( attempt <= CHECK_RETRIES )); do
        if netstat -lNnp | grep ":$port" &>/dev/null; then
            echo " ✓ Service started successfully on port $port"
            return 0
        else
            echo -ne "."
            if (( attempt < CHECK_RETRIES )); then
                sleep $CHECK_WAIT_TIME
            fi
        fi
        ((attempt++))
    done

    echo " ✗ Service failed to start on port $port after $CHECK_RETRIES attempts"
    return 1
}

# Function: start_core_services
# Description: Starts Apache web server and PostgreSQL database
start_core_services() {
    log_info "Starting core services (Apache/PHP/PostgreSQL)..."
    
    # Restart Apache web server
    if /etc/init.d/apache2 restart &>/dev/null; then
        log_info "Apache web server started successfully"
    else
        log_error "Failed to start Apache web server"
        return 1
    fi
    
    # Restart PostgreSQL database
    if /etc/init.d/postgresql restart &>/dev/null; then
        log_info "PostgreSQL database started successfully"
    else
        log_error "Failed to start PostgreSQL database"
        return 1
    fi
}

# Function: setup_apache_logging
# Description: Creates symbolic link for Apache error log if it doesn't exist
setup_apache_logging() {
    local log_dir="/var/www/html/HerikaServer/log"
    local error_log="$log_dir/apache_error.log"
    
    if [[ ! -e "$error_log" ]]; then
        log_info "Setting up Apache error log symbolic link..."
        mkdir -p "$log_dir"
        ln -sf /var/log/apache2/error.log "$error_log"
        log_info "Apache error log link created at $error_log"
    fi
}

# Function: start_service_if_available
# Description: Generic function to start a service if its start script exists
# Parameters: 
#   $1 - Service name (for logging)
#   $2 - Path to start script
#   $3 - Port to check
#   $4 - Variable name to set if service is not available
start_service_if_available() {
    local service_name="$1"
    local start_script="$2"
    local port="$3"
    local status_var="$4"
    
    if [[ -f "$start_script" ]]; then
        log_info "Starting $service_name service..."
        echo -ne "Starting $service_name "
        
        # Run the start script as the dwemer user
        if su dwemer -c "$start_script"; then
            check_port "$port"
        else
            log_error "Failed to execute start script for $service_name"
            return 1
        fi
    else
        log_info "Skipping $service_name (start script not found: $start_script)"
        # Set the status variable to indicate service is not available
        declare -g "$status_var=1"
    fi
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    # Display application logo
    /usr/local/bin/print_logo
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Start core infrastructure services
    start_core_services
    setup_apache_logging
    
    # Start AI/ML services
    log_info "Starting AI/ML services..."
    
    # Start Minime-T5/TXT2VEC service (Text vectorization)
    start_service_if_available \
        "Minime-T5/TXT2VEC" \
        "/home/dwemer/minime-t5/start.sh" \
        "8082" \
        "L_MINIME"
    
    # Start Mimic3 TTS service (Text-to-Speech)
    start_service_if_available \
        "Mimic3 TTS" \
        "/home/dwemer/mimic3/start.sh" \
        "59125" \
        "L_MIMIC"
    
    # Start MeloTTS service (Alternative Text-to-Speech)
    start_service_if_available \
        "MeloTTS" \
        "/home/dwemer/MeloTTS/start.sh" \
        "8084" \
        "L_MELOTTS"
    
    # Start LocalWhisper service (Speech-to-Text)
    if [[ -f "/home/dwemer/remote-faster-whisper/config.yaml" ]]; then
        log_info "Starting LocalWhisper Server (Speech-to-Text)..."
        echo -ne "Starting LocalWhisper Server "
        su dwemer -c "/home/dwemer/remote-faster-whisper/start.sh"
        check_port 9876
    else
        L_WHISPER=1
        log_info "Skipping LocalWhisper Server (config not found)"
    fi
    
    # Start CHIM XTTS service (Advanced Text-to-Speech)
    start_service_if_available \
        "CHIM XTTS" \
        "/home/dwemer/xtts-api-server/start.sh" \
        "8020" \
        "L_XTTSV2"
    
    # Display service information and launch web interface
    display_service_info
}

# Function: display_service_info
# Description: Shows running services and their endpoints, then launches the web interface
display_service_info() {
    local ipaddress
    ipaddress=$(/usr/local/bin/get_ip)
    
    log_info "All services started. Displaying service information..."
    
    cat << EOF
=======================================
📋 CHIM ENVIRONMENT STATUS
=======================================
Download AIAgent.ini under Server Actions!

🔧 AIAgent.ini Network Settings:
----------------------------
SERVER=$ipaddress
PORT=8081
PATH=/HerikaServer/comm.php
POLINT=1
----------------------------

🌐 DwemerDistro Local IP Address: $ipaddress
🔗 CHIM WebServer URL: http://$ipaddress:8081

🚀 Running Components:
EOF

    # Display available service endpoints
    if [[ -z "${L_MINIME:-}" ]]; then
        echo "   📊 Minime-T5/TXT2VEC API: http://$ipaddress:8082"
    fi

    if [[ -z "${L_WHISPER:-}" ]]; then
        echo "   🎤 LocalWhisper API: http://$ipaddress:9876"
    fi

    if [[ -z "${L_XTTSV2:-}" ]]; then
        echo "   🗣️  CHIM XTTS API: http://$ipaddress:8020"
    fi

    if [[ -z "${L_MIMIC:-}" ]]; then
        echo "   🎵 Mimic3 API: http://$ipaddress:59125"
    fi

    if [[ -z "${L_MELOTTS:-}" ]]; then
        echo "   🎶 MelotTTS API: http://$ipaddress:8084"
    fi
    
    echo "======================================="
    
    # Launch the web interface in the default browser
    log_info "Launching web interface in browser..."
    explorer.exe "http://$ipaddress:8081/HerikaServer/ui/index.php" &>/dev/null &
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
