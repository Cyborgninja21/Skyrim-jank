#!/bin/bash

# =============================================================================
# Zonos Installation and Management Script
# -----------------------------------------------------------------------------
# This script automates the installation and management of the Zonos environment.
#
# Functionality:
#   - Validates system prerequisites (git, python3, apt)
#   - Installs required system dependencies (espeak-ng)
#   - Clones the Zonos repository
#   - Sets up a Python virtual environment
#   - Installs the uv package manager
#   - Syncs project dependencies (including compile extras)
#
# Usage:
#   bash zonos.sh [COMMAND]
#
# Commands:
#   install           Install Zonos (default if no command is given)
#   update            Update existing Zonos installation
#   download-models   Download Zonos models using download_models.py
#   all               Run complete setup (install/update + download models)
#   help              Show help message and usage examples
#
# Examples:
#   bash zonos.sh                 # Install Zonos
#   bash zonos.sh install         # Install Zonos
#   bash zonos.sh update          # Update existing Zonos installation
#   bash zonos.sh download-models # Download Zonos models
#   bash zonos.sh all             # Complete setup (install/update + download)
#   bash zonos.sh help            # Show help message
#
# Notes:
#   - This script is intended for Debian/Ubuntu systems with 'apt' available.
#   - Run with appropriate permissions (may require 'sudo' for system installs).
#   - For troubleshooting, review log output and error messages.
# =============================================================================

# Zonos Installation and Management Script
# Description: Installs and manages Zonos environment
# Author: Auto-generated
# Date: $(date +%Y-%m-%d)

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$SCRIPT_DIR"
readonly REPO_URL="https://github.com/Zyphra/Zonos.git"
readonly REPO_NAME="Zonos"
readonly VENV_NAME="."

# Color codes for output
readonly RED='\e[41m'
readonly GREEN='\e[42m'
readonly YELLOW='\e[43m'
readonly BLUE='\e[44m'
readonly NC='\e[0m'  # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Enhanced error checking function
check_error() {
    local exit_code=$?
    local error_message="${1:-Unknown error occurred}"
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Error:${NC} $error_message (Exit code: $exit_code)"
        echo "Press Enter to exit..."
        read -r
        exit $exit_code
    fi
}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} [$timestamp] $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message"
            ;;
        *)
            echo "[$timestamp] $message"
            ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    if ! command_exists git; then
        log "ERROR" "Git is not installed. Please install git first."
        exit 1
    fi
    
    if ! command_exists python3; then
        log "ERROR" "Python3 is not installed. Please install Python3 first."
        exit 1
    fi
    
    if ! command_exists apt; then
        log "ERROR" "apt package manager is not available. This script requires a Debian/Ubuntu system."
        exit 1
    fi
    
    log "INFO" "Prerequisites validated successfully."
}

# Install system dependencies
install_system_dependencies() {
    log "INFO" "Installing system dependencies..."
    
    # Update package list
    log "INFO" "Updating package list..."
    sudo apt update
    check_error "Failed to update package list"
    
    # Install Python3 and pip
    if ! command_exists python3; then
        log "INFO" "Installing Python3..."
        sudo apt install -y python3
        check_error "Failed to install Python3"
        log "INFO" "Python3 installed successfully."
    else
        log "INFO" "Python3 is already installed."
    fi
    
    if ! command_exists pip3; then
        log "INFO" "Installing pip for Python3..."
        sudo apt install -y python3-pip
        check_error "Failed to install pip"
        log "INFO" "pip installed successfully."
    else
        log "INFO" "pip is already installed."
    fi
    
    # Install espeak-ng
    if ! command_exists espeak-ng; then
        log "INFO" "Installing espeak-ng..."
        sudo apt install -y espeak-ng
        check_error "Failed to install espeak-ng"
        log "INFO" "espeak-ng installed successfully."
    else
        log "INFO" "espeak-ng is already installed."
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

# Clone repository
clone_repository() {
    log "INFO" "Starting Zonos repository clone..."
    
    cd "$INSTALL_DIR" || {
        log "ERROR" "Failed to navigate to install directory: $INSTALL_DIR"
        exit 1
    }
    
    if [ -d "$REPO_NAME" ]; then
        log "WARN" "Repository directory already exists. Removing old installation..."
        rm -rf "$REPO_NAME"
    fi
    
    git clone "$REPO_URL"
    check_error "Failed to clone repository from $REPO_URL"
    
    cd "$REPO_NAME" || {
        log "ERROR" "Failed to navigate to repository directory"
        exit 1
    }
    
    log "INFO" "Repository cloned successfully."
}

# Check if repository exists and is valid
check_repository_exists() {
    cd "$INSTALL_DIR" || {
        log "ERROR" "Failed to navigate to install directory: $INSTALL_DIR"
        exit 1
    }
    
    if [ -d "$REPO_NAME" ]; then
        cd "$REPO_NAME" || {
            log "ERROR" "Failed to navigate to repository directory"
            return 1
        }
        
        # Check if it's a valid git repository
        if git rev-parse --git-dir >/dev/null 2>&1; then
            # Check if the remote URL matches
            local current_url=$(git remote get-url origin 2>/dev/null || echo "")
            if [ "$current_url" = "$REPO_URL" ]; then
                log "INFO" "Valid Zonos repository found."
                return 0
            else
                log "WARN" "Repository exists but remote URL doesn't match. Expected: $REPO_URL, Found: $current_url"
                return 1
            fi
        else
            log "WARN" "Directory exists but is not a valid git repository."
            return 1
        fi
    else
        log "INFO" "Repository directory does not exist."
        return 1
    fi
}

# Update existing repository
update_repository() {
    log "INFO" "Updating existing Zonos repository..."
    
    cd "$INSTALL_DIR/$REPO_NAME" || {
        log "ERROR" "Failed to navigate to repository directory"
        exit 1
    }
    
    # Fetch latest changes
    log "INFO" "Fetching latest changes..."
    git fetch origin
    check_error "Failed to fetch latest changes"
    
    # Check if there are any local changes
    if ! git diff --quiet HEAD; then
        log "WARN" "Local changes detected. Stashing them..."
        git stash push -m "Auto-stash before update $(date)"
        check_error "Failed to stash local changes"
    fi
    
    # Pull latest changes
    log "INFO" "Pulling latest changes..."
    git pull origin main
    check_error "Failed to pull latest changes"
    
    log "INFO" "Repository updated successfully."
}

# Setup virtual environment
setup_virtual_environment() {
    log "INFO" "Setting up Python virtual environment..."
    
    python3 -m venv "$VENV_NAME"
    check_error "Failed to create virtual environment"
    
    # Activate virtual environment
    source ./bin/activate
    check_error "Failed to activate virtual environment"
    
    log "INFO" "Virtual environment created and activated."
}

# Install uv package manager
install_uv() {
    log "INFO" "Installing uv package manager..."
    
    ./bin/pip install -U uv
    check_error "Failed to install uv package manager"
    
    # Deactivate virtual environment temporarily
    deactivate
    
    log "INFO" "uv package manager installed successfully."
}

# Sync dependencies
sync_dependencies() {
    log "INFO" "Syncing project dependencies..."
    
    ./bin/uv sync
    check_error "Failed to sync dependencies"
    
    log "INFO" "Dependencies synced successfully."
}

# Sync with compile extras
sync_compile_dependencies() {
    log "INFO" "Syncing compile dependencies..."
    
    ./bin/uv sync --extra compile
    check_error "Failed to sync compile dependencies"
    
    log "INFO" "Compile dependencies synced successfully."
}

# Install additional required dependencies
install_additional_dependencies() {
    log "INFO" "Installing additional required dependencies..."
    
    # Install torch and torchaudio which are required for model downloads
    log "INFO" "Installing torch and torchaudio..."
    ./bin/uv add torch torchaudio
    check_error "Failed to install torch and torchaudio"
    
    log "INFO" "Additional dependencies installed successfully."
}

# Check if virtual environment exists
install_additional_packages() {
    log "INFO" "Installing additional Python packages..."

    # Activate virtual environment
    source ./bin/activate
    check_error "Failed to activate virtual environment"

    # Install packages defined in the PACKAGES variable
    local PACKAGES=(torch torchaudio numpy pandas)
    for package in "${PACKAGES[@]}"; do
        ./bin/pip install "$package"
        check_error "Failed to install $package"
    done

    # Deactivate virtual environment
    deactivate

    log "INFO" "Additional Python packages installed successfully."
}

# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

install_zonos() {
    local auto_mode="${1:-false}"
    log "INFO" "Starting Zonos installation process..."
    
    validate_prerequisites
    install_system_dependencies
    
    # Check if repository already exists
    if check_repository_exists; then
        if [ "$auto_mode" = "true" ]; then
            log "INFO" "Auto-mode: Updating existing installation..."
            update_zonos
            return 0
        else
            log "WARN" "Zonos repository already exists."
            echo "Choose an option:"
            echo "1) Update existing installation (recommended)"
            echo "2) Remove and reinstall completely"
            echo "3) Cancel installation"
            read -p "Enter your choice (1-3): " choice
            
            case "$choice" in
                1)
                    log "INFO" "Proceeding with update..."
                    update_zonos
                    return 0
                    ;;
                2)
                    log "INFO" "Removing existing installation..."
                    cd "$INSTALL_DIR" || exit 1
                    rm -rf "$REPO_NAME"
                    ;;
                3)
                    log "INFO" "Installation cancelled."
                    exit 0
                    ;;
                *)
                    log "ERROR" "Invalid choice. Installation cancelled."
                    exit 1
                    ;;
            esac
        fi
    fi
    
    clone_repository
    setup_virtual_environment
    install_uv
    sync_dependencies
    sync_compile_dependencies
    install_additional_dependencies
    install_additional_packages
    
    log "INFO" "Zonos installation completed successfully!"
}

# Update existing Zonos installation
update_zonos() {
    log "INFO" "Starting Zonos update process..."
    
    validate_prerequisites
    
    if ! check_repository_exists; then
        log "ERROR" "No valid Zonos installation found. Please run 'install' first."
        exit 1
    fi
    
    update_repository
    
    # Navigate to the repository directory
    cd "$INSTALL_DIR/$REPO_NAME" || {
        log "ERROR" "Failed to navigate to repository directory"
        exit 1
    }
    
    # Check if virtual environment exists
    if [ -d "./bin" ] && [ -f "./bin/activate" ]; then
        log "INFO" "Updating dependencies in existing virtual environment..."
        sync_dependencies
        sync_compile_dependencies
        install_additional_dependencies
    else
        log "WARN" "Virtual environment not found. Setting up new environment..."
        setup_virtual_environment
        install_uv
        sync_dependencies
        sync_compile_dependencies
        install_additional_dependencies
    fi
    
    log "INFO" "Zonos update completed successfully!"
}

# =============================================================================
# MODEL DOWNLOAD FUNCTIONS
# =============================================================================

# Download Zonos models
zonos_download_models() {
    log "INFO" "Starting Zonos model download process..."
    
    # Check if Zonos installation exists
    if ! check_repository_exists; then
        log "ERROR" "No valid Zonos installation found. Please run 'install' first."
        exit 1
    fi
    
    # Navigate to the repository directory
    cd "$INSTALL_DIR/$REPO_NAME" || {
        log "ERROR" "Failed to navigate to repository directory"
        exit 1
    }
    
    # Check if virtual environment exists and is properly set up
    if [ ! -d "./bin" ] || [ ! -f "./bin/activate" ]; then
        log "ERROR" "Virtual environment not found. Please run 'install' or 'update' first."
        exit 1
    fi
    
    # Create models download directory relative to the install script
    local models_dir="$INSTALL_DIR/zonos_download_models"
    if [ ! -d "$models_dir" ]; then
        log "INFO" "Creating models directory: $models_dir"
        mkdir -p "$models_dir"
        check_error "Failed to create models directory"
    fi
    
    # Look for download_models.py in common locations
    local download_script=""
    local search_paths=(
        "../Non 50xx card/download_models.py"
        "../../Non 50xx card/download_models.py"
        "../download_models.py"
        "./download_models.py"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            download_script="$path"
            log "INFO" "Found download_models.py at: $path"
            break
        fi
    done
    
    if [ -z "$download_script" ]; then
        log "ERROR" "download_models.py not found. Please ensure it exists in the workspace."
        log "INFO" "Searched in the following locations:"
        for path in "${search_paths[@]}"; do
            log "INFO" "  - $path"
        done
        exit 1
    fi
    
    # Create a modified download script that uses our models directory
    local temp_download_script="$models_dir/download_models_temp.py"
    log "INFO" "Creating customized download script..."
    
    # Copy the original script and modify it to use our models directory
    cat > "$temp_download_script" << 'EOF'
#!/usr/bin/env python3

# GPU FIX: Backup check in case bash script doesn't set environment
import os
import sys

# Set models cache directory to our custom location
models_dir = os.path.dirname(os.path.abspath(__file__))
os.environ['HF_HOME'] = models_dir
os.environ['HUGGINGFACE_HUB_CACHE'] = os.path.join(models_dir, 'hub')
os.environ['TRANSFORMERS_CACHE'] = os.path.join(models_dir, 'transformers')

print(f"Models will be downloaded to: {models_dir}")

if 'CUDA_VISIBLE_DEVICES' not in os.environ:
    print("WARNING: Setting GPU environment from Python")
    os.environ['CUDA_VISIBLE_DEVICES'] = '1'
    os.environ['CUDA_DEVICE_ORDER'] = 'PCI_BUS_ID'

import torch
import torchaudio

# Debug: Confirm GPU selection
print(f"Model download using: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}")

from zonos.model import Zonos
from zonos.conditioning import make_cond_dict
from zonos.utils import DEFAULT_DEVICE as device

print("Downloading hybrid model...")
model = Zonos.from_pretrained("Zyphra/Zonos-v0.1-hybrid", device=device, cache_dir=os.path.join(models_dir, 'models'))
print("Downloading transformer model...")
model = Zonos.from_pretrained("Zyphra/Zonos-v0.1-transformer", device=device, cache_dir=os.path.join(models_dir, 'models'))
print("All models downloaded successfully!")
print(f"Models saved to: {models_dir}")
EOF
    
    # Activate virtual environment and run download script
    log "INFO" "Activating virtual environment..."
    source ./bin/activate
    check_error "Failed to activate virtual environment"
    
    # Ensure we're using the same environment paths
    export PYTHONPATH="$INSTALL_DIR/$REPO_NAME:${PYTHONPATH:-}"
    
    log "INFO" "Running customized model download script..."
    log "INFO" "Models will be downloaded to: $models_dir"
    python "$temp_download_script"
    check_error "Failed to download models"
    
    # Clean up temporary script
    rm -f "$temp_download_script"
    
    # Deactivate virtual environment
    deactivate
    
    log "INFO" "Model download completed successfully!"
    log "INFO" "Models saved to: $models_dir"
}

# =============================================================================
# COMPLETE SETUP FUNCTION
# =============================================================================

# Run complete setup process
zonos_complete_setup() {
    log "INFO" "Starting complete Zonos setup process..."
    
    # Step 1: Install or update Zonos
    log "INFO" "Step 1/2: Setting up Zonos installation..."
    if check_repository_exists; then
        log "INFO" "Existing installation found. Updating..."
        update_zonos
    else
        log "INFO" "No existing installation found. Installing..."
        install_zonos "true"  # Pass auto-mode flag
    fi
    
    # Step 2: Download models
    log "INFO" "Step 2/2: Downloading models..."
    zonos_download_models
    
    log "INFO" "Complete Zonos setup finished successfully!"
    log "INFO" "Your Zonos environment is ready to use!"
}

# =============================================================================
# MAIN SCRIPT EXECUTION
# =============================================================================

main() {
    echo "======================================"
    echo "    Zonos Installation Script"
    echo "======================================"
    echo ""
    
    case "${1:-install}" in
        "install")
            install_zonos
            ;;
        "update")
            update_zonos
            ;;
        "download-models")
            zonos_download_models
            ;;
        "all")
            zonos_complete_setup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    install           Install Zonos (default)
    update            Update existing Zonos installation
    download-models   Download Zonos models using download_models.py
    all               Run complete setup (install/update + download models)
    help              Show this help message

Examples:
    $0                      # Install Zonos
    $0 install              # Install Zonos
    $0 update               # Update existing Zonos installation
    $0 download-models      # Download Zonos models
    $0 all                  # Complete setup (install/update + download)
    $0 help                 # Show help

Workflow:
    For new users:         $0 all
    For existing users:    $0 update && $0 download-models
    Individual commands:   $0 install, $0 update, $0 download-models

EOF
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi