#!/bin/bash

#==============================================================================
# Arch R - Flash Custom U-Boot to SD Card
#==============================================================================
# Flashes custom U-Boot binaries + display DTBs to an existing Arch R SD card.
# Does NOT touch partitions or rootfs — only U-Boot area + BOOT partition DTBs.
#
# Usage:
#   ./flash-uboot.sh /dev/sdX
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[FLASH]${NC} $1"; }
warn() { echo -e "${YELLOW}[FLASH] WARNING:${NC} $1"; }
error() { echo -e "${RED}[FLASH] ERROR:${NC} $1"; exit 1; }

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

# Safety: refuse whole-disk devices that look like system disks
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
SDFUSE="$SCRIPT_DIR/bootloader/u-boot-rk3326/sd_fuse"
DTS_DIR="$SCRIPT_DIR/bootloader/u-boot-rk3326/arch/arm/dts"

for f in "$SDFUSE/idbloader.img" "$SDFUSE/uboot.img" "$SDFUSE/trust.img"; do
    [ -f "$f" ] || error "Missing: $f"
done

for f in "$DTS_DIR/r36s-uboot.dtb" "$DTS_DIR/r36-uboot.dtb"; do
    [ -f "$f" ] || error "Missing: $f"
done

log "Device: $DEVICE"
log "Binaries: $SDFUSE"
log ""
log "Will flash:"
log "  idbloader.img → sector 64    ($(du -h "$SDFUSE/idbloader.img" | cut -f1))"
log "  uboot.img     → sector 16384 ($(du -h "$SDFUSE/uboot.img" | cut -f1))"
log "  trust.img     → sector 24576 ($(du -h "$SDFUSE/trust.img" | cut -f1))"
log "  r36s-uboot.dtb + r36-uboot.dtb → BOOT partition"
log ""

read -p "Flash to $DEVICE? (y/N) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 1

#------------------------------------------------------------------------------
# Flash U-Boot binaries (raw sectors)
#------------------------------------------------------------------------------
log "Flashing idbloader.img..."
pkexec dd if="$SDFUSE/idbloader.img" of="$DEVICE" bs=512 seek=64 conv=sync,noerror,notrunc 2>/dev/null

log "Flashing uboot.img..."
pkexec dd if="$SDFUSE/uboot.img" of="$DEVICE" bs=512 seek=16384 conv=sync,noerror,notrunc 2>/dev/null

log "Flashing trust.img..."
pkexec dd if="$SDFUSE/trust.img" of="$DEVICE" bs=512 seek=24576 conv=sync,noerror,notrunc 2>/dev/null

log "U-Boot binaries flashed"

#------------------------------------------------------------------------------
# Copy display DTBs to BOOT partition
#------------------------------------------------------------------------------
BOOT_PART="${DEVICE}1"
if [ ! -b "$BOOT_PART" ]; then
    # Try mmcblk style (p1)
    BOOT_PART="${DEVICE}p1"
fi

if [ ! -b "$BOOT_PART" ]; then
    warn "BOOT partition not found ($BOOT_PART) — display DTBs NOT copied"
    warn "Copy manually: r36s-uboot.dtb + r36-uboot.dtb to BOOT partition"
else
    MOUNT_TMP=$(mktemp -d)
    pkexec mount "$BOOT_PART" "$MOUNT_TMP"

    pkexec cp "$DTS_DIR/r36s-uboot.dtb" "$MOUNT_TMP/"
    pkexec cp "$DTS_DIR/r36-uboot.dtb" "$MOUNT_TMP/"

    # Verify
    log "BOOT partition contents:"
    ls -la "$MOUNT_TMP/"*.dtb 2>/dev/null || true

    pkexec umount "$MOUNT_TMP"
    rmdir "$MOUNT_TMP"

    log "Display DTBs copied to BOOT partition"
fi

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------
sync
log ""
log "=== Custom U-Boot flashed to $DEVICE ==="
log ""
log "Test on R36S original → should detect eMMC → r36s-uboot.dtb → logo"
log "Test on R36S clone    → no eMMC → r36-uboot.dtb → logo"
log ""
log "If boot fails (red LED blink), restore working U-Boot:"
log "  Original: bootloader/u-boot-r36s-working/"
log "  Clone:    bootloader/u-boot-clone-working/"
