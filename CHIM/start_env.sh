#!/bin/bash

# DwemerDistro Environment Startup Script
# This script initializes and starts all services required for the CHIM AI system
# including web servers, TTS engines, and AI model APIs

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly DWEMER_USER="dwemer"
readonly APACHE_PORT=8081
readonly MINIME_T5_PORT=8082
readonly MELOTTS_PORT=8084
readonly WHISPER_PORT=9876
readonly XTTS_PORT=8020
readonly MIMIC3_PORT=59125

# Service status flags (1 = disabled/not available)
L_MINIME=""
L_MIMIC=""
L_MELOTTS=""
L_WHISPER=""
L_XTTSV2=""

# ============================================================================
# UPDATE FUNCTIONS
# ============================================================================

# Update CHIM distro from git repository
update_chim_distro() {
    echo "[*] STEP 1: Updating CHIM distro..."
    echo ""
    echo "    - Running git operations and update script..."
    bash -c "cd /home/dwemer/dwemerdistro && git fetch origin && git reset --hard origin/main && chmod +x update.sh && echo 'dwemer' | sudo -S ./update.sh"
    echo "    + CHIM distro update complete"
}

# Update CHIM server
update_chim_server() {
    echo ""
    echo "[*] STEP 2: Updating CHIM server..."
    echo ""
    echo "    - Executing server update..."
    su -u dwemer -- /usr/local/bin/update_gws
    echo "    + Server update complete"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Display the DwemerDistro logo
print_startup_logo() {
    echo "Initializing DwemerDistro Environment..."
    /usr/local/bin/print_logo
}

# Clean up temporary files older than 7 days
cleanup_temp_files() {
    echo "Cleaning up temporary files..."
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    find /tmp -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
}

# Check if a service is running on the specified port
# Args: port_number
# Returns: 0 if service is running, 1 if not
check_port_status() {
    local port=$1
    local retries=30
    local wait_time=2
    local attempt=1

    echo -n "Checking port $port"
    
    while (( attempt <= retries )); do
        if netstat -lNnp | grep ":$port" &>/dev/null; then
            echo " ✓ Service started successfully"
            return 0
        else
            echo -n "."
            if (( attempt < retries )); then
                sleep $wait_time
            fi
        fi
        ((attempt++))
    done

    echo " ✗ Service failed to start"
    return 1
}

# Start a service as the dwemer user if its start script exists
# Args: service_name, start_script_path, port, status_flag_var
start_service_if_available() {
    local service_name="$1"
    local start_script="$2"
    local port="$3"
    local status_flag="$4"
    
    if [[ -f "$start_script" ]]; then
        echo "Starting $service_name..."
        su "$DWEMER_USER" -c "$start_script"
        check_port_status "$port"
    else
        echo "Skipping $service_name (service not installed or disabled)"
        eval "$status_flag=1"
    fi
}

# Get the local IP address for network configuration
get_local_ip() {
    /usr/local/bin/get_ip
}

# Display service URLs and configuration information
display_service_info() {
    local ip_address="$1"
    
    cat << EOF

=======================================
CHIM AI System Successfully Started
=======================================

Network Configuration for AIAgent.ini:
----------------------------
SERVER=$ip_address
PORT=$APACHE_PORT
PATH=/HerikaServer/comm.php
POLINT=1
----------------------------

DwemerDistro Local IP Address: $ip_address
CHIM WebServer URL: http://$ip_address:$APACHE_PORT

Available Services:
EOF

    # Display URLs for enabled services
    [[ -z "$L_MINIME" ]] && echo "  • Minime-T5 API: http://$ip_address:$MINIME_T5_PORT"
    [[ -z "$L_WHISPER" ]] && echo "  • LocalWhisper API: http://$ip_address:$WHISPER_PORT"
    [[ -z "$L_XTTSV2" ]] && echo "  • CHIM XTTS API: http://$ip_address:$XTTS_PORT"
    [[ -z "$L_MIMIC" ]] && echo "  • Mimic3 TTS API: http://$ip_address:$MIMIC3_PORT"
    [[ -z "$L_MELOTTS" ]] && echo "  • MeloTTS API: http://$ip_address:$MELOTTS_PORT"
    
    echo ""
    echo "Note: Download AIAgent.ini under Server Actions in the web interface!"
}

# Graceful shutdown of all services
shutdown_services() {
    echo ""
    echo "Shutting down DwemerDistro services..."
    
    # Kill all processes running as dwemer user
    killall -15 -u "$DWEMER_USER" 2>/dev/null || true
    
    # Stop system services
    /etc/init.d/apache2 stop
    /etc/init.d/postgresql stop
    
    echo "All services stopped successfully."
    echo "You can now close this window or use Tools/Force Stop Distro.bat for complete shutdown."
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_startup_logo
    
    # Update system components before starting services
    update_chim_distro
    update_chim_server
    
    cleanup_temp_files
    
    # Start core system services
    echo "Starting core system services..."
    echo "  • Apache/PHP web server"
    /etc/init.d/apache2 restart &>/dev/null
    echo "  • PostgreSQL database"
    /etc/init.d/postgresql restart
    
    # Start AI and TTS services
    echo ""
    echo "Starting AI and TTS services..."
    
    start_service_if_available \
        "Minime-T5 Language Model" \
        "/home/$DWEMER_USER/minime-t5/start.sh" \
        "$MINIME_T5_PORT" \
        "L_MINIME"
    
    start_service_if_available \
        "Mimic3 Text-to-Speech" \
        "/home/$DWEMER_USER/mimic3/start.sh" \
        "$MIMIC3_PORT" \
        "L_MIMIC"
    
    start_service_if_available \
        "MeloTTS Text-to-Speech" \
        "/home/$DWEMER_USER/MeloTTS/start.sh" \
        "$MELOTTS_PORT" \
        "L_MELOTTS"
    
    # LocalWhisper has a different check (config file instead of start script)
    if [[ -f "/home/$DWEMER_USER/remote-faster-whisper/config.yaml" ]]; then
        echo "Starting LocalWhisper Speech-to-Text..."
        su "$DWEMER_USER" -c "/home/$DWEMER_USER/remote-faster-whisper/start.sh"
        check_port_status "$WHISPER_PORT"
    else
        echo "Skipping LocalWhisper Speech-to-Text (service not installed or disabled)"
        L_WHISPER=1
    fi
    
    start_service_if_available \
        "CHIM XTTS Text-to-Speech" \
        "/home/$DWEMER_USER/xtts-api-server/start.sh" \
        "$XTTS_PORT" \
        "L_XTTSV2"
    
    # Get IP address and display service information
    local ip_address
    ip_address=$(get_local_ip)
    
    display_service_info "$ip_address"
    
    # Open web interface in default browser (Windows integration)
    echo "Opening web interface in browser..."
    explorer.exe "http://$ip_address:$APACHE_PORT/HerikaServer/ui/index.php" &>/dev/null &
    
    # Wait for user input to shutdown
    echo ""
    echo "Press Enter to shutdown DwemerDistro..."
    read -r
    
    shutdown_services
    
    # Keep container alive (for Docker environments)
    tail -f /dev/null
}

# Execute main function
main "$@"