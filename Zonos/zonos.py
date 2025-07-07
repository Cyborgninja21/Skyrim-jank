#!/usr/bin/env python3

"""
=============================================================================
                         ZONOS INSTALLATION & MANAGEMENT SCRIPT
=============================================================================

DESCRIPTION:
    This script provides a complete installation and management system for the
    Zonos machine learning environment. It handles everything from initial setup
    to running different Gradio interfaces with proper GPU configuration.

QUICK START:
    # Basic installation (recommended for first-time users):
    python zonos.py

    # Run Zonos after installation:
    python zonos.py run

USAGE:
    python zonos.py [COMMAND] [OPTIONS]

COMMANDS:
    install          Install Zonos completely (default if no command given)
                     - Validates system prerequisites (git, python3, apt)
                     - Installs system dependencies (espeak-ng)
                     - Clones Zonos repository from GitHub
                     - Sets up Python virtual environment with uv package manager
                     - Downloads and verifies ML models with SHA256 hashing
                     - Configures optimal environment variables for ML workloads
                     - Sets proper file ownership and permissions
    
    run              Launch Zonos with interactive interface selection
                     - Automatically discovers available Gradio interfaces
                     - Presents interactive menu for interface type selection
                     - Configures GPU and ML environment variables
                     - Launches selected interface in optimized environment
    
    download-models  Download and verify Zonos models only
                     - Downloads Zyphra/Zonos-v0.1-hybrid and transformer models
                     - Uses SHA256 verification to prevent re-downloading
                     - Stores models in ./zonos_download_models/ directory
                     - Optimizes Hugging Face cache configuration
    
    verify-models    Verify integrity of downloaded models
                     - Checks SHA256 hashes against stored verification data
                     - Validates all required model files are present
                     - Reports detailed verification status for each model
    
    update           Check for and apply updates
                     - Checks GitHub repository for new commits
                     - Verifies model integrity and availability
                     - Interactive prompts for selective updating
                     - Updates dependencies and fixes ownership
    
    uninstall        Completely remove Zonos installation
                     - Removes repository, models, and virtual environment
                     - Cleans up cache directories and environment variables
                     - Requires double confirmation for safety
                     - Preserves user data outside Zonos directories
    
    setup-env        Configure environment variables only
                     - Sets up CUDA, PyTorch, and ML optimization variables
                     - Configures Hugging Face cache directories
                     - Optimizes memory management settings
                     - Creates models directory with proper permissions
    
    help             Show detailed help information

FEATURES:
    ✓ Cross-platform support (Linux/Windows with appropriate adaptations)
    ✓ GPU optimization with automatic CUDA configuration
    ✓ Model verification system with SHA256 hashing
    ✓ Comprehensive logging to separate files per operation
    ✓ File ownership management for proper permissions
    ✓ Interactive interface selection for Gradio environments
    ✓ Update system with selective repository/model updating
    ✓ Virtual environment isolation with uv package manager
    ✓ Memory and performance optimization for ML workloads

SYSTEM REQUIREMENTS:
    - Python 3.8+ with pip
    - Git for repository management
    - apt package manager (Debian/Ubuntu systems)
    - CUDA-capable GPU (recommended, CPU fallback available)
    - 10GB+ free disk space for models and dependencies
    - Internet connection for downloads and updates

DIRECTORY STRUCTURE:
    ./zonos.py                    # This script
    ./Zonos/                      # Cloned repository with virtual environment
    ./zonos_download_models/      # Downloaded ML models and cache
    ./zonos_*.log                 # Operation-specific log files

ENVIRONMENT VARIABLES (Auto-configured):
    CUDA_VISIBLE_DEVICES=1        # GPU device selection
    CUDA_DEVICE_ORDER=PCI_BUS_ID  # Device ordering method
    HF_HOME=./zonos_download_models/  # Hugging Face cache location
    TORCH_CUDA_ARCH_LIST=...      # Supported CUDA architectures
    OMP_NUM_THREADS=4             # OpenMP optimization
    Plus 15+ additional ML optimization variables

LOG FILES (Created automatically):
    zonos_install.log            # Installation process details
    zonos_execution.log          # Runtime and interface launching
    zonos_models.log             # Model download operations
    zonos_verification.log       # Model verification results
    zonos_update.log             # Update operations
    zonos_uninstall.log          # Uninstallation process
    zonos_environment.log        # Environment setup details

EXAMPLES:
    # Complete fresh installation:
    python zonos.py install

    # Quick start (install if needed, then run):
    python zonos.py && python zonos.py run

    # Download models without full installation:
    python zonos.py download-models

    # Check for updates and apply selectively:
    python zonos.py update

    # Verify model integrity:
    python zonos.py verify-models

    # Clean removal:
    python zonos.py uninstall

    # Just configure environment (for development):
    python zonos.py setup-env

GRADIO INTERFACES (Available after installation):
    The script automatically discovers interface types in:
    ./Zonos/Gradio_InterfacePY_Types/[Type]/gradio_interface.py
    
    Common interface types include:
    - BFloat16 Max Gradio         # Maximum precision mode
    - Inference Mode Gradio       # Optimized inference
    - Original Gradio             # Standard interface
    - Prevent Gradient Gradio     # Memory-optimized mode

TROUBLESHOOTING:
    - Check log files for detailed error information
    - Ensure system meets requirements (Python 3.8+, Git, apt)
    - Verify internet connection for downloads
    - Run 'python zonos.py verify-models' to check model integrity
    - Use 'python zonos.py update' to fix repository issues
    - For permission issues, ensure script is run with appropriate privileges

SECURITY NOTES:
    - Script manages file ownership automatically
    - Log files contain system information (review before sharing)
    - Models downloaded from Hugging Face (verify source if security-critical)
    - Virtual environment isolation prevents system contamination

VERSION INFORMATION:
    Compatible with Zonos v0.1 models and repository structure
    Requires uv package manager for dependency management
    Supports CUDA architectures 6.0 through 9.0

=============================================================================

Author: Auto-generated
Date: 2025-07-06
"""

import os
import sys
import subprocess
import shutil
import argparse
import hashlib
import json
import logging
import logging.handlers
import getpass
import pwd
import grp
from pathlib import Path
from datetime import datetime
from typing import NoReturn, Dict, Optional
import logging
import logging.handlers

import platform

# =============================================================================
# CONFIGURATION
# =============================================================================

if platform.system() != "Linux":
    print("This script is Linux-only. Exiting.")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent.absolute()
INSTALL_DIR = SCRIPT_DIR
REPO_URL = "https://github.com/Zyphra/Zonos.git"
REPO_NAME = "Zonos"
VENV_NAME = "."

# =============================================================================
# ENVIRONMENT VARIABLES CONFIGURATION
# =============================================================================

# Model Download Configuration
MODELS_DOWNLOAD_DIR = "zonos_download_models"  # Directory for downloaded models (relative to script)
MODEL_VERIFICATION_FILE = "model_verification.json"  # File to store model verification info

# Model configurations with expected information
MODEL_CONFIGS = {
    "Zyphra/Zonos-v0.1-hybrid": {
        "name": "hybrid_model",
        "description": "Zonos v0.1 Hybrid Model",
        "files_to_check": ["config.json", "pytorch_model.bin", "tokenizer.json"]
    },
    "Zyphra/Zonos-v0.1-transformer": {
        "name": "transformer_model", 
        "description": "Zonos v0.1 Transformer Model",
        "files_to_check": ["config.json", "pytorch_model.bin", "tokenizer.json"]
    }
}

# CUDA Configuration
CUDA_VISIBLE_DEVICES = "1"  # Default GPU device ID
CUDA_DEVICE_ORDER = "PCI_BUS_ID"  # Device ordering method

# PyTorch Configuration
TORCH_CUDA_ARCH_LIST = "6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0"  # CUDA architectures to support
PYTORCH_CUDA_ALLOC_CONF = "max_split_size_mb:512"  # CUDA memory allocation configuration

# Memory Management
OMP_NUM_THREADS = "4"  # OpenMP thread count
MKL_NUM_THREADS = "4"  # Intel MKL thread count
NUMEXPR_NUM_THREADS = "4"  # NumExpr thread count
OPENBLAS_NUM_THREADS = "4"  # OpenBLAS thread count

# CUDA Memory and Performance
CUDA_LAUNCH_BLOCKING = "0"  # Set to "1" for debugging CUDA operations
CUDA_CACHE_DISABLE = "0"  # Set to "1" to disable CUDA kernel caching
NCCL_DEBUG = "WARN"  # NCCL debug level (INFO, WARN, ERROR)

# Hugging Face Configuration
HF_HOME = ""  # Hugging Face cache directory (empty = use models download dir)
TRANSFORMERS_CACHE = ""  # Transformers model cache (empty = use models download dir)
HF_DATASETS_CACHE = ""  # Datasets cache directory (empty = use models download dir)

# Python Optimization
PYTHONUNBUFFERED = "1"  # Force Python stdout/stderr to be unbuffered
PYTHONDONTWRITEBYTECODE = "1"  # Prevent Python from writing .pyc files

# Logging and Debug
TOKENIZERS_PARALLELISM = "false"  # Disable tokenizers parallelism warnings
WANDB_DISABLED = "false"  # Weights & Biases logging (set to "true" to disable)

# System Configuration
MALLOC_TRIM_THRESHOLD_ = "100000"  # Memory allocation tuning
MALLOC_MMAP_THRESHOLD_ = "131072"  # Memory mapping threshold

# Logging Configuration
LOG_DIR = SCRIPT_DIR  # Log files in same directory as script
INSTALL_LOG_FILE = "zonos_install.log"  # Installation log file
EXECUTION_LOG_FILE = "zonos_execution.log"  # Execution/runtime log file
MAX_LOG_SIZE = 10 * 1024 * 1024  # 10MB max log file size
LOG_BACKUP_COUNT = 3  # Keep 3 backup log files

# Color codes for output
class Colors:
    RED = '\033[41m'
    GREEN = '\033[42m'
    YELLOW = '\033[43m'
    BLUE = '\033[44m'
    NC = '\033[0m'  # No Color


# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Global logger instance
_logger = None
_current_log_file = None

def setup_logging(log_type: str = "install") -> None:
    """Setup logging to file and console"""
    global _logger, _current_log_file
    
    # Determine log file based on type
    if log_type == "install":
        log_filename = INSTALL_LOG_FILE
    elif log_type == "execution":
        log_filename = EXECUTION_LOG_FILE
    else:
        log_filename = f"zonos_{log_type}.log"
    
    log_path = LOG_DIR / log_filename
    _current_log_file = log_path
    
    # Ensure log directory exists with proper permissions
    ensure_directory_permissions(LOG_DIR)
    
    # Create logger
    _logger = logging.getLogger('zonos')
    _logger.setLevel(logging.DEBUG)
    
    # Clear any existing handlers
    _logger.handlers.clear()
    
    # Create rotating file handler
    file_handler = logging.handlers.RotatingFileHandler(
        log_path, 
        maxBytes=MAX_LOG_SIZE, 
        backupCount=LOG_BACKUP_COUNT,
        encoding='utf-8'
    )
    file_handler.setLevel(logging.DEBUG)
    
    # Create console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    
    # Create detailed formatter for file
    file_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(file_formatter)
    
    # Create simple formatter for console (we'll handle colors separately)
    console_formatter = logging.Formatter('%(message)s')
    console_handler.setFormatter(console_formatter)
    
    # Add handlers to logger
    _logger.addHandler(file_handler)
    _logger.addHandler(console_handler)
    
    # Fix ownership of log file
    if log_path.exists():
        ensure_file_permissions(log_path)
    
    # Log setup information
    _logger.info(f"=== ZONOS {log_type.upper()} SESSION STARTED ===")
    _logger.info(f"Log file: {log_path}")
    _logger.info(f"Script directory: {SCRIPT_DIR}")
    _logger.info(f"Python version: {sys.version}")
    _logger.info(f"Platform: {os.name}")
    
    user_info = get_current_user_info()
    _logger.info(f"User: {user_info['username']}")
    
    if os.name != 'nt':
        _logger.info(f"UID: {user_info['uid']}, GID: {user_info['gid']}")


def get_logger():
    """Get the current logger instance"""
    global _logger
    if _logger is None:
        setup_logging()
    return _logger


def close_logging() -> None:
    """Close logging and clean up handlers"""
    global _logger, _current_log_file
    
    if _logger:
        _logger.info("=== ZONOS SESSION ENDED ===")
        _logger.info("")  # Add blank line for separation
        
        # Close all handlers
        for handler in _logger.handlers:
            handler.close()
        _logger.handlers.clear()
        
        # Fix final ownership of log file
        if _current_log_file and _current_log_file.exists():
            ensure_file_permissions(_current_log_file)
        
        _logger = None
        _current_log_file = None


def get_log_file_path() -> Optional[Path]:
    """Get the current log file path"""
    return _current_log_file


# =============================================================================
# MODEL VERIFICATION FUNCTIONS
# =============================================================================

def calculate_file_hash(file_path: Path) -> str:
    """Calculate SHA256 hash of a file"""
    hash_sha256 = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_sha256.update(chunk)
        return hash_sha256.hexdigest()
    except (FileNotFoundError, PermissionError) as e:
        log("WARN", f"Could not hash file {file_path}: {e}")
        return ""


def get_model_cache_path(model_name: str, models_dir: Path) -> Optional[Path]:
    """Get the cache path for a model in Hugging Face cache structure"""
    # Hugging Face uses a specific directory structure
    # Try common patterns for model storage
    possible_paths = [
        models_dir / "models--" + model_name.replace("/", "--"),
        models_dir / model_name.replace("/", "--"),
        models_dir / model_name.split("/")[-1],
    ]
    
    for path in possible_paths:
        if path.exists():
            return path
    
    # If none found, check subdirectories
    for subdir in models_dir.iterdir():
        if subdir.is_dir() and model_name.split("/")[-1] in subdir.name:
            return subdir
    
    return None


def verify_model_integrity(model_name: str, models_dir: Path, verification_data: Dict) -> bool:
    """Verify if a model is properly downloaded and hasn't changed"""
    model_config = MODEL_CONFIGS.get(model_name)
    if not model_config:
        log("WARN", f"No configuration found for model: {model_name}")
        return False
    
    # Get model cache path
    cache_path = get_model_cache_path(model_name, models_dir)
    if not cache_path or not cache_path.exists():
        log("DEBUG", f"Model cache path not found for: {model_name}")
        return False
    
    # Check if we have verification data for this model
    model_key = model_config["name"]
    if model_key not in verification_data:
        log("DEBUG", f"No verification data found for: {model_name}")
        return False
    
    stored_hashes = verification_data[model_key]
    
    # Find the actual model files (they might be in snapshots subdirectory)
    model_files_dir = cache_path
    if (cache_path / "snapshots").exists():
        # Find the latest snapshot
        snapshots = [d for d in (cache_path / "snapshots").iterdir() if d.is_dir()]
        if snapshots:
            # Sort by modification time and get the latest
            model_files_dir = max(snapshots, key=lambda x: x.stat().st_mtime)
    
    # Verify each required file
    for file_name in model_config["files_to_check"]:
        file_path = model_files_dir / file_name
        if not file_path.exists():
            log("DEBUG", f"Required file missing: {file_path}")
            return False
        
        current_hash = calculate_file_hash(file_path)
        if not current_hash:
            log("DEBUG", f"Could not calculate hash for: {file_path}")
            return False
        
        if file_name not in stored_hashes or stored_hashes[file_name] != current_hash:
            log("DEBUG", f"Hash mismatch for {file_name} in {model_name}")
            return False
    
    log("DEBUG", f"Model verification successful for: {model_name}")
    return True


def save_model_verification(model_name: str, models_dir: Path, verification_file: Path) -> None:
    """Save model verification data after successful download"""
    model_config = MODEL_CONFIGS.get(model_name)
    if not model_config:
        return
    
    # Load existing verification data
    verification_data = {}
    if verification_file.exists():
        try:
            with open(verification_file, 'r') as f:
                verification_data = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            verification_data = {}
    
    # Get model cache path
    cache_path = get_model_cache_path(model_name, models_dir)
    if not cache_path:
        log("WARN", f"Could not find cache path for model: {model_name}")
        return
    
    # Find the actual model files
    model_files_dir = cache_path
    if (cache_path / "snapshots").exists():
        snapshots = [d for d in (cache_path / "snapshots").iterdir() if d.is_dir()]
        if snapshots:
            model_files_dir = max(snapshots, key=lambda x: x.stat().st_mtime)
    
    # Calculate hashes for all required files
    model_hashes = {}
    for file_name in model_config["files_to_check"]:
        file_path = model_files_dir / file_name
        if file_path.exists():
            model_hashes[file_name] = calculate_file_hash(file_path)
    
    # Save verification data
    model_key = model_config["name"]
    verification_data[model_key] = {
        "hashes": model_hashes,
        "model_name": model_name,
        "download_time": datetime.now().isoformat(),
        "cache_path": str(cache_path)
    }
    
    try:
        with open(verification_file, 'w') as f:
            json.dump(verification_data, f, indent=2)
        
        # Ensure proper ownership and permissions for verification file
        ensure_file_permissions(verification_file)
        
        log("DEBUG", f"Saved verification data for: {model_name}")
    except Exception as e:
        log("WARN", f"Could not save verification data: {e}")


def load_verification_data(verification_file: Path) -> Dict:
    """Load model verification data from file"""
    if not verification_file.exists():
        return {}
    
    try:
        with open(verification_file, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        log("WARN", f"Could not load verification data: {e}")
        return {}


def verify_models() -> None:
    """Verify integrity of downloaded models"""
    log("INFO", "Starting model verification process...")
    
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    if not models_dir.exists():
        log("ERROR", "Models directory not found. Please download models first.")
        sys.exit(1)
    
    verification_file = models_dir / MODEL_VERIFICATION_FILE
    verification_data = load_verification_data(verification_file)
    
    if not verification_data:
        log("WARN", "No verification data found. Models may need to be re-downloaded.")
        return
    
    failed_models = []
    for model_name in MODEL_CONFIGS.keys():
        model_config = MODEL_CONFIGS[model_name]
        log("INFO", f"Verifying {model_config['description']} ({model_name})...")
        if verify_model_integrity(model_name, models_dir, verification_data):
            log("INFO", f"✓ {model_config['description']} verification successful.")
        else:
            log("ERROR", f"✗ {model_config['description']} verification failed.")
            failed_models.append(model_config['description'])
    if not failed_models:
        log("INFO", "All models verified successfully!")
    else:
        log("WARN", f"Some models failed verification: {', '.join(failed_models)}. Consider re-downloading.")
        print("\nVerification summary:")
        for name in failed_models:
            print(f"  ✗ {name}")
        print("\nYou may continue using verified models, or re-download the failed ones.")


# =============================================================================
# ENVIRONMENT SETUP FUNCTIONS
# =============================================================================

def setup_environment_variables() -> None:
    """Configure environment variables for optimal performance"""
    log("INFO", "Configuring environment variables...")
    
    # Create models download directory with proper ownership
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    ensure_directory_permissions(models_dir)
    log("INFO", f"Models download directory: {models_dir}")
    
    env_vars = {
        # CUDA Configuration
        'CUDA_VISIBLE_DEVICES': CUDA_VISIBLE_DEVICES,
        'CUDA_DEVICE_ORDER': CUDA_DEVICE_ORDER,
        
        # PyTorch Configuration
        'TORCH_CUDA_ARCH_LIST': TORCH_CUDA_ARCH_LIST,
        'PYTORCH_CUDA_ALLOC_CONF': PYTORCH_CUDA_ALLOC_CONF,
        
        # Memory Management
        'OMP_NUM_THREADS': OMP_NUM_THREADS,
        'MKL_NUM_THREADS': MKL_NUM_THREADS,
        'NUMEXPR_NUM_THREADS': NUMEXPR_NUM_THREADS,
        'OPENBLAS_NUM_THREADS': OPENBLAS_NUM_THREADS,
        
        # CUDA Memory and Performance
        'CUDA_LAUNCH_BLOCKING': CUDA_LAUNCH_BLOCKING,
        'CUDA_CACHE_DISABLE': CUDA_CACHE_DISABLE,
        'NCCL_DEBUG': NCCL_DEBUG,
        
        # Python Optimization
        'PYTHONUNBUFFERED': PYTHONUNBUFFERED,
        'PYTHONDONTWRITEBYTECODE': PYTHONDONTWRITEBYTECODE,
        
        # Logging and Debug
        'TOKENIZERS_PARALLELISM': TOKENIZERS_PARALLELISM,
        'WANDB_DISABLED': WANDB_DISABLED,
        
        # System Configuration
        'MALLOC_TRIM_THRESHOLD_': MALLOC_TRIM_THRESHOLD_,
        'MALLOC_MMAP_THRESHOLD_': MALLOC_MMAP_THRESHOLD_,
    }
    
    # Set Hugging Face cache directories - use models download dir if not specified
    if HF_HOME:
        env_vars['HF_HOME'] = HF_HOME
    else:
        env_vars['HF_HOME'] = str(models_dir)
        
    if TRANSFORMERS_CACHE:
        env_vars['TRANSFORMERS_CACHE'] = TRANSFORMERS_CACHE
    else:
        env_vars['TRANSFORMERS_CACHE'] = str(models_dir / "transformers")
        
    if HF_DATASETS_CACHE:
        env_vars['HF_DATASETS_CACHE'] = HF_DATASETS_CACHE
    else:
        env_vars['HF_DATASETS_CACHE'] = str(models_dir / "datasets")
    
    # Set environment variables, but don't override existing ones
    for var_name, var_value in env_vars.items():
        if var_name not in os.environ:
            os.environ[var_name] = var_value
            log("DEBUG", f"Set {var_name} = {var_value}")
        else:
            log("DEBUG", f"Using existing {var_name} = {os.environ[var_name]}")
    
    log("INFO", "Environment variables configured successfully.")


# =============================================================================
# OWNERSHIP AND PERMISSIONS FUNCTIONS
# =============================================================================

def get_current_user_info() -> Dict[str, any]:
    """Get current user information for ownership management (Linux only)"""
    import pwd, grp, getpass
    try:
        current_user = pwd.getpwuid(os.getuid())
        current_group = grp.getgrgid(os.getgid())
        return {
            "uid": current_user.pw_uid,
            "gid": current_user.pw_gid,
            "username": current_user.pw_name,
            "groupname": current_group.gr_name
        }
    except Exception:
        return {
            "uid": None,
            "gid": None,
            "username": getpass.getuser(),
            "groupname": None
        }


def fix_ownership_recursive(path: Path, user_info: Dict = None) -> None:
    """Recursively fix ownership of files and directories (Linux only)"""
    if user_info is None:
        user_info = get_current_user_info()
    if user_info["uid"] is None or user_info["gid"] is None:
        log("DEBUG", "Cannot determine user/group IDs, skipping ownership fix")
        return
    try:
        if path.exists():
            log("DEBUG", f"Fixing ownership for: {path}")
            os.chown(path, user_info["uid"], user_info["gid"])
            if path.is_dir():
                for item in path.rglob("*"):
                    try:
                        os.chown(item, user_info["uid"], user_info["gid"])
                    except (PermissionError, FileNotFoundError) as e:
                        log("WARN", f"Could not fix ownership for {item}: {e}")
            log("DEBUG", f"Ownership fixed for {path} and its contents")
    except (PermissionError, FileNotFoundError) as e:
        log("WARN", f"Could not fix ownership for {path}: {e}")
    except Exception as e:
        log("WARN", f"Unexpected error fixing ownership for {path}: {e}")


def ensure_directory_permissions(directory: Path, mode: int = 0o755) -> None:
    """Ensure directory has proper permissions and ownership (Linux only)"""
    try:
        if not directory.exists():
            directory.mkdir(parents=True, exist_ok=True)
            log("DEBUG", f"Created directory: {directory}")
        user_info = get_current_user_info()
        fix_ownership_recursive(directory, user_info)
        try:
            os.chmod(directory, mode)
            log("DEBUG", f"Set permissions {oct(mode)} for: {directory}")
        except PermissionError as e:
            log("WARN", f"Could not set permissions for {directory}: {e}")
    except Exception as e:
        log("WARN", f"Could not ensure proper permissions for {directory}: {e}")


def ensure_file_permissions(file_path: Path, mode: int = 0o644) -> None:
    """Ensure file has proper permissions and ownership (Linux only)"""
    try:
        if file_path.exists():
            user_info = get_current_user_info()
            fix_ownership_recursive(file_path, user_info)
            try:
                os.chmod(file_path, mode)
                log("DEBUG", f"Set permissions {oct(mode)} for: {file_path}")
            except PermissionError as e:
                log("WARN", f"Could not set permissions for {file_path}: {e}")
    except Exception as e:
        log("WARN", f"Could not ensure proper permissions for {file_path}: {e}")


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def show_progress(message: str, show_spinner: bool = True) -> None:
    """Show progress message with Linux-compatible output"""
    if show_spinner:
        # Simple progress indicator
        sys.stdout.write(f"\r{message}... ")
        sys.stdout.flush()
    else:
        log("INFO", message)


def show_progress_complete(message: str = "Done") -> None:
    """Complete progress indication"""
    sys.stdout.write(f"{message}\n")
    sys.stdout.flush()


def ensure_console_output() -> None:
    """Ensure console output is properly configured for Linux"""
    # Force unbuffered output for real-time display
    if hasattr(sys.stdout, 'reconfigure'):
        try:
            sys.stdout.reconfigure(line_buffering=True)
        except:
            pass
    
    # Set environment variable for unbuffered output
    os.environ['PYTHONUNBUFFERED'] = '1'


def check_error(exit_code: int, error_message: str = "Unknown error occurred") -> None:
    """Enhanced error checking function"""
    if exit_code != 0:
        print(f"{Colors.RED}Error:{Colors.NC} {error_message} (Exit code: {exit_code})")
        input("Press Enter to exit...")
        sys.exit(exit_code)


def log(level: str, message: str) -> None:
    """Enhanced logging function with file and console output"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Color mapping for console output
    color_map = {
        "INFO": Colors.GREEN,
        "WARN": Colors.YELLOW,
        "ERROR": Colors.RED,
        "DEBUG": Colors.BLUE
    }
    
    # Console output with colors (Linux-compatible)
    color = color_map.get(level, "")
    console_message = f"{color}[{level}]{Colors.NC} [{timestamp}] {message}"
    
    # Get logger and log to file (if available)
    logger = get_logger()
    if logger:
        # Map our custom levels to logging levels
        if level == "INFO":
            logger.info(message)
        elif level == "WARN":
            logger.warning(message)
        elif level == "ERROR":
            logger.error(message)
        elif level == "DEBUG":
            logger.debug(message)
        else:
            logger.info(f"[{level}] {message}")
    
    # Always output to console using Linux-compatible methods
    # Use sys.stdout.write for direct console output
    sys.stdout.write(console_message + '\n')
    sys.stdout.flush()  # Ensure immediate output


def command_exists(command: str) -> bool:
    """Check if command exists"""
    return shutil.which(command) is not None


def run_command(command: list, error_message: str = None, check: bool = True, show_output: bool = True) -> subprocess.CompletedProcess:
    """Run a command and handle errors with real-time console output"""
    try:
        log("DEBUG", f"Executing command: {' '.join(command)}")
        
        if show_output:
            # Run command with real-time output to console
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # Stream output in real-time
            output_lines = []
            for line in iter(process.stdout.readline, ''):
                if line:
                    # Output directly to console using Linux-compatible method
                    sys.stdout.write(line)
                    sys.stdout.flush()
                    output_lines.append(line.rstrip())
            
            process.wait()
            output = '\n'.join(output_lines)
            
            # Create result object compatible with subprocess.run
            result = subprocess.CompletedProcess(
                command, process.returncode, stdout=output, stderr=''
            )
        else:
            # Use regular subprocess.run for commands that don't need real-time output
            result = subprocess.run(command, check=False, capture_output=True, text=True)
        
        if check and result.returncode != 0:
            if error_message:
                log("ERROR", error_message)
            log("ERROR", f"Command failed: {' '.join(command)}")
            log("ERROR", f"Return code: {result.returncode}")
            if result.stderr:
                log("ERROR", f"stderr: {result.stderr}")
            sys.exit(result.returncode)
        
        return result
        
    except subprocess.CalledProcessError as e:
        if error_message:
            log("ERROR", error_message)
        log("ERROR", f"Command failed: {' '.join(command)}")
        log("ERROR", f"stderr: {e.stderr}")
        sys.exit(e.returncode)
    except FileNotFoundError:
        log("ERROR", f"Command not found: {command[0]}")
        sys.exit(1)
    except Exception as e:
        log("ERROR", f"Unexpected error running command: {e}")
        sys.exit(1)


def validate_prerequisites() -> None:
    """Validate prerequisites"""
    log("INFO", "Validating prerequisites...")
    
    if not command_exists("git"):
        log("ERROR", "Git is not installed. Please install git first.")
        sys.exit(1)
    
    if not command_exists("python3"):
        log("ERROR", "Python3 is not installed. Please install Python3 first.")
        sys.exit(1)
    
    if not command_exists("apt"):
        log("ERROR", "apt package manager is not available. This script requires a Debian/Ubuntu system.")
        sys.exit(1)
    
    log("INFO", "Prerequisites validated successfully.")


def install_system_dependencies() -> None:
    """Install system dependencies"""
    log("INFO", "Installing system dependencies...")
    
    # Ensure console output is properly configured
    ensure_console_output()
    
    # Update package list
    log("INFO", "Updating package list...")
    show_progress("Updating package repositories")
    run_command(["sudo", "apt", "update"], "Failed to update package list", show_output=True)
    show_progress_complete("✓ Package list updated")
    
    # Install espeak-ng
    if not command_exists("espeak-ng"):
        log("INFO", "Installing espeak-ng...")
        show_progress("Installing espeak-ng")
        run_command(["sudo", "apt", "install", "-y", "espeak-ng"], "Failed to install espeak-ng", show_output=True)
        show_progress_complete("✓ espeak-ng installed successfully")
        log("INFO", "espeak-ng installed successfully.")
    else:
        log("INFO", "espeak-ng is already installed.")


# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

def clone_repository() -> None:
    """Clone repository"""
    log("INFO", "Starting Zonos repository clone...")
    ensure_console_output()
    
    try:
        os.chdir(INSTALL_DIR)
    except OSError:
        log("ERROR", f"Failed to navigate to install directory: {INSTALL_DIR}")
        sys.exit(1)
    
    repo_path = INSTALL_DIR / REPO_NAME
    if repo_path.exists():
        log("WARN", "Repository directory already exists. Removing old installation...")
        shutil.rmtree(repo_path)
    
    log("INFO", f"Cloning Zonos repository from {REPO_URL}")
    sys.stdout.write(f"This may take a few minutes depending on your connection...\n")
    sys.stdout.flush()
    
    run_command(["git", "clone", REPO_URL], f"Failed to clone repository from {REPO_URL}", show_output=True)
    
    # Fix ownership of cloned repository
    log("INFO", "Setting proper ownership for repository files...")
    fix_ownership_recursive(repo_path)
    
    try:
        os.chdir(repo_path)
    except OSError:
        log("ERROR", "Failed to navigate to repository directory")
        sys.exit(1)
    
    log("INFO", "Repository cloned successfully.")


def setup_virtual_environment() -> None:
    """Setup virtual environment"""
    log("INFO", "Setting up Python virtual environment...")
    
    run_command(["python3", "-m", "venv", VENV_NAME], "Failed to create virtual environment")
    
    # Fix ownership of virtual environment
    venv_path = Path(VENV_NAME).resolve()
    fix_ownership_recursive(venv_path)
    
    log("INFO", "Virtual environment created successfully.")


def install_uv() -> None:
    """Install uv package manager (Linux only)"""
    log("INFO", "Installing uv package manager...")
    pip_path = "./bin/pip"
    run_command([pip_path, "install", "-U", "uv"], "Failed to install uv package manager")
    log("INFO", "uv package manager installed successfully.")


def sync_dependencies() -> None:
    """Sync dependencies (Linux only)"""
    log("INFO", "Syncing project dependencies...")
    uv_path = "./bin/uv"
    run_command([uv_path, "sync"], "Failed to sync dependencies")
    log("INFO", "Dependencies synced successfully.")


def sync_compile_dependencies() -> None:
    """Sync with compile extras (Linux only)"""
    log("INFO", "Syncing compile dependencies...")
    uv_path = "./bin/uv"
    run_command([uv_path, "sync", "--extra", "compile"], "Failed to sync compile dependencies")
    log("INFO", "Compile dependencies synced successfully.")


def download_models() -> None:
    """Download Zonos models with verification to avoid re-downloading"""
    log("INFO", "Starting model download process...")
    
    # Configure environment variables for optimal performance
    setup_environment_variables()
    
    # Create models download directory with proper ownership
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    ensure_directory_permissions(models_dir)
    log("INFO", f"Models will be downloaded to: {models_dir}")
    
    # Load existing verification data
    verification_file = models_dir / MODEL_VERIFICATION_FILE
    verification_data = load_verification_data(verification_file)
    
    try:
        # Import torch and related modules
        import torch
        import torchaudio
        
        # Debug: Confirm GPU selection
        device_name = torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'
        log("INFO", f"Model download using: {device_name}")
        
        if torch.cuda.is_available():
            log("INFO", f"CUDA version: {torch.version.cuda}")
            log("INFO", f"Available GPUs: {torch.cuda.device_count()}")
            log("INFO", f"Current GPU: {torch.cuda.current_device()}")
        
        # Show cache directory being used
        log("INFO", f"Hugging Face cache: {os.environ.get('HF_HOME', 'default')}")
        log("INFO", f"Transformers cache: {os.environ.get('TRANSFORMERS_CACHE', 'default')}")
        
        # Import Zonos modules
        from zonos.model import Zonos
        from zonos.conditioning import make_cond_dict
        from zonos.utils import DEFAULT_DEVICE as device
        
        models_to_download = list(MODEL_CONFIGS.keys())
        downloaded_models = []
        
        for model_name in models_to_download:
            model_config = MODEL_CONFIGS[model_name]
            log("INFO", f"Checking {model_config['description']} ({model_name})...")
            
            # Check if model is already downloaded and verified
            if verify_model_integrity(model_name, models_dir, verification_data):
                log("INFO", f"✓ {model_config['description']} is already downloaded and verified. Skipping.")
                continue
            
            # Download the model
            log("INFO", f"Downloading {model_config['description']} ({model_name})...")
            try:
                model = Zonos.from_pretrained(model_name, device=device)
                log("INFO", f"✓ {model_config['description']} downloaded successfully.")
                
                # Save verification data
                save_model_verification(model_name, models_dir, verification_file)
                downloaded_models.append(model_name)
                
                # Fix ownership of downloaded model files
                model_cache_path = get_model_cache_path(model_name, models_dir)
                if model_cache_path:
                    fix_ownership_recursive(model_cache_path)
                
                # Clean up model reference to free memory
                del model
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    
            except Exception as e:
                log("ERROR", f"Failed to download {model_config['description']}: {e}")
                raise
        
        if downloaded_models:
            log("INFO", f"Downloaded {len(downloaded_models)} new models:")
            for model_name in downloaded_models:
                log("INFO", f"  - {MODEL_CONFIGS[model_name]['description']}")
        else:
            log("INFO", "All models were already present and verified.")
        
        log("INFO", "All models are now available!")
        log("INFO", f"Models are stored in: {models_dir}")
        
    except ImportError as e:
        log("ERROR", f"Failed to import required modules: {e}")
        log("ERROR", "Make sure the virtual environment is activated and dependencies are installed")
        sys.exit(1)
    except Exception as e:
        log("ERROR", f"Failed to download models: {e}")
        sys.exit(1)


def check_repository_updates() -> Dict[str, any]:
    """Check if there are updates available for the Zonos repository"""
    repo_path = INSTALL_DIR / REPO_NAME
    if not repo_path.exists():
        return {"status": "not_installed", "message": "Repository not found"}
    
    try:
        # Change to repository directory
        original_cwd = os.getcwd()
        os.chdir(repo_path)
        
        # Fetch latest changes from remote
        log("INFO", "Checking for repository updates...")
        run_command(["git", "fetch", "origin"], "Failed to fetch from remote", check=False)
        
        # Get current commit hash
        result = run_command(["git", "rev-parse", "HEAD"], check=False)
        current_commit = result.stdout.strip() if result.returncode == 0 else ""
        
        # Get remote commit hash
        result = run_command(["git", "rev-parse", "origin/main"], check=False)
        remote_commit = result.stdout.strip() if result.returncode == 0 else ""
        
        # Check if there are differences
        if current_commit and remote_commit:
            if current_commit != remote_commit:
                # Get commit count difference
                result = run_command(["git", "rev-list", "--count", f"{current_commit}..{remote_commit}"], check=False)
                commits_behind = int(result.stdout.strip()) if result.returncode == 0 else 0
                
                # Get latest commit message
                result = run_command(["git", "log", "-1", "--pretty=format:%s", "origin/main"], check=False)
                latest_message = result.stdout.strip() if result.returncode == 0 else "No message"
                
                return {
                    "status": "update_available",
                    "current_commit": current_commit[:8],
                    "remote_commit": remote_commit[:8],
                    "commits_behind": commits_behind,
                    "latest_message": latest_message
                }
            else:
                return {"status": "up_to_date", "commit": current_commit[:8]}
        else:
            return {"status": "error", "message": "Could not determine commit status"}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}
    finally:
        os.chdir(original_cwd)


def check_model_updates() -> Dict[str, any]:
    """Check if there are updates available for the models"""
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    if not models_dir.exists():
        return {"status": "not_downloaded", "message": "Models not found"}
    
    verification_file = models_dir / MODEL_VERIFICATION_FILE
    verification_data = load_verification_data(verification_file)
    
    if not verification_data:
        return {"status": "no_verification", "message": "No verification data found"}
    
    try:
        # Check if we can import required modules to test model availability
        import torch
        from zonos.model import Zonos
        
        updates_available = []
        for model_name in MODEL_CONFIGS.keys():
            model_config = MODEL_CONFIGS[model_name]
            log("INFO", f"Checking for updates to {model_config['description']}...")
            
            try:
                # Try to get model info from HuggingFace to see if there are updates
                # This is a lightweight check that doesn't download the full model
                model_info = Zonos.from_pretrained(model_name, device="cpu", torch_dtype=torch.float16, low_cpu_mem_usage=True)
                
                # Check if verification fails (indicating potential updates)
                if not verify_model_integrity(model_name, models_dir, verification_data):
                    updates_available.append({
                        "model_name": model_name,
                        "description": model_config['description'],
                        "reason": "verification_failed"
                    })
                
                # Clean up
                del model_info
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    
            except Exception as e:
                log("WARN", f"Could not check updates for {model_name}: {e}")
                updates_available.append({
                    "model_name": model_name,
                    "description": model_config['description'],
                    "reason": "check_failed"
                })
        
        if updates_available:
            return {"status": "updates_available", "models": updates_available}
        else:
            return {"status": "up_to_date", "message": "All models are current"}
            
    except ImportError:
        return {"status": "cannot_check", "message": "Cannot check models - dependencies not available"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def update_repository() -> bool:
    """Update the Zonos repository to the latest version"""
    repo_path = INSTALL_DIR / REPO_NAME
    if not repo_path.exists():
        log("ERROR", "Repository not found. Please install first.")
        return False
    
    try:
        original_cwd = os.getcwd()
        os.chdir(repo_path)
        
        log("INFO", "Updating Zonos repository...")
        
        # Stash any local changes
        run_command(["git", "stash"], "Failed to stash changes", check=False)
        
        # Pull latest changes
        result = run_command(["git", "pull", "origin", "main"], check=False)
        if result.returncode != 0:
            log("ERROR", "Failed to pull latest changes")
            return False
        
        log("INFO", "✓ Repository updated successfully")
        
        # Update dependencies
        log("INFO", "Updating dependencies...")
        uv_path = "./bin/uv"
        if os.name == 'nt':
            uv_path = "./Scripts/uv.exe"
        
        run_command([uv_path, "sync"], "Failed to sync dependencies", check=False)
        run_command([uv_path, "sync", "--extra", "compile"], "Failed to sync compile dependencies", check=False)
        
        log("INFO", "✓ Dependencies updated successfully")
        
        # Fix ownership after updates
        fix_ownership_recursive(repo_path)
        log("INFO", "✓ Repository ownership updated")
        
        return True
        
    except Exception as e:
        log("ERROR", f"Failed to update repository: {e}")
        return False
    finally:
        os.chdir(original_cwd)


def update_models() -> bool:
    """Update models by re-downloading them"""
    log("INFO", "Updating models...")
    
    # Remove verification file to force re-download
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    verification_file = models_dir / MODEL_VERIFICATION_FILE
    
    if verification_file.exists():
        try:
            verification_file.unlink()
            log("INFO", "Removed verification data to force model updates")
        except Exception as e:
            log("WARN", f"Could not remove verification file: {e}")
    
    # Re-download models
    try:
        os.chdir(INSTALL_DIR / REPO_NAME)
        download_models()
        
        # Fix ownership of updated models
        models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
        fix_ownership_recursive(models_dir)
        log("INFO", "✓ Model ownership updated")
        
        return True
    except Exception as e:
        log("ERROR", f"Failed to update models: {e}")
        return False


def update_zonos() -> None:
    """Check for and apply updates to Zonos repository and models"""
    log("INFO", "Checking for Zonos updates...")
    
    # Check repository updates
    repo_status = check_repository_updates()
    model_status = check_model_updates()
    
    print("\n" + "=" * 60)
    print("ZONOS UPDATE CHECK")
    print("=" * 60)
    
    # Display repository status
    print("\n📦 REPOSITORY STATUS:")
    if repo_status["status"] == "not_installed":
        print("  ❌ Repository not installed")
        return
    elif repo_status["status"] == "up_to_date":
        print(f"  ✅ Repository is up to date (commit: {repo_status['commit']})")
        repo_needs_update = False
    elif repo_status["status"] == "update_available":
        print(f"  🔄 Updates available!")
        print(f"     Current: {repo_status['current_commit']}")
        print(f"     Latest:  {repo_status['remote_commit']}")
        print(f"     Behind by: {repo_status['commits_behind']} commits")
        print(f"     Latest change: {repo_status['latest_message']}")
        repo_needs_update = True
    else:
        print(f"  ⚠️  Error checking repository: {repo_status.get('message', 'Unknown error')}")
        repo_needs_update = False
    
    # Display model status
    print("\n🤖 MODELS STATUS:")
    if model_status["status"] == "not_downloaded":
        print("  ❌ Models not downloaded")
        model_needs_update = False
    elif model_status["status"] == "up_to_date":
        print("  ✅ All models are current")
        model_needs_update = False
    elif model_status["status"] == "updates_available":
        print("  🔄 Model updates may be available:")
        for model in model_status["models"]:
            reason = "verification failed" if model["reason"] == "verification_failed" else "check failed"
            print(f"     - {model['description']} ({reason})")
        model_needs_update = True
    elif model_status["status"] == "cannot_check":
        print(f"  ⚠️  Cannot check models: {model_status['message']}")
        model_needs_update = False
    else:
        print(f"  ⚠️  Error checking models: {model_status.get('message', 'Unknown error')}")
        model_needs_update = False
    
    # If no updates needed
    if not repo_needs_update and not model_needs_update:
        print("\n🎉 Everything is up to date!")
        return
    
    # Ask user what to update
    print("\n" + "=" * 60)
    if repo_needs_update and model_needs_update:
        print("Both repository and models have updates available.")
        choice = input("What would you like to update? (repo/models/both/none): ").strip().lower()
    elif repo_needs_update:
        print("Repository updates are available.")
        choice = input("Update repository? (yes/no): ").strip().lower()
        choice = "repo" if choice in ["yes", "y"] else "none"
    elif model_needs_update:
        print("Model updates may be available.")
        choice = input("Update models? (yes/no): ").strip().lower()
        choice = "models" if choice in ["yes", "y"] else "none"
    
    # Apply updates
    if choice in ["repo", "both"]:
        print("\n🔄 Updating repository...")
        if update_repository():
            log("INFO", "✅ Repository update completed successfully!")
        else:
            log("ERROR", "❌ Repository update failed!")
    
    if choice in ["models", "both"]:
        print("\n🔄 Updating models...")
        if update_models():
            log("INFO", "✅ Model update completed successfully!")
        else:
            log("ERROR", "❌ Model update failed!")
    
    if choice == "none":
        log("INFO", "Update cancelled by user.")
    
    print("\n" + "=" * 60)
    log("INFO", "Update check completed!")


def uninstall_zonos() -> None:
    """Uninstall Zonos and clean up all associated files"""
    log("INFO", "Starting Zonos uninstallation process...")
    
    # Remove Zonos repository
    repo_path = INSTALL_DIR / REPO_NAME
    if repo_path.exists():
        try:
            shutil.rmtree(repo_path)
            log("INFO", f"Removed repository: {repo_path}")
        except Exception as e:
            log("ERROR", f"Failed to remove repository: {e}")
            uninstall_errors.append(f"Repository: {e}")
    else:
        log("INFO", "Zonos repository not found (already removed).")

    # Remove models directory
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    if models_dir.exists():
        try:
            shutil.rmtree(models_dir)
            log("INFO", f"Removed models directory: {models_dir}")
        except Exception as e:
            log("ERROR", f"Failed to remove models directory: {e}")
            uninstall_errors.append(f"Models directory: {e}")
    else:
        log("INFO", "Models directory not found (already removed).")

    # Clean up environment variables (only for current session)
    log("INFO", "Cleaning up environment variables for current session...")
    env_vars_to_clean = [
        'CUDA_VISIBLE_DEVICES', 'CUDA_DEVICE_ORDER', 'TORCH_CUDA_ARCH_LIST',
        'PYTORCH_CUDA_ALLOC_CONF', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
        'NUMEXPR_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'CUDA_LAUNCH_BLOCKING',
        'CUDA_CACHE_DISABLE', 'NCCL_DEBUG', 'PYTHONUNBUFFERED',
        'PYTHONDONTWRITEBYTECODE', 'TOKENIZERS_PARALLELISM', 'WANDB_DISABLED',
        'MALLOC_TRIM_THRESHOLD_', 'MALLOC_MMAP_THRESHOLD_'
    ]
    cleaned_vars = 0
    for var_name in env_vars_to_clean:
        if var_name in os.environ:
            del os.environ[var_name]
            cleaned_vars += 1
    if cleaned_vars > 0:
        log("INFO", f"Cleaned up {cleaned_vars} environment variables.")
    else:
        log("INFO", "No environment variables needed cleaning.")

    # Remove any leftover cache directories that might have been created
    cache_dirs_to_check = [
        SCRIPT_DIR / "transformers",
        SCRIPT_DIR / "datasets", 
        SCRIPT_DIR / ".cache",
        Path.home() / ".cache" / "huggingface" / "transformers",
    ]
    for cache_dir in cache_dirs_to_check:
        try:
            if cache_dir.exists():
                shutil.rmtree(cache_dir)
                log("INFO", f"Removed cache directory: {cache_dir}")
        except Exception as e:
            log("WARN", f"Failed to remove cache directory {cache_dir}: {e}")
            uninstall_errors.append(f"Cache {cache_dir}: {e}")

    # Summary
    print("\nUninstallation summary:")
    if uninstall_errors:
        print("Some items could not be removed:")
        for err in uninstall_errors:
            print(f"  - {err}")
        log("WARN", f"Uninstallation completed with errors: {uninstall_errors}")
    else:
        print("All Zonos files and directories removed successfully.")
        log("INFO", "Uninstallation completed successfully.")

    log("INFO", "Uninstallation summary:")
    log("INFO", "  - Repository and virtual environment removed")
        'CUDA_CACHE_DISABLE', 'NCCL_DEBUG', 'PYTHONUNBUFFERED',
        'PYTHONDONTWRITEBYTECODE', 'TOKENIZERS_PARALLELISM', 'WANDB_DISABLED',
        'MALLOC_TRIM_THRESHOLD_', 'MALLOC_MMAP_THRESHOLD_'
    ]
    
    cleaned_vars = 0
    for var_name in env_vars_to_clean:
        if var_name in os.environ:
            # Only remove if it matches our configured values
            configured_value = globals().get(var_name, "")
            if os.environ.get(var_name) == configured_value:
                del os.environ[var_name]
                cleaned_vars += 1
                log("DEBUG", f"Cleaned environment variable: {var_name}")
    
    if cleaned_vars > 0:
        log("INFO", f"✓ Cleaned {cleaned_vars} environment variables.")
    else:
        log("INFO", "No environment variables needed cleaning.")
    
    # Remove any leftover cache directories that might have been created
    cache_dirs_to_check = [
        SCRIPT_DIR / "transformers",
        SCRIPT_DIR / "datasets", 
        SCRIPT_DIR / ".cache",
        Path.home() / ".cache" / "huggingface" / "transformers",
    ]
    
    for cache_dir in cache_dirs_to_check:
        if cache_dir.exists() and any(MODEL_CONFIGS[model]["name"] in str(p) for p in cache_dir.rglob("*") for model in MODEL_CONFIGS):
            try:
                log("INFO", f"Removing related cache directory: {cache_dir}")
                shutil.rmtree(cache_dir)
                log("INFO", f"✓ Cache directory removed: {cache_dir}")
            except Exception as e:
                error_msg = f"Failed to remove cache directory {cache_dir}: {e}"
                log("WARN", error_msg)
                # Don't add cache cleanup failures to critical errors
    
    # Summary
    if uninstall_errors:
        log("WARN", f"Uninstallation completed with {len(uninstall_errors)} errors:")
        for error in uninstall_errors:
            log("WARN", f"  - {error}")
        log("WARN", "You may need to manually remove some files with elevated permissions.")
    else:
        log("INFO", "✓ Zonos uninstallation completed successfully!")
    
    log("INFO", "Uninstallation summary:")
    log("INFO", "  - Repository and virtual environment removed")
    log("INFO", "  - Downloaded models and verification data removed")
    log("INFO", "  - Environment variables cleaned for current session")
    log("INFO", "  - Cache directories cleaned")
    
    if not uninstall_errors:
        log("INFO", "Zonos has been completely removed from your system.")


# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

def install_zonos() -> None:
    """Main installation function"""
    # Setup installation logging
    setup_logging("install")
    ensure_console_output()
    
    show_progress("Starting Zonos installation")
    log("INFO", "Starting Zonos installation process...")
    sys.stdout.write("This process will install the complete Zonos environment.\n")
    sys.stdout.write("This may take 30-60 minutes depending on your system.\n\n")
    sys.stdout.flush()
    show_progress_complete("READY")
    
    try:
        validate_prerequisites()
        install_system_dependencies()
        clone_repository()
        setup_virtual_environment()
        install_uv()
        sync_dependencies()
        sync_compile_dependencies()
        download_models()
        
        # Final ownership and permissions fix
        show_progress("Setting final permissions")
        log("INFO", "Ensuring proper ownership and permissions...")
        user_info = get_current_user_info()
        log("INFO", f"Setting ownership to user: {user_info['username']}")
        
        # Fix ownership for all created directories and files
        repo_path = INSTALL_DIR / REPO_NAME
        models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
        
        if repo_path.exists():
            fix_ownership_recursive(repo_path, user_info)
            log("INFO", "✓ Repository ownership fixed")
        
        if models_dir.exists():
            fix_ownership_recursive(models_dir, user_info)
            log("INFO", "✓ Models directory ownership fixed")
        
        show_progress_complete("OK")
        
        log("INFO", "Zonos installation completed successfully!")
        log("INFO", f"Installation log saved to: {get_log_file_path()}")
        
        sys.stdout.write("\n✅ Zonos installation completed successfully!\n")
        sys.stdout.write(f"   Installation directory: {INSTALL_DIR}\n")
        sys.stdout.write(f"   To run: python {SCRIPT_DIR}/zonos.py run\n\n")
        sys.stdout.flush()
        
    except Exception as e:
        log("ERROR", f"Installation failed: {e}")
        sys.stdout.write(f"\n❌ Installation failed: {e}\n")
        sys.stdout.flush()
        raise
    finally:
        close_logging()


def show_help() -> None:
    """Show help information"""
    help_text = """
Usage: python zonos.py [COMMAND]

Commands:
    install          Install Zonos (default)
    run              Run Zonos with selected Gradio interface
    download-models  Download Zonos models only
    verify-models    Verify integrity of downloaded models
    update           Check for and apply updates to repository and models
    uninstall        Completely remove Zonos installation
    setup-env        Configure environment variables only
    help             Show this help message

Examples:
    python zonos.py                   # Install Zonos
    python zonos.py install           # Install Zonos
    python zonos.py run               # Run Zonos (choose interface)
    python zonos.py download-models   # Download models only
    python zonos.py verify-models     # Verify model integrity
    python zonos.py update            # Check and apply updates
    python zonos.py uninstall         # Remove Zonos completely
    python zonos.py setup-env         # Configure environment variables
    python zonos.py help              # Show help

Running Zonos:
    The run command will:
    - Discover available Gradio interfaces in Gradio_InterfacePY_Types/
    - Present a menu of interface types to choose from
    - Configure environment variables automatically
    - Launch the selected interface with proper GPU settings

Model Storage:
    Downloaded models are stored in: ./zonos_download_models/
    This directory is created relative to the script location.
    
Model Verification:
    Models are verified using SHA256 hashes to prevent re-downloading.
    Verification data is stored in: ./zonos_download_models/model_verification.json

Update System:
    The update command checks for:
    - Repository updates from GitHub (new commits)
    - Model updates (verification failures or new versions)
    - Prompts user to choose what to update
    - Updates dependencies automatically with repository

Uninstallation:
    The uninstall command will remove:
    - Zonos repository and virtual environment
    - All downloaded models and cache files
    - Model verification data
    - Environment variables (current session only)
    Note: Requires double confirmation for safety.

Environment Variables:
    The script configures the following environment variables:
    - CUDA settings (CUDA_VISIBLE_DEVICES, CUDA_DEVICE_ORDER)
    - PyTorch optimization settings
    - Memory management (OMP, MKL, NumExpr, OpenBLAS threads)
    - Hugging Face cache directories (points to model download dir)
    - Python optimization flags

File Ownership and Permissions:
    The script automatically ensures that all created files and directories
    have proper ownership set to the user executing the script. This includes:
    - Repository files and directories
    - Downloaded models and cache files
    - Virtual environment files
    - Configuration and verification files
    On Unix-like systems, proper file permissions are also set (755 for
    directories, 644 for files). On Windows, ownership management is handled
    by the operating system and is not modified.

Logging:
    The script automatically creates detailed log files for different operations:
    - zonos_install.log: Installation process logging
    - zonos_execution.log: Runtime and execution logging
    - zonos_models.log: Model download operations
    - zonos_verification.log: Model verification operations
    - zonos_update.log: Update operations
    - zonos_uninstall.log: Uninstallation operations
    - zonos_environment.log: Environment setup operations
    
    Log files are stored in the same directory as the script and include:
    - Detailed timestamps and function information
    - User and system information
    - Command execution details
    - Error messages and stack traces
    - Log rotation (10MB max size, 3 backup files)
    """
    print(help_text)


def discover_gradio_interfaces() -> Dict[str, Path]:
    """Discover available Gradio interface types"""
    gradio_base_dir = INSTALL_DIR / REPO_NAME / "Gradio_InterfacePY_Types"
    interfaces = {}
    
    if not gradio_base_dir.exists():
        return interfaces
    
    # Look for gradio_interface.py files in subdirectories
    for subdir in gradio_base_dir.iterdir():
        if subdir.is_dir():
            gradio_file = subdir / "gradio_interface.py"
            if gradio_file.exists():
                # Use the subdirectory name as the interface type
                interface_name = subdir.name
                interfaces[interface_name] = gradio_file
    
    return interfaces


def run_zonos() -> None:
    """Run Zonos with a selected Gradio interface"""
    # Setup execution logging
    setup_logging("execution")
    ensure_console_output()
    
    show_progress("Starting Zonos run process")
    log("INFO", "Proceeding with uninstallation...")
    uninstall_errors = []

    # Remove Zonos repository
    repo_path = INSTALL_DIR / REPO_NAME
    if repo_path.exists():
        try:
            shutil.rmtree(repo_path)
            log("INFO", f"Removed repository: {repo_path}")
        except Exception as e:
            log("ERROR", f"Failed to remove repository: {e}")
            uninstall_errors.append(f"Repository: {e}")
    else:
        log("INFO", "Zonos repository not found (already removed).")

    # Remove models directory
    models_dir = SCRIPT_DIR / MODELS_DOWNLOAD_DIR
    if models_dir.exists():
        try:
            shutil.rmtree(models_dir)
            log("INFO", f"Removed models directory: {models_dir}")
        except Exception as e:
            log("ERROR", f"Failed to remove models directory: {e}")
            uninstall_errors.append(f"Models directory: {e}")
    else:
        log("INFO", "Models directory not found (already removed).")

    # Clean up environment variables (only for current session)
    log("INFO", "Cleaning up environment variables for current session...")
    env_vars_to_clean = [
        'CUDA_VISIBLE_DEVICES', 'CUDA_DEVICE_ORDER', 'TORCH_CUDA_ARCH_LIST',
        'PYTORCH_CUDA_ALLOC_CONF', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
        'NUMEXPR_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'CUDA_LAUNCH_BLOCKING',
        'CUDA_CACHE_DISABLE', 'NCCL_DEBUG', 'PYTHONUNBUFFERED',
        'PYTHONDONTWRITEBYTECODE', 'TOKENIZERS_PARALLELISM', 'WANDB_DISABLED',
        'MALLOC_TRIM_THRESHOLD_', 'MALLOC_MMAP_THRESHOLD_'
    ]
    cleaned_vars = 0
    for var_name in env_vars_to_clean:
        if var_name in os.environ:
            del os.environ[var_name]
            cleaned_vars += 1
    if cleaned_vars > 0:
        log("INFO", f"Cleaned up {cleaned_vars} environment variables.")
    else:
        log("INFO", "No environment variables needed cleaning.")

    # Remove any leftover cache directories that might have been created
    cache_dirs_to_check = [
        SCRIPT_DIR / "transformers",
        SCRIPT_DIR / "datasets", 
        SCRIPT_DIR / ".cache",
        Path.home() / ".cache" / "huggingface" / "transformers",
    ]
    for cache_dir in cache_dirs_to_check:
        try:
            if cache_dir.exists():
                shutil.rmtree(cache_dir)
                log("INFO", f"Removed cache directory: {cache_dir}")
        except Exception as e:
            log("WARN", f"Failed to remove cache directory {cache_dir}: {e}")
            uninstall_errors.append(f"Cache {cache_dir}: {e}")

    # Summary
    print("\nUninstallation summary:")
    if uninstall_errors:
        print("Some items could not be removed:")
        for err in uninstall_errors:
            print(f"  - {err}")
        log("WARN", f"Uninstallation completed with errors: {uninstall_errors}")
    else:
        print("All Zonos files and directories removed successfully.")
        log("INFO", "Uninstallation completed successfully.")
        print(f"CUDA_DEVICE_ORDER={cuda_order}")
        
        log("INFO", f"Environment - CUDA_VISIBLE_DEVICES: {cuda_device}")
        log("INFO", f"Environment - CUDA_DEVICE_ORDER: {cuda_order}")
        
        # Check if we have GPU info
        try:
            import torch
            if torch.cuda.is_available():
                device_name = torch.cuda.get_device_name(0)
                print(f"GPU Device: {device_name}")
                log("INFO", f"GPU Device available: {device_name}")
                log("INFO", f"CUDA version: {torch.version.cuda}")
            else:
                print("GPU: Not available or not detected")
                log("WARN", "GPU not available or not detected")
        except ImportError:
            print("GPU: Cannot check (torch not available)")
            log("WARN", "Cannot check GPU - torch not available")
        
        print(f"\nStarting Zonos with {selected_interface} interface...")
        print("=" * 60)
        
        # Change to repository directory
        try:
            log("INFO", f"Changing to repository directory: {repo_path}")
            os.chdir(repo_path)
        except OSError as e:
            log("ERROR", f"Failed to navigate to repository directory: {e}")
            sys.exit(1)
        
        # Prepare the command
        uv_path = "./bin/uv"
        if os.name == 'nt':  # Windows
            uv_path = "./Scripts/uv.exe"
        
        # Get relative path from repo root to the gradio interface
        relative_path = selected_path.relative_to(repo_path)
        
        # Construct and run the command
        command = [uv_path, "run", str(relative_path)]
        
        log("INFO", f"Executing command: {' '.join(command)}")
        log("INFO", f"Selected interface: {selected_interface}")
        log("INFO", f"Interface path: {relative_path}")
        log("INFO", f"Execution log saved to: {get_log_file_path()}")
        
        # Close logging before exec (so file is properly closed)
        close_logging()
        
        try:
            # Use exec-like behavior - replace current process
            if os.name == 'nt':
                # On Windows, use subprocess with proper handling
                result = subprocess.run(command, cwd=repo_path)
                sys.exit(result.returncode)
            else:
                # On Unix-like systems, use exec to replace the process
                os.execv(shutil.which(command[0]) or command[0], command)
        except FileNotFoundError:
            # Reopen logging for error reporting
            setup_logging("execution")
            log("ERROR", f"Could not find command: {command[0]}")
            log("ERROR", "Make sure the virtual environment is properly set up")
            close_logging()
            sys.exit(1)
        except Exception as e:
            # Reopen logging for error reporting
            setup_logging("execution")
            log("ERROR", f"Failed to run Zonos: {e}")
            close_logging()
            sys.exit(1)
            
    except Exception as e:
        log("ERROR", f"Run process failed: {e}")
        raise
    finally:
        # Ensure logging is closed if we haven't already
        try:
            close_logging()
        except:
            pass


# =============================================================================
# MAIN SCRIPT EXECUTION
# =============================================================================

def main() -> None:
    """Main function"""
    print("======================================")
    print("    Zonos Installation Script")
    print("======================================")
    print()
    
    parser = argparse.ArgumentParser(description="Zonos Installation and Management Script")
    parser.add_argument("command", nargs='?', default="install", 
                       choices=["install", "run", "download-models", "verify-models", "update", "uninstall", "setup-env", "help"],
                       help="Command to execute (default: install)")
    
    args = parser.parse_args()
    
    try:
        if args.command == "install":
            install_zonos()
        elif args.command == "run":
            run_zonos()
        elif args.command == "download-models":
            # Setup logging for model download
            setup_logging("models")
            log("INFO", "Starting model download process...")
            
            # Change to the Zonos repository directory for model download
            repo_path = INSTALL_DIR / REPO_NAME
            if repo_path.exists():
                try:
                    os.chdir(repo_path)
                    download_models()
                    log("INFO", f"Model download log saved to: {get_log_file_path()}")
                except OSError:
                    log("ERROR", "Failed to navigate to repository directory")
                    sys.exit(1)
                finally:
                    close_logging()
            else:
                log("ERROR", "Zonos repository not found. Please run 'install' command first.")
                close_logging()
                sys.exit(1)
        elif args.command == "verify-models":
            # Setup logging for model verification
            setup_logging("verification")
            verify_models()
            log("INFO", f"Verification log saved to: {get_log_file_path()}")
            close_logging()
        elif args.command == "update":
            # Setup logging for updates
            setup_logging("update")
            update_zonos()
            log("INFO", f"Update log saved to: {get_log_file_path()}")
            close_logging()
        elif args.command == "uninstall":
            # Setup logging for uninstall
            setup_logging("uninstall")
            uninstall_zonos()
            log("INFO", f"Uninstall log saved to: {get_log_file_path()}")
            close_logging()
        elif args.command == "setup-env":
            # Setup logging for environment setup
            setup_logging("environment")
            setup_environment_variables()
            log("INFO", "Environment setup completed!")
            log("INFO", f"Environment setup log saved to: {get_log_file_path()}")
            close_logging()
        elif args.command == "help":
            show_help()
        else:
            log("ERROR", f"Unknown command: {args.command}")
            show_help()
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nOperation cancelled by user.")
        try:
            close_logging()
        except:
            pass
        sys.exit(1)
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        try:
            if _logger:
                log("ERROR", f"Unexpected error in main: {e}")
            close_logging()
        except:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main()
