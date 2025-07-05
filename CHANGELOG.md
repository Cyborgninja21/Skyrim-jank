# Changelog

## [Unreleased] - 2025-07-05

### Major Refactor of `Dockersetup.sh`
- Added `set -euo pipefail` for strict error handling and script robustness.
- Parameterized all user, group, and path variables for flexibility and maintainability.
- Introduced utility functions for repeated tasks:
  - `require_cmd` to check for required commands before proceeding.
  - `setup_dir_from_tar` for extracting specific directories from tarballs.
  - `setup_dir` for generic directory creation and permission setting.
  - `set_owner` for setting directory ownership.
- Replaced all `cd` and `tar` combinations with `tar -C` for safer extraction.
- Quoted all variable expansions to prevent word splitting and globbing issues.
- Used Docker's built-in filters for reliable image and container existence checks.
- Consolidated Docker run arguments into a single array, reducing code duplication.
- Added logic to detect NVIDIA runtime and GPU, and conditionally add NVIDIA options to the Docker run command.
- Improved error and info messaging throughout the script.
- Allowed overriding of key variables (e.g., `LINUX_USER`, `WSL_TAR_IMAGE_PATH`) via environment variables.
- Updated all Docker container removal instructions to use the correct `docker container rm` command.
- Improved script readability and maintainability with clear section headers and comments.

---
This changelog documents the major improvements and refactorings made to the Docker setup script for the Skyrim AI Framework. Future changes should be added to this file with dates and descriptions.
