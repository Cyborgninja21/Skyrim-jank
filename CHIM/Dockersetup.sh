#!/usr/bin/env bash
# soruce https://dwemerdynamics.hostwiki.io/en/Linux-Guide
# https://www.nexusmods.com/skyrimspecialedition/mods/126330?tab=files
# ==========================================================
# Skyrim AI Framework Docker Setup Script (Refactored)
# ==========================================================
# This script sets up a Docker environment for the Skyrim AI Framework.
# It performs the following tasks:
# 1. Checks if running as root
# 2. Imports Docker image if it doesn't exist
# 3. Sets up necessary directory structures
# 4. Creates the Docker service with or without NVIDIA support
# ==========================================================

set -euo pipefail

# --- Configurable variables ---
LINUX_USER="${LINUX_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"
WSL_TAR_IMAGE_PATH="${WSL_TAR_IMAGE_PATH:-/home/${LINUX_USER}/docker_build/DwemerAI4Skyrim3.tar}"
POSTGRES_UID=107
POSTGRES_GID=116
DWEMER_UID=1000
DWEMER_GID=1000

# --- Utility functions ---
err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO] $*"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found. Aborting."; exit 1; }
}

setup_dir_from_tar() {
    local target_dir="$1"; shift
    local tar_path="$1"; shift
    local tar_args=("$@")
    if [[ ! -d "$target_dir" ]]; then
        info "Preparing $(basename "$target_dir")"
        mkdir -p "$target_dir"
        tar -xvf "$tar_path" -C "$target_dir" "${tar_args[@]}"
    fi
}

setup_dir() {
    local target_dir="$1"; shift
    local mode="$1"; shift
    if [[ ! -d "$target_dir" ]]; then
        info "Preparing $(basename "$target_dir")"
        mkdir -p "$target_dir"
        chmod "$mode" "$target_dir"
    fi
}

set_owner() {
    local target_dir="$1"; shift
    local uid="$1"; shift
    local gid="$1"; shift
    chown "$uid:$gid" -R "$target_dir"
}

# --- Main script ---

# Check for required commands
for cmd in docker tar grep; do
    require_cmd "$cmd"
done

# Check if script is running as root (required for Docker operations)
if [[ $(id -u) -ne 0 ]]; then
    err "Run this script as root (sudo $0)"
    exit 1
fi

# Display current user and ask for confirmation
info "Detected user: $LINUX_USER"
info "This script will set up Docker environment for user: $LINUX_USER"
info "Docker directories will be created in: /home/$LINUX_USER/docker_env/"
info "Docker build directory: /home/$LINUX_USER/docker_build/"
echo -n "Do you want to continue with user '$LINUX_USER'? (y/N): "
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Setup cancelled by user"
    exit 0
fi

# Pre-setup: Ensure docker_build directory exists
DOCKER_BUILD_DIR="/home/$(whoami)/docker_build"
if [[ ! -d "$DOCKER_BUILD_DIR" ]]; then
    info "Creating required directory: $DOCKER_BUILD_DIR"
    mkdir -p "$DOCKER_BUILD_DIR"
else
    info "Docker build directory already exists: $DOCKER_BUILD_DIR"
fi

# Step 1: Check and create Docker image
info "Checking for existing Docker image..."
if ! sudo docker image list --format '{{.Repository}}' | grep -q '^skyrimai$'; then
    info "Creating docker image..."
    docker image import "$WSL_TAR_IMAGE_PATH" skyrimai:latest
else
    info "Docker image already exists, ok"
fi

# Step 2: Setup directory structures

# PostgreSQL data
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_postgres" "$WSL_TAR_IMAGE_PATH" ./var/lib/postgresql/15 --strip-components=4
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_postgres" "$POSTGRES_UID" "$POSTGRES_GID"
chmod 750 -R "/home/${LINUX_USER}/docker_env/skyrimai_postgres"

# Temporary directory
setup_dir "/home/${LINUX_USER}/docker_env/skyrimai_tmp" 777

# Dwemer home
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome" "$WSL_TAR_IMAGE_PATH" ./home/dwemer/ --strip-components=3
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome" "$DWEMER_UID" "$DWEMER_GID"

# WWW directory
setup_dir_from_tar "/home/${LINUX_USER}/docker_env/skyrimai_www" "$WSL_TAR_IMAGE_PATH" ./var/www/html --strip-components=4
set_owner "/home/${LINUX_USER}/docker_env/skyrimai_www" "$DWEMER_UID" "$DWEMER_GID"

# Step 3: Create Docker service
info "Creating docker service 'skyrimaiframework'"

# Check for NVIDIA runtime
if sudo docker system info | grep -i runtimes | grep -iq nvidia; then
    nvidia_runtime_installed="yes"
else
    nvidia_runtime_installed="no"
fi
info "NVIDIA docker runtime installed: $nvidia_runtime_installed"

# Check for NVIDIA GPU
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia_gpu_id=$(nvidia-smi -L 2>/dev/null | grep -oP "(?<=UUID: ).*(?=\))" || true)
else
    nvidia_gpu_id=""
fi
if [[ -n "$nvidia_gpu_id" ]]; then
    info "NVIDIA GPU detected: yes"
else
    info "NVIDIA GPU detected: no"
fi

# Check if container already exists (use docker filter for reliability)
if sudo docker ps -a --filter name=^/skyrimaiframework$ --format '{{.Names}}' | grep -q '^skyrimaiframework$'; then
    info "Found existing skyrimaiframework container"
    echo -n "Do you want to remove the existing container and recreate it? (y/N): "
    read -r remove_response
    if [[ "$remove_response" =~ ^[Yy]$ ]]; then
        info "Stopping existing container..."
        sudo docker container stop skyrimaiframework 2>/dev/null || true
        info "Removing existing container..."
        sudo docker container rm skyrimaiframework 2>/dev/null || true
        info "Existing container removed successfully"
        info "Proceeding with new container creation..."
    else
        info "Setup cancelled. Existing container will remain unchanged."
        exit 0
    fi
fi

# Build common docker run args
DOCKER_RUN_ARGS=(
    --name=skyrimaiframework
    --log-driver=json-file
    --log-opt max-size=10m
    --log-opt max-file=3
    -p 8081:8081
    -p 8082:8082
    -p 8083:8083
    -p 59125:59125
    -p 9876:9876
    -p 8020:8020
    -p 8007:8007
    -v "/home/${LINUX_USER}/docker_env/skyrimai_postgres:/var/lib/postgresql"
    -v "/home/${LINUX_USER}/docker_env/skyrimai_tmp:/tmp"
    -v "/home/${LINUX_USER}/docker_env/skyrimai_dwemerhome:/home/dwemer"
    -v "/home/${LINUX_USER}/docker_env/skyrimai_www:/var/www/html"
    --restart unless-stopped
    skyrimai:latest
    sh -c "sed -i '/explorer\.exe http:\/\/\$ipaddress:8081\/HerikaServer\/ui\/index\.php &>\/dev\/null&/,\$d' /etc/start_env && \
        echo 'tail -f /var/log/apache2/error.log /var/log/apache2/access.log' >> /etc/start_env && \
        /etc/start_env"
)

# Add NVIDIA options if available
if [[ -n "$nvidia_gpu_id" && "$nvidia_runtime_installed" == "yes" ]]; then
    info "Installing docker service with nvidia support"
    sudo docker run -d --runtime=nvidia --gpus device="$nvidia_gpu_id" "${DOCKER_RUN_ARGS[@]}"
else
    info "Installing docker service without nvidia support"
    sudo docker run -d "${DOCKER_RUN_ARGS[@]}"
fi








# # Discrete log file paths (no duplicates)
# LOG_FILES=(
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/error.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/other_vhosts_access.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/debugStream.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/context_sent_to_llm.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_from_llm.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_to_plugin.log"
#     "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/minai.log"
# )

