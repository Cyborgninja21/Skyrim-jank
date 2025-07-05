#!/usr/bin/env bash
# Log monitoring script for Skyrim AI Framework

set -euo pipefail

LINUX_USER="${LINUX_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

# Log file paths
LOG_FILES=(
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/error.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/log/apache2/other_vhosts_access.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/debugStream.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/context_sent_to_llm.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_from_llm.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/output_to_plugin.log"
    "/home/${LINUX_USER}/docker_env/skyrimai_www/var/www/html/HerikaServer/log/minai.log"
)

echo "=== Skyrim AI Framework Log Monitor ==="
echo "Press Ctrl+C to stop monitoring"
echo

# Monitor Docker container logs
echo "Starting Docker container log monitoring..."
sudo docker logs -f skyrimaiframework 2>&1 &
DOCKER_PID=$!

# Monitor individual log files
echo "Starting log file monitoring..."
for log_file in "${LOG_FILES[@]}"; do
    if [[ -f "$log_file" ]]; then
        echo "Monitoring: $(basename "$log_file")"
        tail -f "$log_file" 2>&1 | sed "s/^/[$(basename "$log_file")]: /" &
    else
        echo "Log file not found: $log_file" >&2
    fi
done

# Wait for all background processes
wait
