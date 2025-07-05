#!/usr/bin/env bash

# ==========================================================
# Skyrim AI Framework Docker Setup Script
# ==========================================================
# This script sets up a Docker environment for the Skyrim AI Framework.
# It performs the following tasks:
# 1. Checks if running as root
# 2. Imports Docker image if it doesn't exist
# 3. Sets up necessary directory structures
# 4. Creates the Docker service with or without NVIDIA support
# ==========================================================

# Check if script is running as root (required for Docker operations)
if [[ $(whoami) != "root" ]]; then
    echo "[ERROR] Run this script as root (sudo $0)"
    exit 1
fi

# Configuration variables
linux_user="ctd"
wsl_tar_image_path="/home/${linux_user}/docker_build/DwemerAI4Skyrim3.tar"

# ----------------------------------------
# Step 1: Check and create Docker image
# ----------------------------------------
echo "[INFO] Checking for existing Docker image..."
sudo docker image list | grep -q skyrimai

if [[ ${?} -ne 0 ]]; then
    echo "[INFO] Creating docker image..."
    docker image import ${wsl_tar_image_path} skyrimai:latest
else
    echo "[INFO] Docker image already exists, ok"
fi

# ----------------------------------------
# Step 2: Setup directory structures
# ----------------------------------------

# Setup PostgreSQL directory
if [[ ! -d "/home/${linux_user}/docker_env/skyrimai_postgres" ]]; then
    echo "[INFO] Preparing skyrimai_postgres"
    mkdir -p /home/${linux_user}/docker_env/skyrimai_postgres
    cd /home/${linux_user}/docker_env/skyrimai_postgres
    tar -xvf ${wsl_tar_image_path} ./var/lib/postgresql/15 --strip-components=4
    chown 107:116 -R /home/${linux_user}/docker_env/skyrimai_postgres
    chmod 750 -R /home/${linux_user}/docker_env/skyrimai_postgres
fi

# Setup temporary directory
if [[ ! -d "/home/${linux_user}/docker_env/skyrimai_tmp" ]]; then
    echo "[INFO] Preparing skyrimai_tmp"
    mkdir -p /home/${linux_user}/docker_env/skyrimai_tmp
    chmod 777 /home/${linux_user}/docker_env/skyrimai_tmp
fi

# Setup Dwemer home directory
if [[ ! -d "/home/${linux_user}/docker_env/skyrimai_dwemerhome" ]]; then
    echo "[INFO] Preparing skyrimai_dwemerhome"
    mkdir -p /home/${linux_user}/docker_env/skyrimai_dwemerhome
    chown 1000:1000 -R /home/${linux_user}/docker_env/skyrimai_dwemerhome
    cd /home/${linux_user}/docker_env/skyrimai_dwemerhome
    tar -xvf ${wsl_tar_image_path} ./home/dwemer/ --strip-components=3
fi

# Setup www directory
if [[ ! -d "/home/${linux_user}/docker_env/skyrimai_www" ]]; then
    echo "[INFO] Preparing skyrimai_www"
    mkdir -p /home/${linux_user}/docker_env/skyrimai_www
    chown 1000:1000 -R /home/${linux_user}/docker_env/skyrimai_www
    cd /home/${linux_user}/docker_env/skyrimai_www
    tar -xvf ${wsl_tar_image_path} ./var/www/html --strip-components=4
fi

# ----------------------------------------
# Step 3: Create Docker service
# ----------------------------------------
echo "[INFO] Creating docker service \"skyrimaiframework\""

# Check for NVIDIA runtime
sudo docker system info | grep -i runtimes | grep -iq nvidia
if [[ ${?} -eq 0 ]]; then
    nvidia_runtime_installed="yes"
else
    nvidia_runtime_installed="no"
fi
echo "[INFO] NVIDIA docker runtime installed: ${nvidia_runtime_installed}"

# Check for NVIDIA GPU
nvidia_gpu_id=$(nvidia-smi -L 2>/dev/null | grep -oP "(?<=UUID: ).*(?=\))")
if [[ ! -z ${nvidia_gpu_id} ]]; then
    echo "[INFO] NVIDIA GPU detected: yes"
else
    echo "[INFO] NVIDIA GPU detected: no"
fi

# Check if container already exists
sudo docker ps -a | grep -iq skyrimaiframework
if [[ ${?} -eq 0 ]]; then
    echo "[ERROR] There already exists skyrimaiframework service. If you want to recreate the service, first remove the old one (sudo docker container stop skyrimaiframework && sudo docker container remove skyrimaiframework) and then rerun this script"
    exit 1
fi

# Create the Docker container with appropriate configuration
if [[ ! -z ${nvidia_gpu_id} && ${nvidia_runtime_installed} = "yes" ]]; then
    echo "[INFO] Installing docker service with nvidia support"
    sudo docker run -d \
        --name=skyrimaiframework \
        --runtime=nvidia \
        --gpus device=${nvidia_gpu_id} \
        -p 8081:8081 \
        -p 8082:8082 \
        -p 8083:8083 \
        -p 59125:59125 \
        -p 9876:9876 \
        -p 8020:8020 \
        -p 8007:8007 \
        -v /home/${linux_user}/docker_env/skyrimai_postgres:/var/lib/postgresql \
        -v /home/${linux_user}/docker_env/skyrimai_tmp:/tmp \
        -v /home/${linux_user}/docker_env/skyrimai_dwemerhome:/home/dwemer \
        -v /home/${linux_user}/docker_env/skyrimai_www:/var/www/html \
        --restart unless-stopped \
        skyrimai:latest \
        sh -c "sed -i '148,158d' /etc/start_env && echo 'tail -f /dev/null' >> /etc/start_env && /etc/start_env"
else
    echo "[INFO] Installing docker service without nvidia support"
    sudo docker run -d \
        --name=skyrimaiframework \
        -p 8081:8081 \
        -p 8082:8082 \
        -p 8083:8083 \
        -p 59125:59125 \
        -p 9876:9876 \
        -p 8020:8020 \
        -p 8007:8007 \
        -v /home/${linux_user}/docker_env/skyrimai_postgres:/var/lib/postgresql \
        -v /home/${linux_user}/docker_env/skyrimai_tmp:/tmp \
        -v /home/${linux_user}/docker_env/skyrimai_dwemerhome:/home/dwemer \
        -v /home/${linux_user}/docker_env/skyrimai_www:/var/www/html \
        --restart unless-stopped \
        skyrimai:latest \
        sh -c "sed -i '148,158d' /etc/start_env && echo 'tail -f /dev/null' >> /etc/start_env && /etc/start_env"
fi