#!/bin/bash

#==============================================================================
# Arch R - U-Boot Build Script for R36S
#==============================================================================
# Builds custom U-Boot with R36S original/clone auto-detection via eMMC probe.
# Cross-compiles for aarch64 (CONFIG_ARM64=y in defconfig).
#
# Custom modifications:
#   - cmd/hwrev.c: R36S detection via eMMC probe (original vs clone)
#   - r36s-uboot.dts: U-Boot display DTB for original (Panel 4-V22 NV3052C)
#   - r36s-clone-uboot.dts: U-Boot display DTB for clone (Type5 NV3052C)
#
# Prerequisites:
#   sudo apt install gcc-aarch64-linux-gnu
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

UBOOT_DIR="$SCRIPT_DIR/bootloader"
UBOOT_REPO="https://github.com/christianhaitian/RG351MP-u-boot"
UBOOT_SRC="$UBOOT_DIR/u-boot-rk3326"
OUTPUT_DIR="$SCRIPT_DIR/output/bootloader"

# U-Boot for RK3326 is aarch64 (CONFIG_ARM64=y in defconfig)
CROSS_COMPILE="aarch64-linux-gnu-"

log "=== Arch R - U-Boot Builder (Custom R36S) ==="

#------------------------------------------------------------------------------
# Step 1: Clone U-Boot
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking U-Boot source..."

mkdir -p "$UBOOT_DIR"

if [ ! -d "$UBOOT_SRC" ]; then
    log "  Cloning U-Boot for RK3326..."
    git clone --depth 1 "$UBOOT_REPO" "$UBOOT_SRC"
    log "  Cloned"
else
    log "  Source exists"
fi

#------------------------------------------------------------------------------
# Step 2: Verify toolchain
#------------------------------------------------------------------------------
log ""
log "Step 2: Checking toolchain..."

if ! command -v ${CROSS_COMPILE}gcc &>/dev/null; then
    error "aarch64 toolchain not found!\n  Install: sudo apt install gcc-aarch64-linux-gnu"
fi

log "  $(${CROSS_COMPILE}gcc --version | head -1)"

#------------------------------------------------------------------------------
# Step 3: Build U-Boot
#------------------------------------------------------------------------------
log ""
log "Step 3: Building U-Boot..."

cd "$UBOOT_SRC"

# GCC 13+ adds stricter warnings that U-Boot 2017.09 doesn't pass.
# Disable specific -Werror flags that break with modern GCC:
#   address-of-packed-member: disk/part_efi.c (packed struct pointer)
#   enum-int-mismatch: common/command.c (enum command_ret_t vs int)
#   maybe-uninitialized: common/edid.c (hdmi_len variable)
GCC_COMPAT_FLAGS="-Wno-error=address-of-packed-member -Wno-error=enum-int-mismatch -Wno-error=maybe-uninitialized"

make CROSS_COMPILE=$CROSS_COMPILE odroidgoa_defconfig
make CROSS_COMPILE=$CROSS_COMPILE KCFLAGS="$GCC_COMPAT_FLAGS" -j$(nproc)

log "  Built"

#------------------------------------------------------------------------------
# Step 4: Copy artifacts
#------------------------------------------------------------------------------
log ""
log "Step 4: Copying bootloader files..."

mkdir -p "$OUTPUT_DIR"

if [ -d "sd_fuse" ] && [ -f "sd_fuse/idbloader.img" ]; then
    cp sd_fuse/idbloader.img "$OUTPUT_DIR/"
    cp sd_fuse/uboot.img "$OUTPUT_DIR/"
    cp sd_fuse/trust.img "$OUTPUT_DIR/"
    log "  Bootloader binaries copied"
else
    error "sd_fuse directory not found — U-Boot build may have failed"
fi

# Copy R36S U-Boot DTBs
for dtb in r36s-uboot.dtb r36s-clone-uboot.dtb; do
    if [ -f "arch/arm/dts/$dtb" ]; then
        cp "arch/arm/dts/$dtb" "$OUTPUT_DIR/"
        log "  DTB copied: $dtb"
    else
        warn "DTB not found: $dtb"
    fi
done

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== U-Boot Build Complete ==="
log ""
log "Bootloader: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"
log ""
log "These will be installed by build-image.sh"
