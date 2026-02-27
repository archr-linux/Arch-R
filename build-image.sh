#!/bin/bash

#==============================================================================
# Arch R - SD Card Image Builder
#==============================================================================
# Creates a flashable SD card image for R36S (original or clone)
#
# Usage:
#   sudo ./build-image.sh --variant original   # R36S original
#   sudo ./build-image.sh --variant clone       # R36S clone (G80CA-MB etc)
#   sudo ./build-image.sh                       # defaults to original
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
# Parse arguments
#------------------------------------------------------------------------------
VARIANT="original"

while [[ $# -gt 0 ]]; do
    case $1 in
        --variant)
            VARIANT="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1\nUsage: $0 --variant original|clone"
            ;;
    esac
done

if [ "$VARIANT" != "original" ] && [ "$VARIANT" != "clone" ]; then
    error "Invalid variant: $VARIANT (must be 'original' or 'clone')"
fi

#------------------------------------------------------------------------------
# Variant-specific configuration
#------------------------------------------------------------------------------
if [ "$VARIANT" = "original" ]; then
    IMAGE_SUFFIX="R36S"
    KERNEL_DTB_NAME="rk3326-gameconsole-r36s.dtb"
    ROOT_DEV="/dev/mmcblk1p2"
else
    IMAGE_SUFFIX="R36S-clone"
    KERNEL_DTB_NAME="rk3326-gameconsole-r36s-clone-type5.dtb"
    ROOT_DEV="/dev/mmcblk0p2"
fi

# U-Boot binaries per variant:
#   Original: BSP Rockchip U-Boot (custom build or pre-built)
#   Clone:    Mainline U-Boot v2025.10 (custom build or pre-built)
UBOOT_TYPE=""
UBOOT_BSP_DIR="$SCRIPT_DIR/bootloader/u-boot-rk3326/sd_fuse"
UBOOT_MAINLINE_DIR="$SCRIPT_DIR/bootloader/u-boot-clone-build"

if [ "$VARIANT" = "clone" ] && [ -f "$UBOOT_MAINLINE_DIR/uboot.img" ]; then
    UBOOT_BIN_DIR="$UBOOT_MAINLINE_DIR"
    UBOOT_TYPE="mainline"
    log "  U-Boot: mainline v2025.10 (clone)"
elif [ "$VARIANT" = "original" ] && [ -f "$UBOOT_BSP_DIR/uboot.img" ]; then
    UBOOT_BIN_DIR="$UBOOT_BSP_DIR"
    UBOOT_TYPE="bsp"
    log "  U-Boot: BSP custom build (original)"
elif [ "$VARIANT" = "original" ]; then
    UBOOT_BIN_DIR="$SCRIPT_DIR/bootloader/u-boot-r36s-working"
    UBOOT_TYPE="bsp"
    log "  U-Boot: BSP pre-built (original)"
else
    UBOOT_BIN_DIR="$SCRIPT_DIR/bootloader/u-boot-clone-working"
    UBOOT_TYPE="bsp"
    log "  U-Boot: BSP pre-built (clone fallback)"
fi

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
IMAGE_DIR="$OUTPUT_DIR/images"
IMAGE_NAME="ArchR-${IMAGE_SUFFIX}-$(date +%Y%m%d).img"

# CRITICAL: Always clean up loop devices and mounts on exit (success OR failure).
LOOP_DEV=""
cleanup_image() {
    echo "[IMAGE] Cleaning up mounts and loop devices..."
    umount -l "$OUTPUT_DIR/mnt_boot" 2>/dev/null || true
    umount -l "$OUTPUT_DIR/mnt_root" 2>/dev/null || true
    [ -n "$LOOP_DEV" ] && losetup -d "$LOOP_DEV" 2>/dev/null || true
    rmdir "$OUTPUT_DIR/mnt_root" "$OUTPUT_DIR/mnt_boot" 2>/dev/null || true
}
trap cleanup_image EXIT
IMAGE_FILE="$IMAGE_DIR/$IMAGE_NAME"

# Partition sizes (in MB)
BOOT_SIZE=128        # Boot partition (FAT32)
ROOTFS_SIZE=6144     # Root filesystem (ext4) - 6GB for full Arch + gaming stack

# Total image size
IMAGE_SIZE=$((BOOT_SIZE + ROOTFS_SIZE + 32))  # +32MB for partition table

log "=== Arch R Image Builder (variant: $VARIANT) ==="

#------------------------------------------------------------------------------
# Root check
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

#------------------------------------------------------------------------------
# Step 1: Verify Prerequisites
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking prerequisites..."

if [ ! -d "$ROOTFS_DIR" ]; then
    error "Rootfs not found at: $ROOTFS_DIR\nRun build-rootfs.sh first!"
fi

if [ ! -f "$ROOTFS_DIR/boot/Image" ]; then
    warn "Kernel Image not found in rootfs. Make sure kernel is installed."
else
    IMAGE_BYTES=$(stat -c%s "$ROOTFS_DIR/boot/Image")
    if [ "$IMAGE_BYTES" -lt 10000000 ]; then
        error "Kernel Image is only $(($IMAGE_BYTES / 1024 / 1024))MB — expected ~18MB for kernel 6.6!"
    fi
    log "  Kernel Image: $(($IMAGE_BYTES / 1024 / 1024))MB (OK)"
fi

# Check variant-specific DTB
if [ ! -f "$ROOTFS_DIR/boot/$KERNEL_DTB_NAME" ]; then
    error "Kernel DTB not found: $ROOTFS_DIR/boot/$KERNEL_DTB_NAME\nRun build-kernel.sh first!"
fi
log "  DTB ($VARIANT): $KERNEL_DTB_NAME (OK)"

# Check U-Boot binaries
if [ ! -d "$UBOOT_BIN_DIR" ] || [ ! -f "$UBOOT_BIN_DIR/idbloader.img" ]; then
    error "U-Boot binaries not found at: $UBOOT_BIN_DIR"
fi
log "  U-Boot: $UBOOT_BIN_DIR (OK)"

# Check required tools
for tool in parted mkfs.vfat mkfs.ext4 losetup; do
    if ! command -v $tool &> /dev/null; then
        error "Required tool not found: $tool"
    fi
done

log "  Prerequisites OK"

#------------------------------------------------------------------------------
# Step 2: Create Image File
#------------------------------------------------------------------------------
log ""
log "Step 2: Creating image file..."

mkdir -p "$IMAGE_DIR"

# Remove old images for this variant only
rm -f "$IMAGE_DIR"/ArchR-${IMAGE_SUFFIX}-*.img "$IMAGE_DIR"/ArchR-${IMAGE_SUFFIX}-*.img.xz

# Create sparse image file
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count=0 seek=$IMAGE_SIZE 2>/dev/null
log "  Created ${IMAGE_SIZE}MB image: $IMAGE_NAME"

#------------------------------------------------------------------------------
# Step 2.5: Install U-Boot Bootloader
#------------------------------------------------------------------------------
log ""
log "Step 2.5: Installing U-Boot bootloader..."

dd if="$UBOOT_BIN_DIR/idbloader.img" of="$IMAGE_FILE" bs=512 seek=64 conv=sync,noerror,notrunc 2>/dev/null
dd if="$UBOOT_BIN_DIR/uboot.img" of="$IMAGE_FILE" bs=512 seek=16384 conv=sync,noerror,notrunc 2>/dev/null
dd if="$UBOOT_BIN_DIR/trust.img" of="$IMAGE_FILE" bs=512 seek=24576 conv=sync,noerror,notrunc 2>/dev/null
log "  U-Boot installed from $UBOOT_BIN_DIR"

#------------------------------------------------------------------------------
# Step 3: Create Partitions
#------------------------------------------------------------------------------
log ""
log "Step 3: Creating partitions..."

parted -s "$IMAGE_FILE" mklabel msdos

BOOT_START=16
BOOT_END=$((BOOT_START + BOOT_SIZE))
ROOTFS_START=$BOOT_END
ROOTFS_END=$((ROOTFS_START + ROOTFS_SIZE))

parted -s "$IMAGE_FILE" mkpart primary fat32 ${BOOT_START}MiB ${BOOT_END}MiB
parted -s "$IMAGE_FILE" mkpart primary ext4 ${ROOTFS_START}MiB ${ROOTFS_END}MiB
parted -s "$IMAGE_FILE" set 1 boot on

log "  Partitions created"

#------------------------------------------------------------------------------
# Step 4: Setup Loop Devices
#------------------------------------------------------------------------------
log ""
log "Step 4: Setting up loop devices..."

LOOP_DEV=$(losetup -fP --show "$IMAGE_FILE")
BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

sleep 1

log "  Loop device: $LOOP_DEV"

#------------------------------------------------------------------------------
# Step 5: Format Partitions
#------------------------------------------------------------------------------
log ""
log "Step 5: Formatting partitions..."

mkfs.vfat -F 32 -n BOOT "$BOOT_PART"
mkfs.ext4 -L ROOTFS -O ^metadata_csum "$ROOT_PART"

log "  Partitions formatted"

#------------------------------------------------------------------------------
# Step 6: Mount and Copy Files
#------------------------------------------------------------------------------
log ""
log "Step 6: Copying files..."

MOUNT_ROOT="$OUTPUT_DIR/mnt_root"
MOUNT_BOOT="$OUTPUT_DIR/mnt_boot"

mkdir -p "$MOUNT_ROOT" "$MOUNT_BOOT"
mount "$ROOT_PART" "$MOUNT_ROOT"
mount "$BOOT_PART" "$MOUNT_BOOT"

# --- Rootfs (excluding /boot) ---
log "  Copying rootfs..."
rsync -aHxS --exclude='/boot' "$ROOTFS_DIR/" "$MOUNT_ROOT/"

# --- Write variant marker (for panel-detect.py and other scripts) ---
mkdir -p "$MOUNT_ROOT/etc/archr"
echo "$VARIANT" > "$MOUNT_ROOT/etc/archr/variant"
log "  Variant marker: /etc/archr/variant = $VARIANT"

# --- Ensure first-boot runs on actual first boot ---
# The rootfs may contain a stale flag from the build process
rm -f "$MOUNT_ROOT/var/lib/archr/.first-boot-done"

# --- Boot partition: kernel Image ---
log "  Copying boot files..."
cp "$ROOTFS_DIR/boot/Image" "$MOUNT_BOOT/"

# --- Boot partition: kernel DTB (as kernel.dtb) ---
cp "$ROOTFS_DIR/boot/$KERNEL_DTB_NAME" "$MOUNT_BOOT/kernel.dtb"
log "  kernel.dtb <- $KERNEL_DTB_NAME"

# --- Boot partition: Panel DTBO overlays (variant-specific) ---
PANELS_DIR="$OUTPUT_DIR/panels/ScreenFiles"
if [ -d "$PANELS_DIR" ]; then
    mkdir -p "$MOUNT_BOOT/ScreenFiles"
    panel_count=0

    # Copy variant-specific panels (explicit names — NO glob with spaces)
    if [ "$VARIANT" = "original" ]; then
        # R36S original: Panel 0 through Panel 5
        for i in 0 1 2 3 4 5; do
            if [ -d "$PANELS_DIR/Panel $i" ]; then
                cp -r "$PANELS_DIR/Panel $i" "$MOUNT_BOOT/ScreenFiles/"
                panel_count=$((panel_count + 1))
            fi
        done
    else
        # R36S clone: Clone Panel 1 through Clone Panel 10 + extras
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if [ -d "$PANELS_DIR/Clone Panel $i" ]; then
                cp -r "$PANELS_DIR/Clone Panel $i" "$MOUNT_BOOT/ScreenFiles/"
                panel_count=$((panel_count + 1))
            fi
        done
        for extra in "R36 Max" "RX6S"; do
            if [ -d "$PANELS_DIR/$extra" ]; then
                cp -r "$PANELS_DIR/$extra" "$MOUNT_BOOT/ScreenFiles/"
                panel_count=$((panel_count + 1))
            fi
        done
    fi

    log "  ScreenFiles: ${panel_count} panel overlays ($VARIANT)"
else
    warn "Panel DTBOs not found! Run scripts/generate-panel-dtbos.sh first"
fi

# --- Boot partition: U-Boot display DTB ---
# BSP U-Boot: hwrev.c loads display DTB from FAT partition (init_kernel_dtb).
# Mainline U-Boot: uses built-in DTS, no separate display DTB needed.
if [ "$UBOOT_TYPE" = "mainline" ]; then
    log "  U-Boot display DTB: not needed (mainline)"
else
    UBOOT_DTS_DIR="$SCRIPT_DIR/bootloader/u-boot-rk3326/arch/arm/dts"
    display_dtb_copied=0

    if [ "$UBOOT_BIN_DIR" = "$UBOOT_BSP_DIR" ]; then
        # BSP custom build: copy variant-specific DTB as uboot-display.dtb
        if [ "$VARIANT" = "original" ]; then
            UBOOT_SRC_DTB="$UBOOT_DTS_DIR/r36s-uboot.dtb"
        else
            UBOOT_SRC_DTB="$UBOOT_DTS_DIR/r36-uboot.dtb"
        fi
        if [ -f "$UBOOT_SRC_DTB" ]; then
            cp "$UBOOT_SRC_DTB" "$MOUNT_BOOT/uboot-display.dtb"
            display_dtb_copied=1
            log "  uboot-display.dtb <- $(basename $UBOOT_SRC_DTB) (custom)"
        fi
    else
        # Legacy pre-built: copy variant-specific DTB under its original name
        if [ "$VARIANT" = "original" ]; then
            UBOOT_DISPLAY_DTB="rg351mp-uboot.dtb"
        else
            UBOOT_DISPLAY_DTB="arkos4clone-uboot.dtb"
        fi
        for dtb_dir in "$UBOOT_BIN_DIR" "$UBOOT_DTS_DIR"; do
            if [ -f "$dtb_dir/$UBOOT_DISPLAY_DTB" ]; then
                cp "$dtb_dir/$UBOOT_DISPLAY_DTB" "$MOUNT_BOOT/$UBOOT_DISPLAY_DTB"
                display_dtb_copied=1
                log "  U-Boot display DTB: $UBOOT_DISPLAY_DTB (legacy)"
                break
            fi
        done
    fi

    if [ "$display_dtb_copied" -eq 0 ]; then
        warn "No U-Boot display DTB found — init_kernel_dtb() WILL FAIL!"
    fi
fi

# --- Boot partition: boot script (with root device substituted) ---
if [ -f "$SCRIPT_DIR/config/boot.ini" ]; then
    sed "s|__ROOTDEV__|$ROOT_DEV|" "$SCRIPT_DIR/config/boot.ini" > "$MOUNT_BOOT/boot.ini"
    log "  boot.ini installed (root=$ROOT_DEV)"

    # Mainline U-Boot: also create boot.scr (compiled boot script)
    # Mainline uses distro boot flow → scans for boot.scr, not boot.ini
    if [ "$UBOOT_TYPE" = "mainline" ]; then
        MKIMAGE="$SCRIPT_DIR/bootloader/u-boot-mainline/tools/mkimage"
        if [ -x "$MKIMAGE" ]; then
            # mkimage doesn't support stdin pipe (-d -) reliably — use temp file
            BOOT_SCR_SRC=$(mktemp)
            grep -v '^odroidgoa-uboot-config' "$MOUNT_BOOT/boot.ini" > "$BOOT_SCR_SRC"
            "$MKIMAGE" -T script -d "$BOOT_SCR_SRC" "$MOUNT_BOOT/boot.scr" >/dev/null 2>&1
            rm -f "$BOOT_SCR_SRC"
            log "  boot.scr created (mainline distro boot)"
        else
            warn "mkimage not found — boot.scr not created! Mainline U-Boot may not find boot script."
        fi
    fi
else
    error "boot.ini not found at config/boot.ini!"
fi

# --- Boot splash: initramfs with embedded splash (appears <1s after kernel start) ---
# Splash is embedded in initramfs /init binary — no file I/O needed at boot time.
# Pipeline: generate splash.bmp → xxd → compile archr-init → cpio → initramfs.img
log "  Building boot splash initramfs..."

SPLASH_FONT="$SCRIPT_DIR/assets/fonts/Quantico-Regular.ttf"
SPLASH_TMPDIR=$(mktemp -d)
BUILD_DATE=$(date +%Y%m%d)
ARCHR_VERSION="v1.0"

if command -v convert &>/dev/null && [ -f "$SPLASH_FONT" ] && command -v aarch64-linux-gnu-gcc &>/dev/null; then

    # Step 1: Generate splash.bmp (Quantico font, glow effect, version+build)
    convert -size 640x480 xc:black "$SPLASH_TMPDIR/base.png"
    # ARCH glow (blue, blurred) — offset -33 centers "ARCH R" as a unit
    convert -size 640x480 xc:transparent -font "$SPLASH_FONT" -pointsize 72 -fill '#1793D1' \
        -gravity center -annotate -33+0 "ARCH" -channel RGBA -blur 0x8 "$SPLASH_TMPDIR/arch-glow.png"
    # ARCH text (blue, sharp)
    convert -size 640x480 xc:transparent -font "$SPLASH_FONT" -pointsize 72 -fill '#1793D1' \
        -gravity center -annotate -33+0 "ARCH" "$SPLASH_TMPDIR/arch-text.png"
    # R glow (white, blurred) — offset +107 gives proper spacing after ARCH
    convert -size 640x480 xc:transparent -font "$SPLASH_FONT" -pointsize 72 -fill white \
        -gravity center -annotate +107+0 "R" -channel RGBA -blur 0x8 "$SPLASH_TMPDIR/r-glow.png"
    # R text (white, sharp)
    convert -size 640x480 xc:transparent -font "$SPLASH_FONT" -pointsize 72 -fill white \
        -gravity center -annotate +107+0 "R" "$SPLASH_TMPDIR/r-text.png"
    # Version + build date
    convert -size 640x480 xc:transparent -font "$SPLASH_FONT" -pointsize 14 -fill '#666666' \
        -gravity center -annotate +0+50 "${ARCHR_VERSION} BUILD ${BUILD_DATE}" "$SPLASH_TMPDIR/version.png"
    # Composite all layers
    convert "$SPLASH_TMPDIR/base.png" \
        "$SPLASH_TMPDIR/arch-glow.png" -composite \
        "$SPLASH_TMPDIR/r-glow.png" -composite \
        "$SPLASH_TMPDIR/arch-text.png" -composite \
        "$SPLASH_TMPDIR/r-text.png" -composite \
        "$SPLASH_TMPDIR/version.png" -composite \
        -alpha remove -type TrueColor BMP3:"$SPLASH_TMPDIR/splash.bmp"
    log "  splash.bmp created ($(du -h "$SPLASH_TMPDIR/splash.bmp" | cut -f1))"

    # Step 2: Generate splash_data.h (embedded BMP data for archr-init)
    cd "$SPLASH_TMPDIR"
    xxd -i splash.bmp > splash_data.h
    cd "$SCRIPT_DIR"
    log "  splash_data.h generated ($(wc -l < "$SPLASH_TMPDIR/splash_data.h") lines)"

    # Step 3: Compile archr-init with embedded splash (static aarch64 binary)
    aarch64-linux-gnu-gcc -static -O2 -I"$SPLASH_TMPDIR" \
        -o "$SPLASH_TMPDIR/archr-init" "$SCRIPT_DIR/scripts/archr-init.c"
    log "  archr-init compiled ($(du -h "$SPLASH_TMPDIR/archr-init" | cut -f1))"

    # Step 4: Create initramfs (cpio + gzip)
    mkdir -p "$SPLASH_TMPDIR/initramfs"/{dev,proc,newroot}
    cp "$SPLASH_TMPDIR/archr-init" "$SPLASH_TMPDIR/initramfs/init"
    chmod 755 "$SPLASH_TMPDIR/initramfs/init"
    (cd "$SPLASH_TMPDIR/initramfs" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$MOUNT_BOOT/initramfs.img")
    log "  initramfs.img created ($(du -h "$MOUNT_BOOT/initramfs.img" | cut -f1))"

    # Also copy splash.bmp to BOOT (for reference / fallback)
    cp "$SPLASH_TMPDIR/splash.bmp" "$MOUNT_BOOT/splash.bmp"

else
    if ! command -v convert &>/dev/null; then
        warn "ImageMagick not found — initramfs splash skipped"
    elif [ ! -f "$SPLASH_FONT" ]; then
        warn "Quantico font not found at $SPLASH_FONT — initramfs splash skipped"
    else
        warn "aarch64-linux-gnu-gcc not found — initramfs splash skipped"
    fi
fi
rm -rf "$SPLASH_TMPDIR"

# NOTE: extlinux.conf is NOT created — boot.ini / boot.scr is the primary boot method.
log "  (no extlinux.conf — boot.ini is primary boot method)"

# --- Rootfs: fstab (overrides rootfs fstab with correct entries) ---
cat > "$MOUNT_ROOT/etc/fstab" << 'FSTAB_EOF'
# Arch R fstab — optimized for fast boot
# fsck disabled (fsck.mode=skip in cmdline + pass=0 here)
LABEL=BOOT        /boot     vfat     defaults,noatime                       0      0
LABEL=ROOTFS      /         ext4     defaults,noatime                       0      0
LABEL=ROMS        /roms     vfat     defaults,utf8,noatime,uid=1001,gid=1001,nofail,x-systemd.device-timeout=10s  0  0
tmpfs             /tmp      tmpfs    defaults,nosuid,nodev,size=128M        0      0
tmpfs             /var/log  tmpfs    defaults,nosuid,nodev,noexec,size=16M  0      0
FSTAB_EOF
log "  Files copied"

#------------------------------------------------------------------------------
# Step 7: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 7: Syncing filesystem..."

sync

log "  Sync complete"

#------------------------------------------------------------------------------
# Step 8: Compress (optional)
#------------------------------------------------------------------------------
log ""
log "Step 8: Compressing image..."

if command -v xz &> /dev/null; then
    rm -f "${IMAGE_FILE}.xz"
    xz -9 -k "$IMAGE_FILE"
    COMPRESSED="${IMAGE_FILE}.xz"
    COMPRESSED_SIZE=$(du -h "$COMPRESSED" | cut -f1)
    log "  Compressed: $COMPRESSED ($COMPRESSED_SIZE)"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== Image Build Complete ($VARIANT) ==="
log ""

IMAGE_SIZE_ACTUAL=$(du -h "$IMAGE_FILE" | cut -f1)
log "Image: $IMAGE_FILE"
log "Size: $IMAGE_SIZE_ACTUAL"
log "Variant: $VARIANT"
log "Root: $ROOT_DEV"
log ""
log "To flash to SD card:"
log "  sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress"
log ""
log "Arch R image ready ($VARIANT)!"
