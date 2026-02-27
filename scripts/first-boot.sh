#!/bin/bash

#==============================================================================
# Arch R - First Boot Setup Script
#==============================================================================
# Runs on first boot to:
# 1. Create ROMS partition (FAT32) with remaining SD card space
# 2. Generate SSH keys and machine-id
# 3. Configure RetroArch and EmulationStation
# 4. Create ROM directories
#==============================================================================

FIRST_BOOT_FLAG="/var/lib/archr/.first-boot-done"
LOG_FILE="/var/log/first-boot.log"

# Log all output for debugging
exec > >(tee -a "$LOG_FILE") 2>&1

if [ -f "$FIRST_BOOT_FLAG" ]; then
    echo "First boot already completed, skipping"
    exit 0
fi

echo "=== Arch R First Boot Setup === ($(date))"

#------------------------------------------------------------------------------
# Detect SD card device
#------------------------------------------------------------------------------
ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SOURCE" | head -1)
ROOT_DISK="/dev/${ROOT_DISK}"

echo "Root device: $ROOT_SOURCE"
echo "SD card: $ROOT_DISK"

#------------------------------------------------------------------------------
# Create ROMS partition (partition 3) if it doesn't exist
#------------------------------------------------------------------------------
ROMS_PART="${ROOT_DISK}p3"
ROMS_OK=false

if ! lsblk "$ROMS_PART" &>/dev/null; then
    echo "Creating ROMS partition..."

    # Parse partition info using sfdisk dump format (reliable, no column alignment issues)
    LAST_INFO=$(sfdisk -d "$ROOT_DISK" 2>/dev/null | grep '^/dev' | tail -1)
    PART_START=$(echo "$LAST_INFO" | grep -o 'start=[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    PART_SIZE=$(echo "$LAST_INFO" | grep -o 'size=[[:space:]]*[0-9]*' | grep -o '[0-9]*')

    if [ -n "$PART_START" ] && [ -n "$PART_SIZE" ]; then
        LAST_END=$((PART_START + PART_SIZE))
        DISK_SECTORS=$(blockdev --getsz "$ROOT_DISK" 2>/dev/null)

        echo "  Last partition ends at sector $LAST_END, disk has $DISK_SECTORS sectors"

        if [ -n "$DISK_SECTORS" ] && [ "$LAST_END" -lt "$DISK_SECTORS" ]; then
            echo "${LAST_END},+,0c" | sfdisk --force --append "$ROOT_DISK" 2>&1 || \
            echo ",,0c" | sfdisk --force --append "$ROOT_DISK" 2>&1 || \
            echo "  ERROR: sfdisk --append failed"
        else
            echo "  ERROR: No free space on disk (last=$LAST_END, total=$DISK_SECTORS)"
        fi
    else
        echo "  WARNING: Could not parse partition table, trying generic append"
        echo ",,0c" | sfdisk --force --append "$ROOT_DISK" 2>&1 || \
        echo "  ERROR: sfdisk --append failed"
    fi

    # Tell kernel about the new partition (try multiple methods)
    partprobe "$ROOT_DISK" 2>/dev/null
    sleep 2

    if ! lsblk "$ROMS_PART" &>/dev/null; then
        # partprobe failed — try partx (more reliable for adding single partitions)
        partx -a "$ROOT_DISK" 2>/dev/null
        sleep 2
    fi

    if ! lsblk "$ROMS_PART" &>/dev/null; then
        # Last resort: blockdev re-read
        blockdev --rereadpt "$ROOT_DISK" 2>/dev/null
        sleep 3
    fi

    if lsblk "$ROMS_PART" &>/dev/null; then
        echo "  Formatting as FAT32..."
        mkfs.vfat -F 32 -n ROMS "$ROMS_PART"
        echo "  ROMS partition created!"
    else
        echo "  WARNING: Partition created in table but kernel can't see it yet"
        echo "  ROMS will be available after reboot"
    fi
else
    echo "  ROMS partition already exists"
    # Ensure it has a FAT32 filesystem with the ROMS label
    if ! blkid "$ROMS_PART" | grep -q 'TYPE="vfat"'; then
        echo "  Formatting existing partition as FAT32..."
        mkfs.vfat -F 32 -n ROMS "$ROMS_PART"
    elif ! blkid "$ROMS_PART" | grep -q 'LABEL="ROMS"'; then
        echo "  Setting label to ROMS..."
        fatlabel "$ROMS_PART" ROMS 2>/dev/null || true
    fi
fi

#------------------------------------------------------------------------------
# Mount ROMS partition and create directories
#------------------------------------------------------------------------------
echo "Setting up ROM directories..."

mkdir -p /roms

if lsblk "$ROMS_PART" &>/dev/null; then
    if ! mountpoint -q /roms; then
        mount "$ROMS_PART" /roms 2>&1 || echo "  WARNING: Could not mount $ROMS_PART"
    fi
fi

if mountpoint -q /roms; then
    ROMS_OK=true

    SYSTEMS=(
        "nes" "snes" "gb" "gbc" "gba" "nds"
        "megadrive" "mastersystem" "gamegear" "genesis" "segacd" "sega32x"
        "n64" "psx" "psp"
        "dreamcast" "saturn"
        "arcade" "mame" "fbneo" "neogeo"
        "atari2600" "atari7800" "atarilynx"
        "pcengine" "pcenginecd" "supergrafx"
        "wonderswan" "wonderswancolor"
        "ngp" "ngpc"
        "virtualboy"
        "scummvm" "dos"
        "ports"
        "bios"
    )

    for sys in "${SYSTEMS[@]}"; do
        mkdir -p "/roms/$sys"
    done

    mkdir -p /roms/saves /roms/states
    echo "  ROM directories created"
else
    echo "  WARNING: /roms not mounted — directories will be created on next boot"
fi

#------------------------------------------------------------------------------
# Generate SSH host keys
#------------------------------------------------------------------------------
echo "Generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

#------------------------------------------------------------------------------
# Set random machine-id
#------------------------------------------------------------------------------
echo "Generating machine ID..."
rm -f /etc/machine-id
systemd-machine-id-setup

#------------------------------------------------------------------------------
# Enable services
#------------------------------------------------------------------------------
echo "Enabling services..."
systemctl enable NetworkManager 2>/dev/null || true

#------------------------------------------------------------------------------
# Configure RetroArch
#------------------------------------------------------------------------------
echo "Configuring RetroArch..."

RA_DIR="/home/archr/.config/retroarch"
mkdir -p "$RA_DIR/cores"
mkdir -p "$RA_DIR/saves"
mkdir -p "$RA_DIR/states"
mkdir -p "$RA_DIR/screenshots"

if [ ! -f "$RA_DIR/retroarch.cfg" ] && [ -f /etc/archr/retroarch.cfg ]; then
    cp /etc/archr/retroarch.cfg "$RA_DIR/retroarch.cfg"
fi

# Set savefile/savestate directories to ROMS partition
sed -i "s|^savefile_directory =.*|savefile_directory = \"/roms/saves\"|" "$RA_DIR/retroarch.cfg" 2>/dev/null || true
sed -i "s|^savestate_directory =.*|savestate_directory = \"/roms/states\"|" "$RA_DIR/retroarch.cfg" 2>/dev/null || true

#------------------------------------------------------------------------------
# Configure EmulationStation
#------------------------------------------------------------------------------
echo "Configuring EmulationStation..."

ES_DIR="/home/archr/.emulationstation"
mkdir -p "$ES_DIR"

# Link system config
if [ ! -f "$ES_DIR/es_systems.cfg" ] && [ -f /etc/emulationstation/es_systems.cfg ]; then
    ln -sf /etc/emulationstation/es_systems.cfg "$ES_DIR/es_systems.cfg"
fi

chown -R archr:archr /home/archr

#------------------------------------------------------------------------------
# Mark first boot complete (only if ROMS partition is working)
#------------------------------------------------------------------------------
if [ "$ROMS_OK" = true ]; then
    mkdir -p "$(dirname "$FIRST_BOOT_FLAG")"
    touch "$FIRST_BOOT_FLAG"
    echo "=== First Boot Setup Complete ==="
else
    echo "=== First Boot Setup Partial — ROMS partition will retry on next boot ==="
fi
