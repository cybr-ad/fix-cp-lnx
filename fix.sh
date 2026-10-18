#!/bin/bash

# =================================================================
# Advanced VirtualBox Guest Additions & Copy-Paste Fixer (v2)
# =================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' 

echo -e "${YELLOW}=== Starting Advanced VirtualBox Copy-Paste Fixer ===${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script with sudo.${NC}"
  exit 1
fi

# 1. Clean up old/zombie processes
echo -e "\n${YELLOW}[1/6] Cleaning up existing VBox processes...${NC}"
pkill -9 VBoxClient 2>/dev/null
pkill -9 VBoxService 2>/dev/null

# 2. Install Dependencies
echo -e "\n${YELLOW}[2/6] Installing dependencies...${NC}"
if command -v apt-get > /dev/null; then
    apt-get update -y
    apt-get remove -y virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms 2>/dev/null
    apt-get install -y build-essential dkms linux-headers-$(uname -r)
elif command -v dnf > /dev/null; then
    dnf install -y kernel-devel kernel-headers gcc make dkms bzip2 perl
elif command -v pacman > /dev/null; then
    pacman -S --noconfirm base-devel linux-headers dkms
else
    echo -e "${RED}Unknown package manager. Please install build tools manually.${NC}"
    exit 1
fi

# 3. Mount and Install Guest Additions
echo -e "\n${YELLOW}[3/6] Locating and installing Guest Additions...${NC}"
MOUNT_DIR="/media/cdrom"
mkdir -p "$MOUNT_DIR"

CD_DEV=""
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if [ -b "$dev" ]; then CD_DEV="$dev"; break; fi
done

if [ -z "$CD_DEV" ]; then
    echo -e "${RED}Error: Could not find CD-ROM device.${NC}"
    echo -e "${YELLOW}Did you click 'Devices > Insert Guest Additions CD image...' in VirtualBox?${NC}"
else
    umount "$MOUNT_DIR" 2>/dev/null
    mount -o ro "$CD_DEV" "$MOUNT_DIR"
    
    if [ -f "$MOUNT_DIR/VBoxLinuxAdditions.run" ]; then
        cd "$MOUNT_DIR"
        chmod +x VBoxLinuxAdditions.run
        ./VBoxLinuxAdditions.run --nox11
    else
        echo -e "${YELLOW}Guest Additions CD not found. Skipping installation, assuming it's already installed.${NC}"
    fi
fi

# 4. Force Load Kernel Modules (Fixes "not running" errors)
echo -e "\n${YELLOW}[4/6] Forcing VirtualBox kernel modules to load...${NC}"
modprobe vboxguest
modprobe vboxsf
modprobe vboxvideo

if lsmod | grep -q vboxguest; then
    echo -e "${GREEN}Kernel modules loaded successfully.${NC}"
else
    echo -e "${RED}Warning: Kernel modules failed to load. Secure Boot might be blocking them.${NC}"
fi

# 5. Enforce Systemd Services
echo -e "\n${YELLOW}[5/6] Starting VirtualBox background services...${NC}"
systemctl enable vboxadd-service 2>/dev/null
systemctl start vboxadd-service 2>/dev/null
systemctl restart vboxadd-service 2>/dev/null

# 6. Detect Display Server & Start VBoxClient
echo -e "\n${YELLOW}[6/6] Starting VBoxClient for your display server...${NC}"
# Detect Wayland vs X11
if [ -n "$SUDO_USER" ]; then
    USER_SESSION=$(sudo -u "$SUDO_USER" loginctl show-session $(sudo -u "$SUDO_USER" loginctl | grep "$SUDO_USER" | awk '{print $1}' | head -n 1) -p Type 2>/dev/null | cut -d'=' -f2)
else
    USER_SESSION="x11" # Default fallback
fi

if [[ "$USER_SESSION" == *"wayland"* ]]; then
    echo -e "${YELLOW}Wayland session detected!${NC}"
    echo "Starting VBoxClient with Wayland flags..."
    # Force X11 clipboard mapping for Wayland
    sudo -u "$SUDO_USER" nohup VBoxClient --clipboard >/dev/null 2>&1 &
else
    echo -e "X11 session detected. Starting standard VBoxClient..."
    sudo -u "$SUDO_USER" nohup VBoxClient-all >/dev/null 2>&1 &
fi

# Final verification
sleep 2
if pgrep -x "VBoxClient" > /dev/null; then
    echo -e "\n${GREEN}=== SUCCESS: VBoxClient is now running! ===${NC}"
else
    echo -e "\n${RED}=== ERROR: VBoxClient still not running. ===${NC}"
    echo -e "${YELLOW}If you are on Wayland, try logging out and switching to 'Ubuntu on Xorg' at the login screen.${NC}"
fi

echo -e "\n${YELLOW}A reboot is highly recommended. Type: sudo reboot${NC}"
echo -e "${RED}REMINDER:${NC} Ensure VM Settings > General > Advanced > Shared Clipboard is set to 'Bidirectional'.${NC}"
