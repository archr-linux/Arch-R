#!/bin/bash
#==============================================================================
# Arch R - Flash Mainline U-Boot to Clone SD Card
#==============================================================================
# Flashes mainline U-Boot binaries to an existing Arch R SD card for clones.
# Does NOT touch partitions or rootfs — only U-Boot area.
#
# Also creates a minimal boot.scr for mainline U-Boot (distro boot).
#
# Usage:
#   ./flash-uboot-clone.sh /dev/sdX
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[FLASH-CLONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[FLASH-CLONE] WARNING:${NC} $1"; }
error() { echo -e "${RED}[FLASH-CLONE] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "sd|mmcblk" || true
    exit 1
fi

DEVICE="$1"

if [ ! -b "$DEVICE" ]; then
    error "Device not found: $DEVICE"
fi

# Safety check
if mount | grep -q "^${DEVICE}"; then
    warn "Device $DEVICE has mounted partitions:"
    mount | grep "^${DEVICE}" || true
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

#------------------------------------------------------------------------------
# Verify binaries
#------------------------------------------------------------------------------
BUILD_DIR="$SCRIPT_DIR/bootloader/u-boot-clone-build"

for f in "$BUILD_DIR/idbloader.img" "$BUILD_DIR/uboot.img" "$BUILD_DIR/trust.img"; do
    [ -f "$f" ] || error "Missing: $f (run build-uboot-clone.sh first)"
done

log "Device: $DEVICE"
log "Binaries: $BUILD_DIR"
log ""
log "Will flash:"
log "  idbloader.img → sector 64    ($(du -h "$BUILD_DIR/idbloader.img" | cut -f1))"
log "  uboot.img     → sector 16384 ($(du -h "$BUILD_DIR/uboot.img" | cut -f1))"
log "  trust.img     → sector 24576 ($(du -h "$BUILD_DIR/trust.img" | cut -f1))"
log ""

read -p "Flash to $DEVICE? (y/N) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 1

#------------------------------------------------------------------------------
# Flash U-Boot binaries (raw sectors)
#------------------------------------------------------------------------------
log "Flashing idbloader.img..."
pkexec dd if="$BUILD_DIR/idbloader.img" of="$DEVICE" bs=512 seek=64 conv=sync,noerror,notrunc 2>/dev/null

log "Flashing uboot.img..."
pkexec dd if="$BUILD_DIR/uboot.img" of="$DEVICE" bs=512 seek=16384 conv=sync,noerror,notrunc 2>/dev/null

log "Flashing trust.img..."
pkexec dd if="$BUILD_DIR/trust.img" of="$DEVICE" bs=512 seek=24576 conv=sync,noerror,notrunc 2>/dev/null

log "U-Boot binaries flashed"

#------------------------------------------------------------------------------
# Create boot.scr on BOOT partition
#------------------------------------------------------------------------------
BOOT_PART="${DEVICE}1"
if [ ! -b "$BOOT_PART" ]; then
    BOOT_PART="${DEVICE}p1"
fi

if [ ! -b "$BOOT_PART" ]; then
    warn "BOOT partition not found — boot.scr NOT created"
else
    MOUNT_TMP=$(mktemp -d)
    pkexec mount "$BOOT_PART" "$MOUNT_TMP"

    # Create boot.scr from boot.ini (strip BSP-specific commands)
    MKIMAGE="$SCRIPT_DIR/bootloader/u-boot-mainline/tools/mkimage"
    if [ -x "$MKIMAGE" ] && [ -f "$MOUNT_TMP/boot.ini" ]; then
        log "Creating boot.scr from boot.ini..."
        TMP_SCR=$(mktemp)
        # Strip 'odroidgoa-uboot-config' (BSP command, not in mainline)
        grep -v '^odroidgoa-uboot-config' "$MOUNT_TMP/boot.ini" > "$TMP_SCR"
        "$MKIMAGE" -T script -d "$TMP_SCR" "$MOUNT_TMP/boot.scr" 2>/dev/null && \
            log "boot.scr created" || \
            warn "boot.scr creation failed"
        rm -f "$TMP_SCR"
    fi

    log "BOOT partition contents:"
    ls "$MOUNT_TMP/" | head -20

    pkexec umount "$MOUNT_TMP"
    rmdir "$MOUNT_TMP"
fi

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------
sync
log ""
log "=== Mainline U-Boot flashed to $DEVICE ==="
log ""
log "This is MAINLINE U-Boot (not BSP). Key differences:"
log "  - Uses go2.c board detection (not hwrev.c)"
log "  - Boots via boot.scr / extlinux.conf (not boot.ini directly)"
log "  - Display: mainline DRM (may not show boot logo)"
log ""
log "If boot fails, restore working clone U-Boot:"
log "  pkexec dd if=bootloader/u-boot-clone-working/uboot.img of=$DEVICE bs=512 seek=16384 conv=notrunc"
log "  pkexec dd if=bootloader/u-boot-clone-working/idbloader.img of=$DEVICE bs=512 seek=64 conv=notrunc"
log "  pkexec dd if=bootloader/u-boot-clone-working/trust.img of=$DEVICE bs=512 seek=24576 conv=notrunc"
