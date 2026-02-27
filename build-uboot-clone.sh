#!/bin/bash
#==============================================================================
# Arch R - Build Mainline U-Boot for R36S Clones
#==============================================================================
# Uses mainline U-Boot v2025.10 + ROCKNIX patches
# Produces: idbloader.img, uboot.img, trust.img (Rockchip format)
#
# Usage:
#   ./build-uboot-clone.sh [--uart5]
#
# --uart5: Build for K36 clones that use UART5 instead of UART2
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBOOT_SRC="$SCRIPT_DIR/bootloader/u-boot-mainline"
RKBIN_DIR="$SCRIPT_DIR/bootloader/rkbin"
OUTPUT_DIR="$SCRIPT_DIR/bootloader/u-boot-clone-build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[UBOOT-CLONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[UBOOT-CLONE] WARNING:${NC} $1"; }
error() { echo -e "${RED}[UBOOT-CLONE] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
UART5=0
for arg in "$@"; do
    case "$arg" in
        --uart5) UART5=1 ;;
    esac
done

#------------------------------------------------------------------------------
# Verify prerequisites
#------------------------------------------------------------------------------
CROSS_COMPILE="aarch64-linux-gnu-"

if ! command -v ${CROSS_COMPILE}gcc &>/dev/null; then
    error "Cross-compiler not found. Install: sudo apt install gcc-aarch64-linux-gnu"
fi

if ! python3 -c "import elftools" 2>/dev/null; then
    error "pyelftools not found. Install: pip3 install pyelftools"
fi

if ! command -v swig &>/dev/null; then
    error "swig not found. Install: sudo apt install swig"
fi

[ -d "$UBOOT_SRC" ] || error "Mainline U-Boot source not found: $UBOOT_SRC"
[ -d "$RKBIN_DIR" ] || error "rkbin not found: $RKBIN_DIR"

#------------------------------------------------------------------------------
# Rockchip firmware binaries
#------------------------------------------------------------------------------
PKG_DDR_BIN="$RKBIN_DIR/bin/rk33/rk3326_ddr_333MHz_v2.11.bin"
PKG_MINILOADER="$RKBIN_DIR/bin/rk33/rk3326_miniloader_v1.40.bin"
PKG_BL31="$RKBIN_DIR/bin/rk33/rk3326_bl31_v1.34.elf"

[ -f "$PKG_DDR_BIN" ] || error "DDR binary not found: $PKG_DDR_BIN"
[ -f "$PKG_MINILOADER" ] || error "Miniloader not found: $PKG_MINILOADER"
[ -f "$PKG_BL31" ] || error "BL31 not found: $PKG_BL31"

#------------------------------------------------------------------------------
# UART5 DDR binary (for K36 clones)
#------------------------------------------------------------------------------
if [ "$UART5" -eq 1 ]; then
    log "Building UART5 variant for K36 clones"
    PKG_DDR_BIN_UART5="$RKBIN_DIR/rk3326_ddr_uart5.bin"

    if [ ! -f "$PKG_DDR_BIN_UART5" ]; then
        log "Creating UART5-tuned DDR binary..."
        DDRBIN_TOOL="$RKBIN_DIR/tools/ddrbin_tool"
        if [ ! -x "$DDRBIN_TOOL" ]; then
            error "ddrbin_tool not found or not executable: $DDRBIN_TOOL"
        fi
        cp "$PKG_DDR_BIN" "$PKG_DDR_BIN_UART5"
        "$DDRBIN_TOOL" rk3326 -g "$RKBIN_DIR/rk3326_ddr_uart5.txt" "$PKG_DDR_BIN_UART5"
        sed -i 's|uart id=.*$|uart id=5|' "$RKBIN_DIR/rk3326_ddr_uart5.txt"
        "$DDRBIN_TOOL" rk3326 "$RKBIN_DIR/rk3326_ddr_uart5.txt" "$PKG_DDR_BIN_UART5" >/dev/null
        log "UART5 DDR binary created"
    fi
    PKG_DDR_BIN="$PKG_DDR_BIN_UART5"
fi

#------------------------------------------------------------------------------
# Build U-Boot
#------------------------------------------------------------------------------
JOBS=$(nproc)
DEFCONFIG="rk3326-handheld_defconfig"

log "=== Building Mainline U-Boot v2025.10 for R36S Clone ==="
log "Cross-compiler: $(${CROSS_COMPILE}gcc --version | head -1)"
log "Defconfig: $DEFCONFIG"
log "Jobs: $JOBS"
[ "$UART5" -eq 1 ] && log "UART: UART5 (0xFF178000)" || log "UART: UART2 (0xFF160000)"

cd "$UBOOT_SRC"

log "Step 1: Clean..."
make CROSS_COMPILE="$CROSS_COMPILE" ARCH=arm mrproper 2>&1 | tail -1

log "Step 2: Configure..."
make CROSS_COMPILE="$CROSS_COMPILE" ARCH=arm "$DEFCONFIG" 2>&1 | tail -1

# UART5 variant: override config
if [ "$UART5" -eq 1 ]; then
    ./scripts/config --set-val CONFIG_DEBUG_UART_BASE 0xFF178000
    ./scripts/config --set-str CONFIG_DEVICE_TREE_INCLUDES "rk3326-odroid-go2-emmc.dtsi rk3326-odroid-go2-uart5.dtsi"
    log "UART5 config applied"
fi

log "Step 3: Compile..."
make CROSS_COMPILE="$CROSS_COMPILE" ARCH=arm -j"$JOBS" u-boot-dtb.bin 2>&1 | tail -20

[ -f "u-boot-dtb.bin" ] || error "Build failed: u-boot-dtb.bin not found"
log "u-boot-dtb.bin built: $(du -h u-boot-dtb.bin | cut -f1)"

#------------------------------------------------------------------------------
# Package: idbloader.img
#------------------------------------------------------------------------------
log "Step 4: Creating idbloader.img..."
"$UBOOT_SRC/tools/mkimage" -n px30 -T rksd -d "$PKG_DDR_BIN" -C bzip2 idbloader.img
cat "$PKG_MINILOADER" >> idbloader.img
log "idbloader.img: $(du -h idbloader.img | cut -f1)"

#------------------------------------------------------------------------------
# Package: uboot.img
#------------------------------------------------------------------------------
log "Step 5: Creating uboot.img..."
"$RKBIN_DIR/tools/loaderimage" --pack --uboot u-boot-dtb.bin uboot.img 0x00200000 2>&1 | tail -3
log "uboot.img: $(du -h uboot.img | cut -f1)"

#------------------------------------------------------------------------------
# Package: trust.img
#------------------------------------------------------------------------------
log "Step 6: Creating trust.img..."
cat >trust.ini <<EOF
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=${PKG_BL31}
ADDR=0x00010000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF
"$RKBIN_DIR/tools/trust_merger" --verbose trust.ini 2>&1 | tail -5
log "trust.img: $(du -h trust.img | cut -f1)"

#------------------------------------------------------------------------------
# Copy to output directory
#------------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
cp idbloader.img uboot.img trust.img "$OUTPUT_DIR/"

log ""
log "=== Build Complete ==="
log "Output: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"*.img
log ""
log "Flash with:"
log "  ./flash-uboot-clone.sh /dev/sdX"
