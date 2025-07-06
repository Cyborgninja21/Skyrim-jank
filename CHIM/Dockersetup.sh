#!/usr/bin/env bash
# Source: https://dwemerdynamics.hostwiki.io/en/Linux-Guide
# Nexus Mods: https://www.nexusmods.com/skyrimspecialedition/mods/126330?tab=files
# ==========================================================
# Skyrim AI Framework Docker Setup Script (Refactored)
# ==========================================================
# This script automates the setup of a Docker environment for the Skyrim AI Framework.
# It performs the following critical tasks:
# 1. Validates environment and checks if running as root (required for Docker operations)
# 2. Imports the pre-built Docker image if it doesn't already exist
# 3. Sets up necessary directory structures with proper permissions for:
#    - PostgreSQL database storage
#    - Temporary file storage
#    - Dwemer user home directory
#    - Web server content directory
# 4. Creates and configures the Docker service with optional NVIDIA GPU support
# 5. Handles existing container cleanup and recreation if needed
# ==========================================================

# Bash strict mode: exit on error, undefined variables, and pipe failures
# -e: exit immediately if a command exits with a non-zero status
# -u: treat unset variables as an error when substituting
# -o pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status
set -euo pipefail

# --- Configurable variables ---
# These variables control the script behavior and can be overridden via environment variables

# Determine the Linux user to set up the environment for
# Priority: LINUX_USER env var > logname command > SUDO_USER env var
LINUX_USER="${LINUX_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

# Path to the startup environment script within the Docker build directory
# This script will be used to initialize the Docker container environment
start_env_path="${WSL_TAR_IMAGE_PATH:-/home/${LINUX_USER}/docker_build/start_env}"

# Path to the main Docker image TAR file containing the Skyrim AI Framework
# This is a pre-built image with all necessary components for the AI framework
WSL_TAR_IMAGE_PATH="${WSL_TAR_IMAGE_PATH:-/home/${LINUX_USER}/docker_build/DwemerAI4Skyrim3.tar}"

# PostgreSQL database user/group IDs for proper file ownership
# These must match the PostgreSQL installation inside the Docker image
POSTGRES_UID=107    # PostgreSQL daemon user ID
POSTGRES_GID=116    # PostgreSQL daemon group ID

# Dwemer user IDs - this is the main application user inside the container
# Used for running the Skyrim AI Framework components
DWEMER_UID=1000     # Standard user ID for the dwemer user
DWEMER_GID=1000     # Standard group ID for the dwemer user


# --- Utility functions ---

# Error logging function - outputs error messages to stderr with timestamp
# Usage: err "error message"
# Output: [ERROR] error message (to stderr)
err() { echo "[ERROR] $*" >&2; }

# Info logging function - outputs informational messages to stdout
# Usage: info "informational message" 
# Output: [INFO] informational message (to stdout)
info() { echo "[INFO] $*"; }

# Check if a required command/binary exists in the system PATH
# Exits the script with error code 1 if the command is not found
# Usage: require_cmd "docker"
require_cmd() {
    # command -v returns the path to the command if found, null if not found
    # >/dev/null 2>&1 suppresses all output (stdout and stderr)
    command -v "$1" >/dev/null 2>&1 || { 
        err "Required command '$1' not found. Aborting."; 
        exit 1; 
    }
}

# Extract specific directories/files from a TAR archive to a target directory
# Creates the target directory if it doesn't exist, then extracts specified content
# Usage: setup_dir_from_tar "/target/path" "/path/to/archive.tar" [tar extraction args...]
setup_dir_from_tar() {
    local target_dir="$1"; shift    # First arg: destination directory
    local tar_path="$1"; shift      # Second arg: path to TAR file
    local tar_args=("$@")           # Remaining args: additional tar options
    
    # Only proceed if target directory doesn't already exist
    if [[ ! -d "$target_dir" ]]; then
        info "Preparing $(basename "$target_dir")"
        mkdir -p "$target_dir"      # Create directory and any missing parent directories
        # Extract from TAR file to target directory with specified arguments
        # -x: extract, -v: verbose, -f: file, -C: change to directory
        tar -xvf "$tar_path" -C "$target_dir" "${tar_args[@]}"
    fi
}

# Create a directory with specific permissions if it doesn't exist
# Usage: setup_dir "/path/to/directory" "755"
setup_dir() {
    local target_dir="$1"; shift    # Directory path to create
    local mode="$1"; shift          # Permission mode (e.g., 755, 777)
    
    if [[ ! -d "$target_dir" ]]; then
        info "Preparing $(basename "$target_dir")"
        mkdir -p "$target_dir"      # Create directory and parents if needed
        chmod "$mode" "$target_dir" # Set the specified permissions
    fi
}

# Change ownership of a directory and all its contents recursively
# Usage: set_owner "/path/to/directory" "1000" "1000"
set_owner() {
    local target_dir="$1"; shift    # Directory to change ownership for
    local uid="$1"; shift           # User ID to set as owner
    local gid="$1"; shift           # Group ID to set as owner
    
    # Change ownership recursively (-R flag)
    # Format: uid:gid
    chown "$uid:$gid" -R "$target_dir"
}

# --- Main script execution begins here ---

# Validate that all required system commands are available before proceeding
# This prevents the script from failing partway through due to missing dependencies
info "Checking for required system commands..."
for cmd in docker tar grep; do
    require_cmd "$cmd"
done
info "All required commands found successfully"

# Verify script is running with root privileges
# Docker operations require root access for container management and file system modifications
if [[ $(id -u) -ne 0 ]]; then
    err "This script must be run as root to perform Docker operations"
    err "Please run: sudo $0"
    exit 1
fi
info "Root privileges confirmed"

# Display detected configuration and get user confirmation before proceeding
# This gives the user a chance to verify the setup parameters and abort if incorrect
info "=== CONFIGURATION SUMMARY ==="
info "Detected user: $LINUX_USER"
info "This script will set up Docker environment for user: $LINUX_USER"
info "Docker directories will be created in: /home/$LINUX_USER/docker_env/"
info "Docker build directory: /home/$LINUX_USER/docker_build/"
info "Docker image source: $WSL_TAR_IMAGE_PATH"
echo -n "Do you want to continue with user '$LINUX_USER'? (y/N): "
read -r response

# Exit gracefully if user chooses not to continue
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Setup cancelled by user"
    exit 0
fi
info "User confirmed setup parameters"

# Pre-setup: Ensure docker_build directory exists and is accessible
# This directory should contain the Docker image TAR file and other build assets
# Using $(whoami) instead of $LINUX_USER since we're running as root
DOCKER_BUILD_DIR="/home/$(whoami)/docker_build"
if [[ ! -d "$DOCKER_BUILD_DIR" ]]; then
    info "Creating required directory: $DOCKER_BUILD_DIR"
    mkdir -p "$DOCKER_BUILD_DIR"
    info "Created docker_build directory successfully"
else
    info "Docker build directory already exists: $DOCKER_BUILD_DIR"
fi

# Verify the Docker image TAR file exists before attempting to import it
if [[ ! -f "$WSL_TAR_IMAGE_PATH" ]]; then
    err "Docker image TAR file not found at: $WSL_TAR_IMAGE_PATH"
    err "Please ensure the DwemerAI4Skyrim3.tar file is present in the docker_build directory"
    exit 1
fi
info "Docker image TAR file verified: $WSL_TAR_IMAGE_PATH"

# ==========================================================
# Step 1: Docker Image Management
# ==========================================================
# Check if the Skyrim AI Docker image already exists in the local Docker registry
# If not found, import it from the TAR file to avoid unnecessary re-imports

info "Checking for existing Docker image 'skyrimai'..."

# List all Docker images and search for one with repository name 'skyrimai'
# --format '{{.Repository}}' outputs only the repository names for easier parsing
# grep -q performs a quiet search (no output, just exit code)
if ! sudo docker image list --format '{{.Repository}}' | grep -q '^skyrimai$'; then
    info "Docker image 'skyrimai' not found in local registry"
    info "Importing Docker image from TAR file: $WSL_TAR_IMAGE_PATH"
    info "This may take several minutes depending on image size..."
    
    # Import the Docker image from TAR file and tag it as 'skyrimai:latest'
    # This creates a new Docker image from the exported TAR archive
    docker image import "$WSL_TAR_IMAGE_PATH" skyrimai:latest
    
    info "Docker image import completed successfully"
else
    info "Docker image 'skyrimai' already exists in local registry - skipping import"
fi


# ==========================================================
# Step 2: Directory Structure Setup
# ==========================================================
# Create and configure all necessary directories for the Docker environment
# Each directory serves a specific purpose and requires proper permissions

info "Setting up Docker environment directory structure..."

# --- PostgreSQL Database Directory ---
# Extract PostgreSQL data directory from the TAR file and set proper ownership
# This contains the database files and must be owned by the postgres user
info "Configuring PostgreSQL data directory..."
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_postgres" "$WSL_TAR_IMAGE_PATH" ./var/lib/postgresql/15 --strip-components=4

# Set ownership to PostgreSQL daemon user (required for database operation)
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_postgres" "$POSTGRES_UID" "$POSTGRES_GID"

# Set restrictive permissions (750) for database security
# Owner: read/write/execute, Group: read/execute, Others: no access
chmod 750 -R "/home/${LINUX_USER}/docker_env/skyrimai_postgres"
info "PostgreSQL directory configured with proper permissions"

# --- Temporary Directory ---
# Create a temporary directory for container temporary files
# Permissions 777 allow all users to read/write (standard for temp directories)
info "Setting up temporary directory..."
setup_dir "/home/${LINUX_USER}/docker_env/skyrimai_tmp" 777
info "Temporary directory created with full access permissions"

# --- Dwemer User Home Directory ---
# Extract the dwemer user's home directory from the TAR file
# This contains user-specific configuration and application data
info "Setting up Dwemer user home directory..."
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome" "$WSL_TAR_IMAGE_PATH" ./home/dwemer/ --strip-components=3

# Set ownership to the dwemer user (the main application user)
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome" "$DWEMER_UID" "$DWEMER_GID"
info "Dwemer home directory configured"

# --- Web Server Directory ---
# Extract the web server content directory containing the Skyrim AI web interface
# This includes PHP files, HTML, CSS, JavaScript, and other web assets
info "Setting up web server content directory..."
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_www" "$WSL_TAR_IMAGE_PATH" ./var/www/html --strip-components=4

# Set ownership to dwemer user (web server runs as this user)
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_www" "$DWEMER_UID" "$DWEMER_GID"
info "Web server directory configured"

info "All directory structures have been set up successfully"















# ==========================================================
# Step 3: Docker Container Creation and Configuration
# ==========================================================
# Create the main Docker container with proper networking, volumes, and GPU support

info "=== DOCKER CONTAINER SETUP ==="
info "Creating docker service 'skyrimaiframework'"

# --- NVIDIA GPU Support Detection ---
# Check if NVIDIA Docker runtime is installed and available
# This is required for GPU acceleration of AI workloads
info "Detecting NVIDIA GPU support capabilities..."

if sudo docker system info | grep -i runtimes | grep -iq nvidia; then
    nvidia_runtime_installed="yes"
    info "✓ NVIDIA Docker runtime is installed and available"
else
    nvidia_runtime_installed="no"
    info "✗ NVIDIA Docker runtime not detected"
fi

# Check if NVIDIA GPU hardware is present and accessible
# nvidia-smi is the NVIDIA System Management Interface tool
if command -v nvidia-smi >/dev/null 2>&1; then
    # Extract GPU UUID for specific GPU targeting (more reliable than using 'all')
    nvidia_gpu_id=$(nvidia-smi -L 2>/dev/null | grep -oP "(?<=UUID: ).*(?=\))" || true)
    if [[ -n "$nvidia_gpu_id" ]]; then
        info "✓ NVIDIA GPU detected with UUID: $nvidia_gpu_id"
    else
        info "✗ NVIDIA GPU hardware not found or not accessible"
        nvidia_gpu_id=""
    fi
else
    info "✗ nvidia-smi command not available - no NVIDIA GPU support"
    nvidia_gpu_id=""
fi

# --- Existing Container Management ---
# Check if a container with the same name already exists
# Use Docker's filter feature for reliable container detection
info "Checking for existing 'skyrimaiframework' container..."

if sudo docker ps -a --filter name=^/skyrimaiframework$ --format '{{.Names}}' | grep -q '^skyrimaiframework$'; then
    info "⚠️  Found existing skyrimaiframework container"
    echo -n "Do you want to remove the existing container and recreate it? (y/N): "
    read -r remove_response
    
    if [[ "$remove_response" =~ ^[Yy]$ ]]; then
        info "Stopping existing container..."
        # Stop the container gracefully (allows for cleanup)
        sudo docker container stop skyrimaiframework 2>/dev/null || true
        
        info "Removing existing container..."
        # Remove the stopped container completely
        sudo docker container rm skyrimaiframework 2>/dev/null || true
        
        info "✓ Existing container removed successfully"
        info "Proceeding with new container creation..."
    else
        info "Setup cancelled. Existing container will remain unchanged."
        exit 0
    fi
else
    info "✓ No existing container found - proceeding with creation"
fi

# --- Docker Container Configuration ---
# Build the complete Docker run command with all necessary parameters
info "Configuring Docker container parameters..."

DOCKER_RUN_ARGS=(
    # Container identification and management
    --name=skyrimaiframework                    # Unique container name for easy reference
    
    # Network configuration
    --network=host                            # Network mode: bridge (default), host, none, or custom network name
    
    # Logging configuration to prevent log files from growing too large
    --log-driver=json-file                      # Use JSON file logging driver
    --log-opt max-size=10m                      # Limit individual log file size to 10MB
    --log-opt max-file=3                        # Keep maximum of 3 rotated log files
    
    # Network port mappings (Host:Container)
    # These ports expose various services running inside the container
    -p 8081:8081                                # Main web interface (HerikaServer UI)
    -p 8082:8082                                # Secondary web service
    -p 8083:8083                                # Additional web service
    -p 59125:59125                              # Skyrim mod communication port
    -p 9876:9876                                # AI service communication port
    -p 8020:8020                                # Additional service port
    -p 8007:8007                                # Additional service port
    
    # Volume mounts (Host:Container) - bind mount host directories into container
    # These provide persistent storage and data sharing between host and container
    -v "/home/${LINUX_USER}/docker_env/skyrimai_postgres:/var/lib/postgresql"     # PostgreSQL data persistence
    -v "/home/${LINUX_USER}/docker_env/skyrimai_tmp:/tmp"                         # Temporary file storage
    -v "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome:/home/dwemer"          # User home directory
    -v "/home/${LINUX_USER}/docker_env/skyrimai_www:/var/www/html"                # Web server content
    
    # Container restart policy
    --restart unless-stopped                    # Automatically restart container unless manually stopped
    
    # Docker image to use
    skyrimai:latest                            # The imported Skyrim AI image
    
    # Container startup command - runs when container starts
    # This command creates a new startup script and executes it
    sh -c "cat > /etc/start_env << 'SCRIPT_EOF'
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
# Last Modified: \$(date +%Y-%m-%d)
# ===================================================================

# Enable strict error handling
set -euo pipefail

# Configuration Constants
readonly SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\"
readonly LOG_DIR=\"/var/log\"
readonly TMP_CLEANUP_DAYS=7
readonly DEFAULT_RETRIES=30
readonly DEFAULT_WAIT_TIME=2

# Service Configuration
readonly APACHE_LOG_DIR=\"/var/www/html/HerikaServer/log\"
readonly APACHE_ERROR_LOG=\"\${APACHE_LOG_DIR}/apache_error.log\"
readonly DWEMER_HOME=\"/home/dwemer\"

# Service installation script paths
readonly MINIME_INSTALL_SCRIPT=\"\${DWEMER_HOME}/minime-t5/ddistro_install.sh\"
readonly MIMIC_INSTALL_SCRIPT=\"\${DWEMER_HOME}/mimic3/ddistro_install.sh\"
readonly MELOTTS_INSTALL_SCRIPT=\"\${DWEMER_HOME}/MeloTTS/ddistro_install.sh\"
readonly WHISPER_INSTALL_SCRIPT=\"\${DWEMER_HOME}/remote-faster-whisper/ddistro_install.sh\"
readonly XTTS_INSTALL_SCRIPT=\"\${DWEMER_HOME}/xtts-api-server/ddistro_install.sh\"

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global service status flags
declare -g L_MINIME=\"\"
declare -g L_MIMIC=\"\"
declare -g L_MELOTTS=\"\"
declare -g L_WHISPER=\"\"
declare -g L_XTTSV2=\"\"

#######################################
# Print colored log messages
# Arguments:
#   \$1 - Log level (INFO, WARN, ERROR, SUCCESS)
#   \$2 - Message
#######################################
log_message() {
    local level=\"\$1\"
    local message=\"\$2\"
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    
    case \"\$level\" in
        \"INFO\")  echo -e \"\${BLUE}[INFO]\${NC} \${timestamp} - \$message\" ;;
        \"WARN\")  echo -e \"\${YELLOW}[WARN]\${NC} \${timestamp} - \$message\" ;;
        \"ERROR\") echo -e \"\${RED}[ERROR]\${NC} \${timestamp} - \$message\" ;;
        \"SUCCESS\") echo -e \"\${GREEN}[SUCCESS]\${NC} \${timestamp} - \$message\" ;;
        *) echo \"[\$level] \${timestamp} - \$message\" ;;
    esac
}

#######################################
# Display the application logo/banner
#######################################
display_banner() {
    log_message \"INFO\" \"Displaying DwemerDistro banner\"
    if [[ -x \"/usr/local/bin/print_logo\" ]]; then
        /usr/local/bin/print_logo
    else
        log_message \"WARN\" \"Logo script not found at /usr/local/bin/print_logo\"
    fi
}

#######################################
# Update DwemerDistro from git repository
#######################################
update_dwemer_distro() {
    log_message \"INFO\" \"Running git operations and update script...\"

    log_message \"INFO\" \"Executing: cd /home/dwemer/dwemerdistro && git fetch origin\"
    su - dwemer -s /bin/bash -c \"export TERM=xterm; cd /home/dwemer/dwemerdistro && git fetch origin\"

    log_message \"INFO\" \"Executing: git reset --hard origin/main\"
    su - dwemer -s /bin/bash -c \"export TERM=xterm; cd /home/dwemer/dwemerdistro && git reset --hard origin/main\"

    log_message \"INFO\" \"Executing: chmod +x update.sh\"
    su - dwemer -s /bin/bash -c \"export TERM=xterm; cd /home/dwemer/dwemerdistro && chmod +x update.sh\"

    log_message \"INFO\" \"Executing: ./update.sh (as root)\"
    if cd /home/dwemer/dwemerdistro && ./update.sh; then
        log_message \"SUCCESS\" \"CHIM distro update complete\"
    else
        log_message \"ERROR\" \"Failed to update DwemerDistro\"
        return 1
    fi
}

#######################################
# Update GWS (Game World Server)
#######################################
update_gws() {
    log_message \"INFO\" \"Running GWS update script...\"
    
    if [[ -x \"/usr/local/bin/update_gws\" ]]; then
        log_message \"INFO\" \"Executing: /usr/local/bin/update_gws\"
        if su dwemer /usr/local/bin/update_gws; then
            log_message \"SUCCESS\" \"GWS update complete\"
        else
            log_message \"ERROR\" \"Failed to update GWS\"
            return 1
        fi
    else
        log_message \"WARN\" \"GWS update script not found or not executable: /usr/local/bin/update_gws\"
    fi
}

#######################################
# Clean temporary files older than specified days
# Arguments:
#   \$1 - Number of days (optional, defaults to TMP_CLEANUP_DAYS)
#######################################
cleanup_temp_files() {
    local cleanup_days=\"\${1:-\$TMP_CLEANUP_DAYS}\"
    
    log_message \"INFO\" \"Cleaning temporary files older than \${cleanup_days} days\"
    
    # Clean temporary files
    if find /tmp -type f -mtime +\${cleanup_days} -delete 2>/dev/null; then
        log_message \"SUCCESS\" \"Temporary files cleaned successfully\"
    else
        log_message \"WARN\" \"Some temporary files could not be cleaned\"
    fi
    
    # Clean empty temporary directories
    find /tmp/ -type d -mtime +\${cleanup_days} -exec rm -fr {} \; 2>/dev/null || true
}

#######################################
# Check if a service port is listening
# Arguments:
#   \$1 - Port number to check
#   \$2 - Service name (for logging)
#   \$3 - Retries (optional, defaults to DEFAULT_RETRIES)
#   \$4 - Wait time between retries (optional, defaults to DEFAULT_WAIT_TIME)
# Returns:
#   0 if port is listening, 1 otherwise
#######################################
check_port() {
    local port=\"\$1\"
    local service_name=\"\${2:-Service}\"
    local retries=\"\${3:-\$DEFAULT_RETRIES}\"
    local wait_time=\"\${4:-\$DEFAULT_WAIT_TIME}\"
    local attempt=1

    log_message \"INFO\" \"Checking if \${service_name} is listening on port \${port}\"

    while (( attempt <= retries )); do
        if netstat -lnp 2>/dev/null | grep \":\${port}\" &>/dev/null; then
            log_message \"SUCCESS\" \"\${service_name} started successfully on port \${port}\"
            return 0
        else
            echo -ne \".\"
            if (( attempt < retries )); then
                sleep \"\$wait_time\"
            fi
        fi
        ((attempt++))
    done

    log_message \"ERROR\" \"\${service_name} failed to start on port \${port} after \${retries} attempts\"
    return 1
}

#######################################
# Start core system services (Apache/PHP and PostgreSQL)
#######################################
start_core_services() {
    log_message \"INFO\" \"Starting core services (Apache/PHP/PostgreSQL)\"
    
    # Start Apache with error handling
    if /etc/init.d/apache2 restart &>/dev/null; then
        log_message \"SUCCESS\" \"Apache2 service started successfully\"
    else
        log_message \"ERROR\" \"Failed to start Apache2 service\"
        return 1
    fi
    
    # Start PostgreSQL with error handling
    if /etc/init.d/postgresql restart; then
        log_message \"SUCCESS\" \"PostgreSQL service started successfully\"
    else
        log_message \"ERROR\" \"Failed to start PostgreSQL service\"
        return 1
    fi
}

#######################################
# Setup Apache error log symbolic link
#######################################
setup_apache_logging() {
    log_message \"INFO\" \"Setting up Apache error log symlink\"
    
    # Create log directory if it doesn't exist
    if [[ ! -d \"\$APACHE_LOG_DIR\" ]]; then
        mkdir -p \"\$APACHE_LOG_DIR\"
        log_message \"INFO\" \"Created Apache log directory: \$APACHE_LOG_DIR\"
    fi
    
    # Create symbolic link for Apache error log if it doesn't exist
    if [[ ! -e \"\$APACHE_ERROR_LOG\" ]]; then
        if ln -sf /var/log/apache2/error.log \"\$APACHE_ERROR_LOG\"; then
            log_message \"SUCCESS\" \"Apache error log symlink created successfully\"
        else
            log_message \"ERROR\" \"Failed to create Apache error log symlink\"
            return 1
        fi
    else
        log_message \"INFO\" \"Apache error log symlink already exists\"
    fi
}

#######################################
# Install a service with user context
# Arguments:
#   \$1 - Service name
#   \$2 - Installation script path
#   \$3 - Installation directory (optional)
#   \$4 - Flag variable name
#######################################
install_ai_service() {
    local service_name=\"\$1\"
    local install_script=\"\$2\"
    local install_dir=\"\${3:-}\"
    local flag_var=\"\$4\"
    
    log_message \"INFO\" \"Installing \$service_name\"
    
    # Check if installation script exists
    if [[ -f \"\$install_script\" ]]; then
        # Change to installation directory if provided
        if [[ -n \"\$install_dir\" && -d \"\$install_dir\" ]]; then
            log_message \"INFO\" \"Changing to installation directory: \$install_dir\"
            cd \"\$install_dir\" || {
                log_message \"ERROR\" \"Failed to change to installation directory: \$install_dir\"
                declare -g \"\$flag_var=1\"
                return 1
            }
        fi
        
        log_message \"INFO\" \"Executing installation script for \$service_name\"
        
        # Execute installation script as dwemer user
        if su dwemer -c \"\$install_script\"; then
            log_message \"SUCCESS\" \"\$service_name installed successfully\"
        else
            log_message \"ERROR\" \"Failed to install \$service_name\"
            declare -g \"\$flag_var=1\"
            return 1
        fi
    else
        log_message \"WARN\" \"Installation script not found for \$service_name: \$install_script\"
        declare -g \"\$flag_var=1\"
        return 1
    fi
}

#######################################
# Start a service with user context
# Arguments:
#   \$1 - Service name
#   \$2 - Script path
#   \$3 - Port number
#   \$4 - Flag variable name
#######################################
start_ai_service() {
    local service_name=\"\$1\"
    local script_path=\"\$2\"
    local port=\"\$3\"
    local flag_var=\"\$4\"
    
    if [[ -f \"\$script_path\" ]]; then
        log_message \"INFO\" \"Starting \$service_name\"
        echo -ne \"Starting \$service_name \"
        
        if su dwemer -c \"\$script_path\"; then
            if check_port \"\$port\" \"\$service_name\"; then
                log_message \"SUCCESS\" \"\$service_name started successfully\"
            else
                log_message \"ERROR\" \"\$service_name failed to start (port check failed)\"
                declare -g \"\$flag_var=1\"
            fi
        else
            log_message \"ERROR\" \"Failed to execute \$service_name startup script\"
            declare -g \"\$flag_var=1\"
        fi
    else
        log_message \"WARN\" \"Skipping \$service_name (startup script not found: \$script_path)\"
        declare -g \"\$flag_var=1\"
    fi
}

#######################################
# Start all AI and supporting services
#######################################
start_ai_services() {
    log_message \"INFO\" \"Starting AI and supporting services\"
    
    # Start Minime-T5/TXT2VEC service (Text vectorization)
    start_ai_service \"Minime-T5/TXT2VEC service\" \\
                  \"\$DWEMER_HOME/minime-t5/start.sh\" \\
                  \"8082\" \\
                  \"L_MINIME\"
    
    # Start Mimic3 TTS (Text-to-Speech)
    start_ai_service \"Mimic3 TTS\" \\
                  \"\$DWEMER_HOME/mimic3/start.sh\" \\
                  \"59125\" \\
                  \"L_MIMIC\"
    
    # Start MeloTTS (Alternative Text-to-Speech)
    start_ai_service \"MeloTTS\" \\
                  \"\$DWEMER_HOME/MeloTTS/start.sh\" \\
                  \"8084\" \\
                  \"L_MELOTTS\"
    
    # Start LocalWhisper Server (Speech-to-Text)
    if [[ -f \"\$DWEMER_HOME/remote-faster-whisper/config.yaml\" ]]; then
        start_ai_service \"LocalWhisper Server\" \\
                      \"\$DWEMER_HOME/remote-faster-whisper/start.sh\" \\
                      \"9876\" \\
                      \"L_WHISPER\"
    else
        L_WHISPER=1
        log_message \"WARN\" \"Skipping LocalWhisper Server (config not found)\"
    fi
    
    # Start CHIM XTTS server (Advanced Text-to-Speech)
    start_ai_service \"CHIM XTTS server\" \\
                  \"\$DWEMER_HOME/xtts-api-server/start.sh\" \\
                  \"8020\" \\
                  \"L_XTTSV2\"
}

#######################################
# Get container IP address
# Returns:
#   IP address string
#######################################
get_container_ip() {
    local ip_script=\"/usr/local/bin/get_ip\"
    
    if [[ -x \"\$ip_script\" ]]; then
        local ip_address
        ip_address=\$(\"\$ip_script\")
        if [[ -n \"\$ip_address\" ]]; then
            echo \"\$ip_address\"
        else
            log_message \"ERROR\" \"Failed to get IP address from \$ip_script\"
            echo \"localhost\"
        fi
    else
        log_message \"WARN\" \"IP script not found, using localhost\"
        echo \"localhost\"
    fi
}

#######################################
# Display connection information and service status
#######################################
display_service_info() {
    local ipaddress
    ipaddress=\$(get_container_ip)
    
    log_message \"INFO\" \"Displaying service connection information\"
    
    cat << EOF
=======================================
Download AIAgent.ini under Server Actions!
AIAgent.ini Network Settings:
----------------------------
SERVER=\$ipaddress
PORT=8081
PATH=/HerikaServer/comm.php
POLINT=1
----------------------------
DwemerDistro Local IP Address: \$ipaddress
CHIM WebServer URL: http://\$ipaddress:8081

Running Components:
EOF

    # Display URLs for each running service
    [[ -z \"\$L_MINIME\" ]] && echo \"Minime-T5/TXT2VEC API: http://\$ipaddress:8082\"
    [[ -z \"\$L_WHISPER\" ]] && echo \"LocalWhisper API: http://\$ipaddress:9876\"
    [[ -z \"\$L_XTTSV2\" ]] && echo \"CHIM XTTS API: http://\$ipaddress:8020\"
    [[ -z \"\$L_MIMIC\" ]] && echo \"Mimic3 API: http://\$ipaddress:59125\"
    [[ -z \"\$L_MELOTTS\" ]] && echo \"MelotTTS API: http://\$ipaddress:8084\"
    
    echo \"=======================================\"
}

#######################################
# Start log monitoring (keeps container running)
#######################################
start_log_monitoring() {
    log_message \"INFO\" \"Starting log file monitoring to keep container running\"
    
    local log_files=(
        \"/var/log/apache2/error.log\"
        \"/var/log/apache2/access.log\"
    )
    
    # Check if log files exist before tailing
    local existing_logs=()
    for log_file in \"\${log_files[@]}\"; do
        if [[ -f \"\$log_file\" ]]; then
            existing_logs+=(\"\$log_file\")
        else
            log_message \"WARN\" \"Log file not found: \$log_file\"
        fi
    done
    
    if [[ \${#existing_logs[@]} -gt 0 ]]; then
        log_message \"INFO\" \"Monitoring log files: \${existing_logs[*]}\"
        tail -f \"\${existing_logs[@]}\"
    else
        log_message \"ERROR\" \"No log files found to monitor. Container will exit.\"
        return 1
    fi
}

#######################################
# Main execution function
#######################################
main() {
    log_message \"INFO\" \"Starting DwemerDistro service initialization\"
    
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
if [[ \"\${BASH_SOURCE[0]}\" == \"\${0}\" ]]; then
    main \"\$@\"
fi

# ===================================================================
# END OF DwemerDistro Service Startup Script
# ===================================================================
SCRIPT_EOF
chmod +x /etc/start_env && /etc/start_env"
)
# Note: The startup command does the following:
# 1. Creates a complete new start_env script with all required services and configuration
# 2. Makes the script executable and runs it
# 3. Replaces the explorer.exe launch with log file monitoring for better container operation





# --- Final Container Deployment ---
# Deploy the container with or without NVIDIA GPU support based on system capabilities

if [[ -n "$nvidia_gpu_id" && "$nvidia_runtime_installed" == "yes" ]]; then
    # Deploy with NVIDIA GPU acceleration
    info "🚀 Deploying Docker container WITH NVIDIA GPU support"
    info "   Using GPU: $nvidia_gpu_id"
    info "   This will enable AI workload acceleration for better performance"
    
    # Add NVIDIA-specific Docker runtime and GPU device specification
    # --runtime=nvidia: Use NVIDIA container runtime for GPU access
    # --gpus device="$nvidia_gpu_id": Specify exact GPU to use by UUID
    sudo docker run -d --runtime=nvidia --gpus device="$nvidia_gpu_id" "${DOCKER_RUN_ARGS[@]}"
    
    info "✓ Container deployed successfully with GPU acceleration"
else
    # Deploy without GPU support (CPU-only mode)
    info "🚀 Deploying Docker container WITHOUT NVIDIA GPU support"
    if [[ "$nvidia_runtime_installed" == "no" ]]; then
        info "   Reason: NVIDIA Docker runtime not installed"
    elif [[ -z "$nvidia_gpu_id" ]]; then
        info "   Reason: No NVIDIA GPU detected"
    fi
    info "   Container will run in CPU-only mode"
    
    # Deploy container with standard Docker runtime
    sudo docker run -d "${DOCKER_RUN_ARGS[@]}"
    
    info "✓ Container deployed successfully in CPU mode"
fi

# --- Post-Deployment Verification ---
info "=== DEPLOYMENT COMPLETE ==="
info "Container 'skyrimaiframework' has been created and started"
info ""
info "🌐 Access the Skyrim AI web interface at:"
info "   http://localhost:8081/HerikaServer/ui/index.php"
info ""
info "📊 Monitor container status with:"
info "   sudo docker ps"
info "   sudo docker logs skyrimaiframework"
info ""
info "🔧 Container management commands:"
info "   Start:   sudo docker start skyrimaiframework"
info "   Stop:    sudo docker stop skyrimaiframework"
info "   Restart: sudo docker restart skyrimaiframework"
info ""
info "📁 Persistent data locations:"
info "   PostgreSQL: /home/${LINUX_USER}/docker_env/skyrimai_postgres"
info "   Web files:  /home/${LINUX_USER}/docker_env/skyrimai_www"
info "   User data:  /home/${LINUX_USER}/docker_env/skyrimai_dwemerhome"
info "   Temp files: /home/${LINUX_USER}/docker_env/skyrimai_tmp"



# ==========================================================
# Optional: Advanced Logging Configuration
# ==========================================================
# The following section defines specific log file paths that could be monitored
# These are currently commented out but provide examples of important log locations
# within the Skyrim AI Framework for debugging and monitoring purposes

# # Discrete log file paths for advanced monitoring (currently disabled)
# # These logs provide detailed insight into different components of the system:
# LOG_FILES=(
#     # Apache web server logs
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/error.log"           # Web server errors
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/other_vhosts_access.log"  # Virtual host access logs
#     
#     # Skyrim AI Framework specific logs  
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/debugStream.log"         # Debug information stream
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/context_sent_to_llm.log" # Data sent to AI model
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_from_llm.log"     # AI model responses
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_to_plugin.log"    # Data sent to Skyrim plugin
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/minai.log"              # Minimal AI interaction log
# )
# 
# # To enable advanced log monitoring, uncomment the LOG_FILES array above
# # and implement log monitoring functionality as needed for your environment

info ""
info "🎯 Setup completed successfully!"
info "The Skyrim AI Framework Docker environment is now ready for use."
info "Check the container logs if you encounter any issues: sudo docker logs skyrimaiframework"

