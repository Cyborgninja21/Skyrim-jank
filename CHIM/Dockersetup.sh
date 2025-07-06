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
#
# IMPROVEMENTS IN THIS VERSION:
# - Dynamic, configurable directory paths (no more hardcoded docker_build/docker_env)
# - Support for arbitrary deployment locations (system-wide paths like /opt, /var, etc.)
# - Customizable container and image names
# - Command-line help and usage information
# - Environment variable configuration support
# - Better path validation and error handling
# - Proper permission handling for different filesystem locations
# - Support for multiple deployment scenarios (development, production, etc.)
#
# COMMON DEPLOYMENT LOCATIONS:
# - Development: /home/user/skyrim-ai-docker (default)
# - Production: /opt/skyrim-ai or /srv/skyrim-ai
# - Data partition: /data/skyrim-ai or /var/lib/skyrim-ai
# - Custom enterprise: /apps/skyrim-framework or /usr/local/skyrim-ai
# ==========================================================

# Bash strict mode: exit on error, undefined variables, and pipe failures
# -e: exit immediately if a command exits with a non-zero status
# -u: treat unset variables as an error when substituting
# -o pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status
set -euo pipefail

# --- Configurable variables ---
# These variables control the script behavior and can be overridden via environment variables
# All paths must be absolute and the script will validate them before proceeding

# Determine the Linux user to set up the environment for
# Priority order: LINUX_USER env var > logname command > SUDO_USER env var
# This user will own the created directories and files (when not running as root)
LINUX_USER="${LINUX_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

# Base directory for all Docker-related files and data
# This is the root directory that will contain both build and runtime data
# Can be set to system-wide locations like /opt, /var, or any custom path
# Examples: /opt/skyrim-ai, /srv/skyrim-framework, /data/applications/skyrim
# Default falls back to user's home directory if not specified
#DOCKER_BASE_DIR="${DOCKER_BASE_DIR:-/home/${LINUX_USER}/skyrim-ai-docker}"
DOCKER_BASE_DIR="${DOCKER_BASE_DIR:-/models/skyrim-ai/skyrim-ai-docker}"

# Docker build directory containing TAR files and build assets
# This directory holds the Docker image TAR file and any build-time resources
# Subdirectory under the base directory for organization, but can be overridden to any path
DOCKER_BUILD_DIR="${DOCKER_BUILD_DIR:-${DOCKER_BASE_DIR}/build}"

# Docker environment directory for persistent data volumes
# This directory contains all the runtime data that persists between container restarts
# Includes database files, web content, user home directories, and temporary files
# Subdirectory under the base directory for organization, but can be overridden to any path
DOCKER_ENV_DIR="${DOCKER_ENV_DIR:-${DOCKER_BASE_DIR}/data}"

# Path to the startup environment script within the Docker build directory
# This script will be used to initialize the Docker container environment
# Currently not used in the refactored version but kept for potential future use
start_env_path="${start_env_path:-${DOCKER_BUILD_DIR}/start_env}"

# Path to the main Docker image TAR file containing the Skyrim AI Framework
# This is a pre-built image with all necessary components for the AI framework
# The TAR file should be exported from a working Docker image using 'docker save'
WSL_TAR_IMAGE_PATH="${WSL_TAR_IMAGE_PATH:-${DOCKER_BUILD_DIR}/DwemerAI4Skyrim3.tar}"

# Container name for the Skyrim AI framework
# Must follow Docker naming conventions: start with alphanumeric, contain only [a-zA-Z0-9_.-]
# Can be customized for multiple deployments or naming conventions (dev, prod, test, etc.)
CONTAINER_NAME="${CONTAINER_NAME:-skyrimaiframework}"

# Docker image name and tag
# Image name must be lowercase and follow Docker registry naming rules
# Tag allows versioning and different builds (latest, dev, v1.0, etc.)
DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-skyrimai}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"

# PostgreSQL database user/group IDs for proper file ownership
# These must match the PostgreSQL installation inside the Docker image
# PostgreSQL requires specific ownership for security and proper database operation
# These IDs are typically standard across most Linux distributions
POSTGRES_UID=107    # PostgreSQL daemon user ID (postgres user inside container)
POSTGRES_GID=116    # PostgreSQL daemon group ID (postgres group inside container)

# Dwemer user IDs - this is the main application user inside the container
# Used for running the Skyrim AI Framework components and web services
# Standard user/group ID 1000 is typically the first non-system user
# All application files and processes will run under this user for security
DWEMER_UID=1000     # Standard user ID for the dwemer user
DWEMER_GID=1000     # Standard group ID for the dwemer user


# --- Utility functions ---
# These functions provide common operations used throughout the script
# They handle logging, command validation, directory setup, and file extraction

# Error logging function - outputs error messages to stderr with timestamp
# Usage: err "error message"
# Output: [ERROR] error message (to stderr)
# Sends output to stderr so it can be separated from normal output
err() { echo "[ERROR] $*" >&2; }

# Info logging function - outputs informational messages to stdout
# Usage: info "informational message" 
# Output: [INFO] informational message (to stdout)
# Provides consistent formatting for status messages throughout the script
info() { echo "[INFO] $*"; }

# Check if a required command/binary exists in the system PATH
# Exits the script with error code 1 if the command is not found
# Usage: require_cmd "docker"
# This ensures all dependencies are available before attempting to use them
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
# This function is used to extract pre-configured data from the Docker image TAR file
setup_dir_from_tar() {
    local target_dir="$1"; shift    # First arg: destination directory
    local tar_path="$1"; shift      # Second arg: path to TAR file
    local tar_args=("$@")           # Remaining args: additional tar options (e.g., --strip-components)
    
    # Only proceed if target directory doesn't already exist
    # This prevents overwriting existing configurations and data
    if [[ ! -d "$target_dir" ]]; then
        info "Preparing $(basename "$target_dir")"
        mkdir -p "$target_dir"      # Create directory and any missing parent directories
        # Extract from TAR file to target directory with specified arguments
        # -x: extract, -v: verbose (show files being extracted), -f: file, -C: change to directory
        tar -xvf "$tar_path" -C "$target_dir" "${tar_args[@]}"
    fi
}

# Create a directory with specific permissions if it doesn't exist
# Usage: setup_dir "/path/to/directory" "755"
# Used for creating directories that don't need content from TAR files
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
# Essential for proper permissions when running services as non-root users
set_owner() {
    local target_dir="$1"; shift    # Directory to change ownership for
    local uid="$1"; shift           # User ID to set as owner
    local gid="$1"; shift           # Group ID to set as owner
    
    # Change ownership recursively (-R flag)
    # Format: uid:gid - uses numeric IDs for consistency across systems
    chown "$uid:$gid" -R "$target_dir"
}

# Set up proper ownership and permissions for directories
# This is especially important when using system-wide locations outside user home directories
# Ensures directories are accessible to the correct users and have appropriate security settings
setup_directory_permissions() {
    local target_dir="$1"    # Directory to configure
    local owner_user="$2"    # User to own the directory (can be empty for root)
    local mode="$3"          # Permission mode to set (can be empty to skip)
    
    # Create directory if it doesn't exist
    if [[ ! -d "$target_dir" ]]; then
        info "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    # Set ownership to the specified user if provided and not root
    # This is important for security - services should not run as root
    if [[ -n "$owner_user" && "$owner_user" != "root" ]]; then
        # Check if user exists before changing ownership
        # Prevents errors if the user doesn't exist on the system
        if id "$owner_user" &>/dev/null; then
            info "Setting ownership of $target_dir to user: $owner_user"
            chown "$owner_user:$owner_user" "$target_dir"
        else
            info "User $owner_user not found, keeping root ownership for: $target_dir"
        fi
    fi
    
    # Set permissions if specified
    # Different directories may need different permission levels
    if [[ -n "$mode" ]]; then
        info "Setting permissions of $target_dir to: $mode"
        chmod "$mode" "$target_dir"
    fi
}

# --- Usage and help functions ---
# These functions provide user-friendly help and argument parsing

# Display usage information and available environment variables
# Shows comprehensive help including all configuration options and examples
show_usage() {
    cat << EOF
==========================================================
Skyrim AI Framework Docker Setup Script
==========================================================

USAGE:
    sudo $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message and exit

ENVIRONMENT VARIABLES:
    You can customize the setup by setting these environment variables:

    LINUX_USER          Target Linux user (default: current user)
    DOCKER_BASE_DIR     Base directory for all Docker files 
                        Can be ANY absolute path on the filesystem
                        Examples: /opt/skyrim-ai, /var/lib/skyrim-docker, 
                                 /srv/applications/skyrim, /custom/path
                        (default: /home/\$LINUX_USER/skyrim-ai-docker)
    DOCKER_BUILD_DIR    Directory containing build files and TAR images
                        (default: \$DOCKER_BASE_DIR/build)
    DOCKER_ENV_DIR      Directory for persistent container data
                        (default: \$DOCKER_BASE_DIR/data)
    WSL_TAR_IMAGE_PATH  Path to the Docker image TAR file
                        (default: \$DOCKER_BUILD_DIR/DwemerAI4Skyrim3.tar)
    CONTAINER_NAME      Name for the Docker container
                        (default: skyrimaiframework)
    DOCKER_IMAGE_NAME   Name for the Docker image
                        (default: skyrimai)
    DOCKER_IMAGE_TAG    Tag for the Docker image
                        (default: latest)

EXAMPLES:
    # Use default paths (user's home directory)
    sudo $0

    # Deploy to system-wide location
    sudo DOCKER_BASE_DIR=/opt/skyrim-ai $0

    # Deploy to custom application directory
    sudo DOCKER_BASE_DIR=/srv/applications/skyrim-framework $0

    # Deploy to data partition
    sudo DOCKER_BASE_DIR=/data/docker/skyrim $0

    # Use custom container name with system location
    sudo CONTAINER_NAME=skyrim-prod DOCKER_BASE_DIR=/opt/skyrim-ai $0

    # Completely separate build and data directories
    sudo DOCKER_BUILD_DIR=/opt/builds/skyrim DOCKER_ENV_DIR=/var/lib/skyrim-data $0

NOTES:
    - This script must be run with root privileges (sudo)
    - The Docker image TAR file must exist at WSL_TAR_IMAGE_PATH
    - All directories will be created automatically if they don't exist
    - When using system-wide paths, ensure you have write permissions
    - For production deployments, consider using paths like:
      * /opt/skyrim-ai (standard for optional software)
      * /srv/skyrim-ai (for service data)
      * /var/lib/skyrim-ai (for application state data)
    - The script will set appropriate ownership and permissions automatically
==========================================================
EOF
}

# Parse command line arguments
# Currently only supports help option, but can be extended for other flags
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                err "Use -h or --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
}

# --- Configuration validation ---
# These functions ensure all configuration is valid before proceeding with setup

# Validate configuration and directory structure
# Performs comprehensive validation of all paths, names, and permissions
# Exits with error if any validation fails to prevent partial setup
validate_configuration() {
    # Ensure base directory is absolute path
    # Relative paths would be unpredictable when running with sudo
    if [[ ! "$DOCKER_BASE_DIR" =~ ^/ ]]; then
        err "DOCKER_BASE_DIR must be an absolute path, got: $DOCKER_BASE_DIR"
        exit 1
    fi
    
    # Ensure build and env directories are absolute paths
    # These can be independent of the base directory for advanced configurations
    if [[ ! "$DOCKER_BUILD_DIR" =~ ^/ ]]; then
        err "DOCKER_BUILD_DIR must be an absolute path, got: $DOCKER_BUILD_DIR"
        exit 1
    fi
    
    if [[ ! "$DOCKER_ENV_DIR" =~ ^/ ]]; then
        err "DOCKER_ENV_DIR must be an absolute path, got: $DOCKER_ENV_DIR"
        exit 1
    fi
    
    # Check if TAR image path is absolute
    # Critical since this file contains the entire Docker image
    if [[ ! "$WSL_TAR_IMAGE_PATH" =~ ^/ ]]; then
        err "WSL_TAR_IMAGE_PATH must be an absolute path, got: $WSL_TAR_IMAGE_PATH"
        exit 1
    fi
    
    # Validate container name (Docker naming rules)
    # Docker has strict naming requirements for containers
    if [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        err "Invalid container name: $CONTAINER_NAME"
        err "Container names must start with alphanumeric character and contain only [a-zA-Z0-9_.-]"
        exit 1
    fi
    
    # Validate image name (Docker registry naming rules)
    # Image names must follow Docker registry format (lowercase, specific characters)
    if [[ ! "$DOCKER_IMAGE_NAME" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
        err "Invalid Docker image name: $DOCKER_IMAGE_NAME"
        err "Image names must be lowercase and contain only [a-z0-9._-]"
        exit 1
    fi
    
    # Validate that we can create/access the base directory
    # Test actual filesystem permissions rather than just checking if directory exists
    # This prevents failures later during actual directory creation
    if [[ ! -d "$DOCKER_BASE_DIR" ]]; then
        # Try to create the directory to test permissions
        if ! mkdir -p "$DOCKER_BASE_DIR" 2>/dev/null; then
            err "Cannot create base directory: $DOCKER_BASE_DIR"
            err "Check permissions and ensure the parent directory exists"
            exit 1
        fi
        info "Successfully validated ability to create base directory: $DOCKER_BASE_DIR"
    else
        # Directory exists, check if it's writable
        if [[ ! -w "$DOCKER_BASE_DIR" ]]; then
            err "Base directory exists but is not writable: $DOCKER_BASE_DIR"
            err "Run script with appropriate permissions (sudo) or choose a different location"
            exit 1
        fi
        info "Base directory exists and is writable: $DOCKER_BASE_DIR"
    fi
    
    info "Configuration validation passed"
}

# --- Display current configuration ---
# Shows the user exactly what configuration will be used

# Display current configuration for debugging/verification
# This helps users understand exactly what settings are being used
# Especially useful when troubleshooting or when environment variables are set
show_configuration() {
    info "=== CURRENT CONFIGURATION ==="
    info "LINUX_USER: $LINUX_USER"
    info "DOCKER_BASE_DIR: $DOCKER_BASE_DIR"
    info "DOCKER_BUILD_DIR: $DOCKER_BUILD_DIR"
    info "DOCKER_ENV_DIR: $DOCKER_ENV_DIR"
    info "WSL_TAR_IMAGE_PATH: $WSL_TAR_IMAGE_PATH"
    info "CONTAINER_NAME: $CONTAINER_NAME"
    info "DOCKER_IMAGE_NAME: $DOCKER_IMAGE_NAME"
    info "DOCKER_IMAGE_TAG: $DOCKER_IMAGE_TAG"
    info "==============================="
    echo
}

# --- Main script execution begins here ---
# Entry point for the script - handles validation, setup, and deployment

# Parse command line arguments first
# Process any command-line options before doing any setup work
parse_arguments "$@"

# Validate configuration and directory structure
# Ensure all settings are valid before proceeding with any changes
validate_configuration

# Validate that all required system commands are available before proceeding
# This prevents the script from failing partway through due to missing dependencies
# Better to fail early with clear error messages than to fail during critical operations
info "Checking for required system commands..."
for cmd in docker tar grep; do
    require_cmd "$cmd"
done
info "All required commands found successfully"

# Verify script is running with root privileges
# Docker operations require root access for:
# - Container management (create, start, stop)
# - File system modifications (creating directories, setting permissions)
# - Network configuration (port binding)
# - Volume mounting (bind mounts require root)
if [[ $(id -u) -ne 0 ]]; then
    err "This script must be run as root to perform Docker operations"
    err "Please run: sudo $0"
    exit 1
fi
info "Root privileges confirmed"

# Show current configuration
# Display all settings so user can verify before proceeding
show_configuration

# Display detected configuration and get user confirmation before proceeding
# This gives the user a final chance to verify the setup parameters and abort if incorrect
# Important safety measure to prevent accidental deployment to wrong locations
info "=== CONFIGURATION SUMMARY ==="
info "Detected user: $LINUX_USER"
info "This script will set up Docker environment for user: $LINUX_USER"
info "Docker base directory: $DOCKER_BASE_DIR"
info "Docker build directory: $DOCKER_BUILD_DIR"
info "Docker data directory: $DOCKER_ENV_DIR"
info "Docker image source: $WSL_TAR_IMAGE_PATH"
info "Container name: $CONTAINER_NAME"
echo -n "Do you want to continue with user '$LINUX_USER'? (y/N): "
read -r response

# Exit gracefully if user chooses not to continue
# Default is 'N' (no) for safety - user must explicitly confirm
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Setup cancelled by user"
    exit 0
fi
info "User confirmed setup parameters"

# Validate configuration before proceeding
# Run validation again to catch any issues that might have been introduced
validate_configuration

# Pre-setup: Ensure all required directories exist and are accessible
# These directories can be located anywhere on the filesystem based on configuration
# Create the directory structure that will hold both build assets and runtime data
info "Setting up directory structure..."

# Ensure base directory exists with proper permissions
# This is the root directory that will contain all Skyrim AI Docker files
setup_directory_permissions "$DOCKER_BASE_DIR" "$LINUX_USER" "755"

# Ensure build directory exists
# This directory will contain the Docker image TAR file and any build-time assets
if [[ ! -d "$DOCKER_BUILD_DIR" ]]; then
    info "Creating required directory: $DOCKER_BUILD_DIR"
    mkdir -p "$DOCKER_BUILD_DIR"
    setup_directory_permissions "$DOCKER_BUILD_DIR" "$LINUX_USER" "755"
    info "Created docker build directory successfully"
else
    info "Docker build directory already exists: $DOCKER_BUILD_DIR"
fi

# Ensure data directory exists  
# This directory will contain all persistent data that survives container restarts
if [[ ! -d "$DOCKER_ENV_DIR" ]]; then
    info "Creating required directory: $DOCKER_ENV_DIR"
    mkdir -p "$DOCKER_ENV_DIR"
    setup_directory_permissions "$DOCKER_ENV_DIR" "$LINUX_USER" "755"
    info "Created docker data directory successfully"
else
    info "Docker data directory already exists: $DOCKER_ENV_DIR"
fi

# Verify the Docker image TAR file exists before attempting to import it
# This file contains the complete Skyrim AI Framework Docker image
# Without it, the setup cannot proceed
if [[ ! -f "$WSL_TAR_IMAGE_PATH" ]]; then
    err "Docker image TAR file not found at: $WSL_TAR_IMAGE_PATH"
    err "Please ensure the DwemerAI4Skyrim3.tar file is present in the build directory:"
    err "  Expected location: $DOCKER_BUILD_DIR/"
    err "  You can place the TAR file there, or set WSL_TAR_IMAGE_PATH to point to its location"
    err ""
    err "The TAR file should be created from a working Docker image using:"
    err "  docker save skyrimai:latest > DwemerAI4Skyrim3.tar"
    exit 1
fi
info "Docker image TAR file verified: $WSL_TAR_IMAGE_PATH"

# ==========================================================
# Step 1: Docker Image Management
# ==========================================================
# Import the pre-built Skyrim AI Docker image from TAR file
# This step ensures the required Docker image is available in the local registry
# The image contains all the necessary software and configurations for the AI framework

info "Checking for existing Docker image '${DOCKER_IMAGE_NAME}'..."

# List all Docker images and search for one with repository name matching our image
# --format '{{.Repository}}' outputs only the repository names for easier parsing
# grep -q performs a quiet search (no output, just exit code)
# This prevents unnecessary re-imports of the same image
if ! sudo docker image list --format '{{.Repository}}' | grep -q "^${DOCKER_IMAGE_NAME}$"; then
    info "Docker image '${DOCKER_IMAGE_NAME}' not found in local registry"
    info "Importing Docker image from TAR file: $WSL_TAR_IMAGE_PATH"
    info "This may take several minutes depending on image size..."
    
    # Import the Docker image from TAR file and tag it appropriately
    # docker image import creates a new image from a tarball's content
    # Different from 'docker load' - import creates a new image, load restores a saved image
    docker image import "$WSL_TAR_IMAGE_PATH" "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
    
    info "Docker image import completed successfully"
else
    info "Docker image '${DOCKER_IMAGE_NAME}' already exists in local registry - skipping import"
fi


# ==========================================================
# Step 2: Directory Structure Setup
# ==========================================================
# Create and configure all necessary directories for the Docker environment
# Each directory serves a specific purpose and requires proper permissions
# These directories will be mounted as volumes in the Docker container

info "Setting up Docker environment directory structure..."

# --- PostgreSQL Database Directory ---
# Extract PostgreSQL data directory from the TAR file and set proper ownership
# This contains the database files and must be owned by the postgres user
# PostgreSQL is very strict about file ownership for security reasons
info "Configuring PostgreSQL data directory..."
setup_dir_from_tar "${DOCKER_ENV_DIR}/skyrimai_postgres" "$WSL_TAR_IMAGE_PATH" ./var/lib/postgresql/15 --strip-components=4

# Set ownership to PostgreSQL daemon user (required for database operation)
# PostgreSQL will refuse to start if the data directory has incorrect ownership
set_owner "${DOCKER_ENV_DIR}/skyrimai_postgres" "$POSTGRES_UID" "$POSTGRES_GID"

# Set restrictive permissions (750) for database security
# Owner: read/write/execute, Group: read/execute, Others: no access
# This prevents unauthorized access to database files
chmod 750 -R "${DOCKER_ENV_DIR}/skyrimai_postgres"
info "PostgreSQL directory configured with proper permissions"

# --- Temporary Directory ---
# Create a temporary directory for container temporary files
# Permissions 777 allow all users to read/write (standard for temp directories)
# This directory is mounted as /tmp inside the container
info "Setting up temporary directory..."
setup_dir "${DOCKER_ENV_DIR}/skyrimai_tmp" 777
info "Temporary directory created with full access permissions"

# --- Dwemer User Home Directory ---
# Extract the dwemer user's home directory from the TAR file
# This contains user-specific configuration and application data
# Includes AI model configurations, user settings, and application state
info "Setting up Dwemer user home directory..."
setup_dir_from_tar "${DOCKER_ENV_DIR}/skyrimai_dwemerhome" "$WSL_TAR_IMAGE_PATH" ./home/dwemer/ --strip-components=3

# Set ownership to the dwemer user (the main application user)
# All AI services and applications run as this user for security
set_owner "${DOCKER_ENV_DIR}/skyrimai_dwemerhome" "$DWEMER_UID" "$DWEMER_GID"
info "Dwemer home directory configured"

# --- Web Server Directory ---
# Extract the web server content directory containing the Skyrim AI web interface
# This includes PHP files, HTML, CSS, JavaScript, and other web assets
# Contains the HerikaServer web interface for managing the AI framework
info "Setting up web server content directory..."
setup_dir_from_tar "${DOCKER_ENV_DIR}/skyrimai_www" "$WSL_TAR_IMAGE_PATH" ./var/www/html --strip-components=4

# Set ownership to dwemer user (web server runs as this user)
# Apache/PHP processes run as dwemer user for security
set_owner "${DOCKER_ENV_DIR}/skyrimai_www" "$DWEMER_UID" "$DWEMER_GID"
info "Web server directory configured"

info "All directory structures have been set up successfully"















# ==========================================================
# Step 3: Docker Container Creation and Configuration
# ==========================================================
# Create the main Docker container with proper networking, volumes, and GPU support
# This step configures and deploys the container that will run the Skyrim AI Framework

info "=== DOCKER CONTAINER SETUP ==="
info "Creating docker service '${CONTAINER_NAME}'"

# --- NVIDIA GPU Support Detection ---
# Check if NVIDIA Docker runtime is installed and available
# GPU acceleration significantly improves AI inference performance
# This is optional - the system will work in CPU mode if GPU is not available
info "Detecting NVIDIA GPU support capabilities..."

# Check if NVIDIA Docker runtime is installed
# The NVIDIA Container Toolkit provides GPU access to Docker containers
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
    # UUID provides exact GPU identification for multi-GPU systems
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
# Docker container names must be unique, so we need to handle conflicts
info "Checking for existing '${CONTAINER_NAME}' container..."

# Use Docker's filter feature for reliable container detection
# Checks both running and stopped containers
if sudo docker ps -a --filter name=^/${CONTAINER_NAME}$ --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "⚠️  Found existing ${CONTAINER_NAME} container"
    echo -n "Do you want to remove the existing container and recreate it? (y/N): "
    read -r remove_response
    
    if [[ "$remove_response" =~ ^[Yy]$ ]]; then
        info "Stopping existing container..."
        # Stop the container gracefully (allows for cleanup)
        # || true prevents script from failing if container is already stopped
        sudo docker container stop "${CONTAINER_NAME}" 2>/dev/null || true
        
        info "Removing existing container..."
        # Remove the stopped container completely (but preserve volumes)
        sudo docker container rm "${CONTAINER_NAME}" 2>/dev/null || true
        
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
# This creates a comprehensive container configuration for the Skyrim AI Framework
info "Configuring Docker container parameters..."

DOCKER_RUN_ARGS=(
    # Container identification and management
    --name="${CONTAINER_NAME}"                  # Unique container name for easy reference and management
    
    # Network configuration
    --network=host                              # Use host networking for direct access to services
                                               # Alternative: bridge mode with explicit port mappings
    
    # Logging configuration to prevent log files from growing too large
    --log-driver=json-file                     # Use JSON file logging driver (Docker default)
    --log-opt max-size=10m                     # Limit individual log file size to 10MB
    --log-opt max-file=3                       # Keep maximum of 3 rotated log files (30MB total)
    
    # Network port mappings (Host:Container)
    # These ports expose various services running inside the container
    # Each service has a specific purpose in the Skyrim AI ecosystem
    -p 8081:8081                               # Main web interface (HerikaServer UI) - primary access point
    -p 8082:8082                               # Minime-T5/TXT2VEC API (text vectorization service)
    -p 8083:8083                               # Additional web service (future expansion)
    -p 59125:59125                             # Mimic3 TTS API (text-to-speech service)
    -p 9876:9876                               # LocalWhisper API (speech-to-text service)
    -p 8020:8020                               # CHIM XTTS API (advanced text-to-speech)
    -p 8007:8007                               # Additional service port (future use)
    
    # Volume mounts (Host:Container) - bind mount host directories into container
    # These provide persistent storage and data sharing between host and container
    # Critical for maintaining data across container restarts and updates
    -v "${DOCKER_ENV_DIR}/skyrimai_postgres:/var/lib/postgresql"     # PostgreSQL data persistence (database files)
    -v "${DOCKER_ENV_DIR}/skyrimai_tmp:/tmp"                         # Temporary file storage (cache, temp processing)
    -v "${DOCKER_ENV_DIR}/skyrimai_dwemerhome:/home/dwemer"          # User home directory (configs, AI models, user data)
    -v "${DOCKER_ENV_DIR}/skyrimai_www:/var/www/html"                # Web server content (PHP files, web interface)
    
    # Container restart policy
    --restart unless-stopped                   # Automatically restart container unless manually stopped
                                              # Ensures service availability after system reboots
    
    # Docker image to use
    "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" # The imported Skyrim AI image with specified tag
    
    # Container startup command - runs when container starts
    # This command creates a comprehensive startup script inside the container and executes it
    # The script handles all service initialization, updates, and monitoring
    sh -c "cat > /etc/start_env << 'SCRIPT_EOF'
#!/bin/bash
# ===================================================================
# DwemerDistro Service Startup Script
# ===================================================================
# This script initializes and starts all services required for the
# DwemerDistro AI Agent environment including web servers, AI services,
# and supporting components.
# 
# This script is dynamically generated by the Docker setup script and
# embedded into the container at /etc/start_env
# 
# Services managed by this script:
# - Apache2 web server (hosts the HerikaServer web interface)
# - PostgreSQL database (stores AI conversation data and configurations)
# - Minime-T5/TXT2VEC service (text vectorization for AI processing)
# - Mimic3 TTS (text-to-speech synthesis)
# - MeloTTS (alternative text-to-speech)
# - LocalWhisper Server (speech-to-text recognition)
# - CHIM XTTS server (advanced text-to-speech with voice cloning)
# 
# Author: DwemerDistro Team
# Version: 2.0
# Last Modified: \$(date +%Y-%m-%d)
# ===================================================================

# Enable strict error handling for reliable service startup
set -euo pipefail

# Configuration Constants
readonly SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\"
readonly LOG_DIR=\"/var/log\"
readonly TMP_CLEANUP_DAYS=7        # Days before cleaning temporary files
readonly DEFAULT_RETRIES=30        # Default number of retries for service startup
readonly DEFAULT_WAIT_TIME=30       # Seconds to wait between startup attempts

# Service Configuration
readonly APACHE_LOG_DIR=\"/var/www/html/HerikaServer/log\"
readonly APACHE_ERROR_LOG=\"\${APACHE_LOG_DIR}/apache_error.log\"
readonly DWEMER_HOME=\"/home/dwemer\"

# Service installation script paths - these scripts install AI services if not present
readonly MINIME_INSTALL_SCRIPT=\"\${DWEMER_HOME}/minime-t5/ddistro_install.sh\"
readonly MIMIC_INSTALL_SCRIPT=\"\${DWEMER_HOME}/mimic3/ddistro_install.sh\"
readonly MELOTTS_INSTALL_SCRIPT=\"\${DWEMER_HOME}/MeloTTS/ddistro_install.sh\"
readonly WHISPER_INSTALL_SCRIPT=\"\${DWEMER_HOME}/remote-faster-whisper/ddistro_install.sh\"
readonly XTTS_INSTALL_SCRIPT=\"\${DWEMER_HOME}/xtts-api-server/ddistro_install.sh\"

# Color codes for output formatting (improves readability)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global service status flags - track which services started successfully
# Empty string means success, non-empty (1) means failure
declare -g L_MINIME=\"\"      # Minime-T5/TXT2VEC service status
declare -g L_MIMIC=\"\"       # Mimic3 TTS service status
declare -g L_MELOTTS=\"\"     # MeloTTS service status
declare -g L_WHISPER=\"\"     # LocalWhisper service status
declare -g L_XTTSV2=\"\"      # CHIM XTTS service status

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
        if su dwemer -s /bin/bash -c \"export TERM=xterm; /usr/local/bin/update_gws\"; then
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
        if su dwemer -s /bin/bash -c \"export TERM=xterm; \$install_script\"; then
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
        
        if su dwemer -s /bin/bash -c \"export TERM=xterm; \$script_path\"; then
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
    
    # Display comprehensive connection information for Skyrim AI Framework
    # This information helps users configure their Skyrim installation to connect to the AI services
    # The AIAgent.ini file is required by the Skyrim plugin to communicate with the server
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

    # Display URLs for each successfully running service
    # Only show services that started without errors (empty flag variables)
    # This provides users with a clear list of accessible AI services
    [[ -z \"\$L_MINIME\" ]] && echo \"Minime-T5/TXT2VEC API: http://\$ipaddress:8082\"    # Text vectorization service
    [[ -z \"\$L_WHISPER\" ]] && echo \"LocalWhisper API: http://\$ipaddress:9876\"        # Speech-to-text recognition
    [[ -z \"\$L_XTTSV2\" ]] && echo \"CHIM XTTS API: http://\$ipaddress:8020\"           # Advanced text-to-speech with voice cloning
    [[ -z \"\$L_MIMIC\" ]] && echo \"Mimic3 API: http://\$ipaddress:59125\"              # Standard text-to-speech synthesis
    [[ -z \"\$L_MELOTTS\" ]] && echo \"MelotTTS API: http://\$ipaddress:8084\"           # Alternative text-to-speech engine
    
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
# This function orchestrates the complete startup sequence for the DwemerDistro environment
# It runs in a specific order to ensure all dependencies are met:
# 1. Display banner and branding
# 2. Update software from repositories
# 3. Clean temporary files to free space
# 4. Start core infrastructure (web server, database)
# 5. Configure logging and monitoring
# 6. Start AI services (TTS, STT, text processing)
# 7. Display connection information for users
# 8. Begin log monitoring to keep container alive
#######################################
main() {
    log_message \"INFO\" \"Starting DwemerDistro service initialization\"
    
    # Display application banner and branding information
    display_banner
    
    # Update DwemerDistro components from the git repository
    # This ensures the latest features and bug fixes are applied
    update_dwemer_distro
    
    # Update GWS (Game World Server) components
    # This updates game-specific integrations and content
    update_gws
    
    # Clean temporary files to free disk space and remove stale data
    # Helps prevent disk space issues and improves performance
    cleanup_temp_files
    
    # Start core infrastructure services required by all AI components
    # Apache web server provides the UI and API endpoints
    # PostgreSQL database stores conversation history and configurations
    start_core_services
    
    # Setup Apache logging configuration for debugging and monitoring
    # Creates symbolic links and ensures log directories exist
    setup_apache_logging
    
    # NOTE: AI service installation is currently disabled
    # The installation functions are defined above but not currently called
    # This section would automatically install AI services if their installation scripts are missing
    # Uncomment the lines below to enable automatic AI service installation:
    # install_ai_service \"Minime-T5/TXT2VEC\" \"\$MINIME_INSTALL_SCRIPT\" \"\$DWEMER_HOME/minime-t5\" \"L_MINIME\"
    # install_ai_service \"Mimic3 TTS\" \"\$MIMIC_INSTALL_SCRIPT\" \"\$DWEMER_HOME/mimic3\" \"L_MIMIC\"
    # install_ai_service \"MeloTTS\" \"\$MELOTTS_INSTALL_SCRIPT\" \"\$DWEMER_HOME/MeloTTS\" \"L_MELOTTS\"
    # install_ai_service \"LocalWhisper\" \"\$WHISPER_INSTALL_SCRIPT\" \"\$DWEMER_HOME/remote-faster-whisper\" \"L_WHISPER\"
    # install_ai_service \"CHIM XTTS\" \"\$XTTS_INSTALL_SCRIPT\" \"\$DWEMER_HOME/xtts-api-server\" \"L_XTTSV2\"

    # Start all AI services using existing installations
    # Each service will be tested for availability and port accessibility
    # Failed services are logged but don't stop the overall initialization
    start_ai_services
    
    # Display comprehensive connection information for users
    # Shows available service URLs and configuration details
    display_service_info
    
    # Start log monitoring to keep container running indefinitely
    # This prevents the container from exiting and provides real-time log access
    # The container will continue running until manually stopped
    start_log_monitoring
}

# Script entry point - only execute main function if script is run directly
# This allows the script to be sourced for testing without automatically executing
# The condition checks if this script is being executed directly vs being sourced
if [[ \"\${BASH_SOURCE[0]}\" == \"\${0}\" ]]; then
    # Pass all command line arguments to the main function
    # This enables future expansion for command-line argument processing
    main \"\$@\"
fi

# ===================================================================
# END OF DwemerDistro Service Startup Script
# ===================================================================
SCRIPT_EOF
chmod +x /etc/start_env && /etc/start_env"
)
# Note: The startup command above does the following:
# 1. Creates a complete startup script (/etc/start_env) inside the container with all required services
# 2. The script handles DwemerDistro updates, service initialization, and log monitoring
# 3. Makes the script executable and runs it immediately
# 4. The script will run indefinitely, monitoring logs to keep the container alive
# 5. All AI services are started and monitored for proper operation

# --- Final Container Deployment ---
# Deploy the container with or without NVIDIA GPU support based on system capabilities
# The deployment method depends on available hardware and drivers

if [[ -n "$nvidia_gpu_id" && "$nvidia_runtime_installed" == "yes" ]]; then
    # Deploy with NVIDIA GPU acceleration
    # This provides significant performance improvements for AI inference
    info "🚀 Deploying Docker container WITH NVIDIA GPU support"
    info "   Using GPU: $nvidia_gpu_id"
    info "   This will enable AI workload acceleration for better performance"
    
    # Add NVIDIA-specific Docker runtime and GPU device specification
    # --runtime=nvidia: Use NVIDIA container runtime for GPU access
    # --gpus device="$nvidia_gpu_id": Specify exact GPU to use by UUID (more reliable than 'all')
    sudo docker run -d --runtime=nvidia --gpus device="$nvidia_gpu_id" "${DOCKER_RUN_ARGS[@]}"
    
    info "✓ Container deployed successfully with GPU acceleration"
else
    # Deploy without GPU support (CPU-only mode)
    # Still fully functional but with slower AI inference
    info "🚀 Deploying Docker container WITHOUT NVIDIA GPU support"
    if [[ "$nvidia_runtime_installed" == "no" ]]; then
        info "   Reason: NVIDIA Docker runtime not installed"
        info "   Install nvidia-container-toolkit for GPU support"
    elif [[ -z "$nvidia_gpu_id" ]]; then
        info "   Reason: No NVIDIA GPU detected"
        info "   Ensure NVIDIA drivers are installed and GPU is accessible"
    fi
    info "   Container will run in CPU-only mode"
    
    # Deploy container with standard Docker runtime
    sudo docker run -d "${DOCKER_RUN_ARGS[@]}"
    
    info "✓ Container deployed successfully in CPU mode"
fi

# --- Post-Deployment Verification and User Guidance ---
# Provide comprehensive information about the deployed system including:
# - Access URLs and connection instructions
# - Management commands for container lifecycle  
# - File system layout for troubleshooting
# - Performance monitoring recommendations
info "=== DEPLOYMENT COMPLETE ==="
info "Container '${CONTAINER_NAME}' has been created and started"
info ""
info "🌐 Access the Skyrim AI web interface at:"
info "   http://localhost:8081/HerikaServer/ui/index.php"
info ""
info "📊 Monitor container status with:"
info "   sudo docker ps                      # View running containers"
info "   sudo docker logs ${CONTAINER_NAME}  # View container logs"
info ""
info "🔧 Container management commands:"
info "   Start:   sudo docker start ${CONTAINER_NAME}"
info "   Stop:    sudo docker stop ${CONTAINER_NAME}"
info "   Restart: sudo docker restart ${CONTAINER_NAME}"
info ""
info "📁 Persistent data locations:"
info "   PostgreSQL: ${DOCKER_ENV_DIR}/skyrimai_postgres     # Database files"
info "   Web files:  ${DOCKER_ENV_DIR}/skyrimai_www          # Web interface and PHP files"
info "   User data:  ${DOCKER_ENV_DIR}/skyrimai_dwemerhome   # AI models and configurations"
info "   Temp files: ${DOCKER_ENV_DIR}/skyrimai_tmp          # Temporary processing files"



# ==========================================================
# Optional: Advanced Logging Configuration
# ==========================================================
# The following section defines specific log file paths that could be monitored
# These are currently commented out but provide examples of important log locations
# within the Skyrim AI Framework for debugging and monitoring purposes
#
# When troubleshooting issues, these logs provide detailed insight into different 
# components of the system and can help identify the root cause of problems:

# # Discrete log file paths for advanced monitoring (currently disabled)
# # Uncomment and modify as needed for specific debugging scenarios:
# LOG_FILES=(
#     # Apache web server logs - for HTTP request and server error analysis
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/log/apache2/error.log"           # Web server errors and warnings
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/log/apache2/other_vhosts_access.log"  # Virtual host access patterns
#     
#     # Skyrim AI Framework specific logs - for AI processing and communication analysis
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/www/html/HerikaServer/log/debugStream.log"         # Debug information stream
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/www/html/HerikaServer/log/context_sent_to_llm.log" # Data sent to AI model
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/www/html/HerikaServer/log/output_from_llm.log"     # AI model responses
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/www/html/HerikaServer/log/output_to_plugin.log"    # Data sent to Skyrim plugin
#     "${DOCKER_ENV_DIR}/skyrimai_www/var/www/html/HerikaServer/log/minai.log"              # Minimal AI interaction log
# )
# 
# # To enable advanced log monitoring:
# # 1. Uncomment the LOG_FILES array above
# # 2. Implement custom log monitoring functionality as needed
# # 3. Consider using tools like logrotate for log management
# # 4. Set up alerts for critical error patterns in production environments

# Final completion message with helpful next steps
info ""
info "🎯 Setup completed successfully!"
info "The Skyrim AI Framework Docker environment is now ready for use."
info ""
info "📋 Next Steps:"
info "   1. Wait 30-60 seconds for all services to fully initialize"
info "   2. Access the web interface to verify everything is working"
info "   3. Download the AIAgent.ini configuration file from the web interface"
info "   4. Configure your Skyrim installation to use this AI server"
info ""
info "🔍 Troubleshooting:"
info "   • Check container logs: sudo docker logs ${CONTAINER_NAME}"
info "   • Verify service status: sudo docker exec ${CONTAINER_NAME} ps aux"
info "   • Check service ports: sudo docker exec ${CONTAINER_NAME} netstat -tulpn"
info "   • View web server logs: sudo docker exec ${CONTAINER_NAME} tail -f /var/log/apache2/error.log"
info ""
info "📖 For detailed usage instructions, refer to the documentation in your workspace"

