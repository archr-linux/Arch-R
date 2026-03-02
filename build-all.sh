#!/bin/bash

#==============================================================================
# Arch R - Master Build Script
#==============================================================================
# Builds everything: kernel, rootfs, and SD card image
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     █████╗ ██████╗  ██████╗██╗  ██╗    ██████╗                ║"
    echo "║    ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██╔══██╗               ║"
    echo "║    ███████║██████╔╝██║     ███████║    ██████╔╝               ║"
    echo "║    ██╔══██║██╔══██╗██║     ██╔══██║    ██╔══██╗               ║"
    echo "║    ██║  ██║██║  ██║╚██████╗██║  ██║    ██║  ██║               ║"
    echo "║    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═╝               ║"
    echo "║                                                               ║"
    echo "║            Gaming Distribution for R36S                       ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --kernel     Build kernel only"
    echo "  --rootfs     Build rootfs only"
    echo "  --uboot      Build U-Boot only"
    echo "  --image      Build image only"
    echo "  --all        Build everything (default)"
    echo "  --clean      Clean all build artifacts"
    echo "  --help       Show this help"
    echo ""
}

BUILD_KERNEL=false
BUILD_ROOTFS=false
BUILD_UBOOT=false
BUILD_IMAGE=false
CLEAN=false

# Parse arguments
if [ $# -eq 0 ]; then
    BUILD_KERNEL=true
    BUILD_ROOTFS=true
    BUILD_UBOOT=true
    BUILD_IMAGE=true
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            --kernel) BUILD_KERNEL=true; shift ;;
            --rootfs) BUILD_ROOTFS=true; shift ;;
            --uboot)  BUILD_UBOOT=true; shift ;;
            --image)  BUILD_IMAGE=true; shift ;;
            --all)    BUILD_KERNEL=true; BUILD_ROOTFS=true; BUILD_UBOOT=true; BUILD_IMAGE=true; shift ;;
            --clean)  CLEAN=true; shift ;;
            --help)   usage; exit 0 ;;
            *)        error "Unknown option: $1" ;;
        esac
    done
fi

banner

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------
if [ "$CLEAN" = true ]; then
    log "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/output"
    rm -rf "$SCRIPT_DIR/.cache"
    log "✓ Clean complete"
    exit 0
fi

#------------------------------------------------------------------------------
# Prerequisites Check
#------------------------------------------------------------------------------
log "Checking prerequisites..."

# Check if running as root (needed for rootfs and image)
if [ "$BUILD_ROOTFS" = true ] || [ "$BUILD_IMAGE" = true ]; then
    if [ "$EUID" -ne 0 ]; then
        error "Rootfs and image build require root. Run with sudo."
    fi
fi

# Check cross-compiler
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    warn "Cross-compiler not found. Install with:"
    warn "  sudo apt install gcc-aarch64-linux-gnu"
    if [ "$BUILD_KERNEL" = true ]; then
        error "Cannot build kernel without cross-compiler"
    fi
fi

# Check QEMU (for rootfs chroot)
if [ "$BUILD_ROOTFS" = true ]; then
    if [ ! -f "/usr/bin/qemu-aarch64-static" ]; then
        warn "QEMU static not found. Install with:"
        warn "  sudo apt install qemu-user-static"
    fi
fi

log "✓ Prerequisites OK"

#------------------------------------------------------------------------------
# Build Steps
#------------------------------------------------------------------------------
START_TIME=$(date +%s)

if [ "$BUILD_KERNEL" = true ]; then
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                    BUILDING KERNEL"
    log "═══════════════════════════════════════════════════════════════"
    chmod +x "$SCRIPT_DIR/build-kernel.sh"
    "$SCRIPT_DIR/build-kernel.sh"
fi

if [ "$BUILD_ROOTFS" = true ]; then
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                    BUILDING ROOTFS"
    log "═══════════════════════════════════════════════════════════════"
    chmod +x "$SCRIPT_DIR/build-rootfs.sh"
    "$SCRIPT_DIR/build-rootfs.sh"
fi

# Build Mesa 26 (after rootfs, before ES — ES links against Mesa EGL/GLES)
if [ "$BUILD_ROOTFS" = true ]; then
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                  BUILDING MESA 26"
    log "═══════════════════════════════════════════════════════════════"
    chmod +x "$SCRIPT_DIR/build-mesa.sh"
    "$SCRIPT_DIR/build-mesa.sh"
fi

# Build EmulationStation (after rootfs + Mesa, before image)
if [ "$BUILD_ROOTFS" = true ]; then
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "               BUILDING EMULATIONSTATION"
    log "═══════════════════════════════════════════════════════════════"
    chmod +x "$SCRIPT_DIR/build-emulationstation.sh"
    "$SCRIPT_DIR/build-emulationstation.sh"
fi

# Build RetroArch with KMS/DRM (after rootfs + Mesa, before image)
if [ "$BUILD_ROOTFS" = true ]; then
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                  BUILDING RETROARCH"
    log "═══════════════════════════════════════════════════════════════"
    chmod +x "$SCRIPT_DIR/build-retroarch.sh"
    "$SCRIPT_DIR/build-retroarch.sh"
fi

# Generate panel DTBOs (always, lightweight step)
log ""
log "═══════════════════════════════════════════════════════════════"
log "                 GENERATING PANEL DTBOs"
log "═══════════════════════════════════════════════════════════════"
chmod +x "$SCRIPT_DIR/scripts/generate-panel-dtbos.sh"
"$SCRIPT_DIR/scripts/generate-panel-dtbos.sh"

# Build custom U-Boot (optional — requires arm-linux-gnueabihf toolchain)
if [ "$BUILD_UBOOT" = true ] && [ -f "$SCRIPT_DIR/build-uboot.sh" ]; then
    if command -v aarch64-linux-gnu-gcc &>/dev/null; then
        log ""
        log "═══════════════════════════════════════════════════════════════"
        log "                    BUILDING U-BOOT"
        log "═══════════════════════════════════════════════════════════════"
        chmod +x "$SCRIPT_DIR/build-uboot.sh"
        "$SCRIPT_DIR/build-uboot.sh"
    else
        warn "Skipping U-Boot build: aarch64-linux-gnu-gcc not found"
        warn "Install: sudo apt install gcc-aarch64-linux-gnu"
    fi
fi

if [ "$BUILD_IMAGE" = true ]; then
    chmod +x "$SCRIPT_DIR/build-image.sh"

    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                 BUILDING IMAGE (original)"
    log "═══════════════════════════════════════════════════════════════"
    "$SCRIPT_DIR/build-image.sh" --variant original

    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                 BUILDING IMAGE (clone)"
    log "═══════════════════════════════════════════════════════════════"
    "$SCRIPT_DIR/build-image.sh" --variant clone

    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "                 BUILDING IMAGE (no-panel)"
    log "═══════════════════════════════════════════════════════════════"
    "$SCRIPT_DIR/build-image.sh" --variant no-panel
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log ""
log "═══════════════════════════════════════════════════════════════"
log "                    BUILD COMPLETE!"
log "═══════════════════════════════════════════════════════════════"
log ""
log "Build time: ${MINUTES}m ${SECONDS}s"
log ""

if [ -d "$SCRIPT_DIR/output" ]; then
    log "Output files:"
    ls -lh "$SCRIPT_DIR/output/"* 2>/dev/null || true
    
    if [ -d "$SCRIPT_DIR/output/images" ]; then
        log ""
        log "Images:"
        ls -lh "$SCRIPT_DIR/output/images/"* 2>/dev/null || true
    fi
fi

log ""
log "🎮 Arch R is ready for R36S!"
