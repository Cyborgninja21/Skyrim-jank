# DwemerDistro on Linux Installation Guide

**Credit:** CTD

This guide provides instructions for Linux users who want to use the DwemerDistro mod. While this should work for most setups, you may need to adjust some configurations based on your specific environment.

## Prerequisites

- Docker installed on the PC where you want to run DwemerDistro
- The DwemerDistro can run on a different PC than your gaming machine
- Example setup: Separate laptop with 4c/8t 9th gen Intel CPU and NVIDIA GTX 1650 for XTTS, OpenRouter for LLM

> **Note:** STT functionality has not been tested and may require additional configuration.

## Installation Steps

### 1. Prepare the Archive

1. Unpack the DwemerDistro archive
2. On the PC where you'll be running DwemerDistro, create the directory:

   ```bash
   mkdir -p /home/$(whoami)/docker_build
   ```

3. Copy `DwemerAI4Skyrim3.tar` from the unpacked archive to this directory

### 2. Install NVIDIA Container Runtime (if using NVIDIA GPU)

**For NVIDIA GPU users only:**

- **General Instructions:** Follow the official guide at [NVIDIA Container Toolkit Installation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- **Arch Linux:** Install from the extra repository:

  ```bash
  sudo pacman -S libnvidia-container nvidia-container-toolkit
  ```

- **Ubuntu and other distros:** Follow the instructions in the NVIDIA documentation

### 3. Create and Run the Setup Script

Create a setup script and run it with sudo privileges.

> **Important:** You must fill in the `linux_user` variable in the script. Use your actual username (run `whoami` in terminal if unsure).

### 4. Verify Container Installation

After running the setup script, you should see one of these messages:

- With NVIDIA GPU: `"[INFO] Installing docker service with nvidia support"`
- Without NVIDIA GPU: `"[INFO] Installing docker service without nvidia support"`

Confirm the container is running:

```bash
sudo docker ps | grep -i skyrimaiframework
```

If you see output, the installation was successful.

## Container Configuration

### 1. Enter the Container

```bash
container_id=$(sudo docker ps -a | grep "skyrimaiframework" | cut -f1 -d" ")
sudo docker exec -ti ${container_id} /bin/bash
```

You should now be logged in as root.

### 2. Switch to Dwemer User

```bash
su dwemer
```

### 3. Run Required Scripts

Execute the following scripts (equivalent to running .bat files from the official instructions):

#### a. Update Git Repository

```bash
/usr/local/bin/update_gws
```

#### b. Install Minime Service

```bash
/home/dwemer/minime-t5/ddistro_install.sh
```

- **Configuration:** Choose the CPU option when prompted

#### c. Install Mimic and/or XTTS

**For Mimic3:**

```bash
/home/dwemer/mimic3/ddistro_install.sh
```

- **Configuration:** Choose default when prompted

**For XTTS:**

```bash
/home/dwemer/xtts-api-server/ddistro_install.sh
```

wsl -d  DwemerAI4Skyrim3 -u dwemer -- /home/dwemer/minime-t5/ddistro_install.sh


wsl -d  DwemerAI4Skyrim3 -u dwemer -- /home/dwemer/remote-faster-whisper/ddistro_install.sh

wsl -d  DwemerAI4Skyrim3 -u dwemer -- /home/dwemer/minime-t5/ddistro_install.sh






- **Configuration:** Choose default for CPU, or GPU if you installed the NVIDIA version

## Network Configuration

### Configure Plugin Settings

You need to enter your PC's local IP address in the plugin configuration file.

**Example Network Setup:**

- Main laptop IP: `192.168.1.51`
- DwemerDistro laptop IP: `192.168.1.101`

### Sample AIAgent.ini Configuration

```ini
SERVER=192.168.1.101
PORT=8081
PATH=/HerikaServer/comm.php
POLINT=1
```

### Access Configuration Interface

The configuration interface is available at: `http://192.168.1.101:8081`

Replace `192.168.1.101` with your DwemerDistro server's IP address.