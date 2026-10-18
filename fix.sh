#!/bin/bash

# =================================================================
# Intelligent VirtualBox Guest Additions & Copy-Paste Fixer
# Run this script with sudo: sudo ./fix_vbox.sh
# =================================================================

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Starting VirtualBox Copy-Paste Fixer ===${NC}"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script with sudo.${NC}"
  exit 1
fi

# 2. Detect Linux Distribution and Install Dependencies
echo -e "\n${YELLOW}[1/5] Detecting OS and installing dependencies...${NC}"
if command -v apt-get > /dev/null; then
    echo "Detected Debian/Ubuntu based system."
    apt-get update -y
    # Remove conflicting OS-level packages first
    apt-get remove -y virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms 2>/dev/null
    apt-get install -y build-essential dkms linux-headers-$(uname -r)
elif command -v dnf > /dev/null; then
    echo "Detected Fedora/RHEL based system."
    dnf install -y kernel-devel kernel-headers gcc make dkms bzip2 perl
elif command -v pacman > /dev/null; then
    echo "Detected Arch Linux based system."
    pacman -S --noconfirm base-devel linux-headers dkms
else
    echo -e "${RED}Unknown package manager. Please install 'build-essential', 'dkms', and 'linux-headers' manually.${NC}"
    exit 1
fi

# 3. Find and Mount the Guest Additions CD
echo -e "\n${YELLOW}[2/5] Locating and mounting Guest Additions CD...${NC}"
MOUNT_DIR="/media/cdrom"
mkdir -p "$MOUNT_DIR"

# Try to find the CD-ROM device
CD_DEV=""
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if [ -b "$dev" ]; then
        CD_DEV="$dev"
        break
    fi
done

if [ -z "$CD_DEV" ]; then
    echo -e "${RED}Error: Could not find a CD-ROM device.${NC}"
    echo -e "${YELLOW}Did you click 'Devices > Insert Guest Additions CD image...' in the VirtualBox menu?${NC}"
    exit 1
fi

echo "Found CD device at $CD_DEV. Mounting..."
umount "$MOUNT_DIR" 2>/dev/null # Unmount if already mounted
mount -o ro "$CD_DEV" "$MOUNT_DIR"

if [ ! -f "$MOUNT_DIR/VBoxLinuxAdditions.run" ]; then
    echo -e "${RED}Error: VBoxLinuxAdditions.run not found on the CD.${NC}"
    echo -e "${YELLOW}Make sure the Guest Additions CD is inserted in the VirtualBox menu.${NC}"
    exit 1
fi

# 4. Install Guest Additions
echo -e "\n${YELLOW}[3/5] Installing Guest Additions (this may take a minute)...${NC}"
cd "$MOUNT_DIR"
chmod +x VBoxLinuxAdditions.run
./VBoxLinuxAdditions.run --nox11

# 5. Restart the Clipboard Services
echo -e "\n${YELLOW}[4/5] Restarting clipboard services...${NC}"
pkill VBoxClient 2>/dev/null
systemctl restart vboxadd-service 2>/dev/null

# 6. Check Display Server (X11 vs Wayland) and Start Clipboard
echo -e "\n${YELLOW}[5/5] Verifying Clipboard Client...${NC}"
SESSION_TYPE=$(loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p Type 2>/dev/null | cut -d'=' -f2)

if [[ "$SESSION_TYPE" == *"wayland"* ]]; then
    echo -e "${YELLOW}Note: Wayland session detected. Wayland handles clipboard differently and can be buggy in VirtualBox.${NC}"
    echo "Attempting to start X11 fallback clipboard..."
    nohup VBoxClient --clipboard >/dev/null 2>&1 &
else
    echo "X11 session detected. Starting clipboard daemon..."
    nohup VBoxClient-all >/dev/null 2>&1 &
fi

echo -e "\n${GREEN}=== Script Finished! ===${NC}"
echo -e "A reboot is highly recommended. Type: ${YELLOW}sudo reboot${NC}"
echo -e "${RED}CRITICAL REMINDER:${NC} Before you test copy-paste, you MUST:"
echo "1. Shut down the VM completely."
echo "2. Go to VM Settings > General > Advanced."
echo "3. Set 'Shared Clipboard' and 'Drag'n'Drop' to 'Bidirectional'."
echo "4. Boot the VM back up."