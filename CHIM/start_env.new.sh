#!/bin/bash
# DwemerDistro Environment Startup Script
# Refactored for clarity and best practices
set -euo pipefail
IFS=$'\n\t'

/usr/local/bin/print_logo


# Clean /tmp
find /tmp -type f -mtime +7 -delete
find /tmp/ -type d -mtime +7 -exec rm -rf {} + &>/dev/null

# Check if a port is open (service started)
check_port() {
	local port="$1"
	local retries=30
	local wait_time=2
	local attempt=1
	while (( attempt <= retries )); do
		if netstat -lNnp 2>/dev/null | grep -q ":$port"; then
			echo " started "
			return 0
		else
			echo -ne "."
			if (( attempt < retries )); then
				sleep "$wait_time"
			fi
		fi
		((attempt++))
	done
	echo "not started"
	return 1
}

# Start a service if its script exists
start_service() {
	local name="$1"
	local script_path="$2"
	local port="$3"
	local skip_var="$4"
	if [[ -f "$script_path" ]]; then
		echo -ne "Starting $name "
		su dwemer -c "$script_path"
		check_port "$port"
	else
		echo "Skipping $name (not enabled)"
		eval "$skip_var=1"
	fi
}


# Start Apache/PHP server
echo "Starting Apache/PHP/PGSQL Server"
/etc/init.d/apache2 restart &>/dev/null
/etc/init.d/postgresql restart

# Create symbolic link for Apache error log if it doesn't exist
if [ ! -e "/var/www/html/HerikaServer/log/apache_error.log" ]; then
  mkdir -p /var/www/html/HerikaServer/log/
  ln -sf /var/log/apache2/error.log /var/www/html/HerikaServer/log/apache_error.log
fi


# Initialize service skip variables
L_MINIME=""
L_MIMIC=""
L_MELOTTS=""
L_WHISPER=""
L_XTTSV2=""

start_service "Minime-T5/TXT2VEC service" "/home/dwemer/minime-t5/start.sh" 8082 L_MINIME
start_service "Mimic3 TTS" "/home/dwemer/mimic3/start.sh" 59125 L_MIMIC
start_service "MeloTTS" "/home/dwemer/MeloTTS/start.sh" 8084 L_MELOTTS

# LocalWhisper Server (uses config.yaml as enable check)
if [[ -f "/home/dwemer/remote-faster-whisper/config.yaml" ]]; then
	echo -ne "Starting LocalWhisper Server "
	su dwemer -c "/home/dwemer/remote-faster-whisper/start.sh"
	check_port 9876
else
	echo "Skipping LocalWhisper Server (not enabled)"
	L_WHISPER=1
fi

start_service "CHIM XTTS server" "/home/dwemer/xtts-api-server/start.sh" 8020 L_XTTSV2


echo "Press Enter to shutdown DwemerDistro"

# Get local IP address
ipaddress=$(/usr/local/bin/get_ip)

cat << EOF
=======================================
Download AIAgent.ini under Server Actions!
AIAgent.ini Network Settings:
----------------------------
SERVER=$ipaddress
PORT=8081
PATH=/HerikaServer/comm.php
POLINT=1
----------------------------
DwemerDistro Local IP Address: $ipaddress
CHIM WebServer URL: http://$ipaddress:8081

Running Components:
EOF

[[ -z "$L_MINIME" ]]   && echo "Minime-T5/TXT2VEC API: http://$ipaddress:8082"
[[ -z "$L_WHISPER" ]]  && echo "LocalWhisper API: http://$ipaddress:9876"
[[ -z "$L_XTTSV2" ]]   && echo "CHIM XTTS API: http://$ipaddress:8020"
[[ -z "$L_MIMIC" ]]    && echo "Mimic3 API: http://$ipaddress:59125"
[[ -z "$L_MELOTTS" ]]  && echo "MelotTTS API: http://$ipaddress:8084"

# Open web UI in browser (Windows explorer.exe)
explorer.exe "http://$ipaddress:8081/HerikaServer/ui/index.php" &>/dev/null &

echo "Press Enter to shutdown DwemerDistro"
read -r

# Graceful shutdown
killall -15 -u dwemer || true
/etc/init.d/apache2 stop
/etc/init.d/postgresql stop

echo "DwemerDistro has stopped running"

