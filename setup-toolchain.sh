#!/bin/bash

#==============================================================================
# Arch R - Toolchain Setup Script
#==============================================================================
# Sets up the cross-compilation environment for building Arch R
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/setup-toolchain.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Arch R Toolchain Setup ==="
log "Script directory: $SCRIPT_DIR"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log "Warning: Running as root. Some operations may require sudo anyway."
fi

#------------------------------------------------------------------------------
# Step 1: Install required packages
#------------------------------------------------------------------------------
log ""
log "Step 1: Installing required packages..."

PACKAGES=(
    # Cross-compilation toolchain
    gcc-aarch64-linux-gnu
    g++-aarch64-linux-gnu
    binutils-aarch64-linux-gnu
    
    # Build tools
    make
    cmake
    ninja-build
    bc
    bison
    flex
    
    # Device tree compiler
    device-tree-compiler
    
    # U-Boot tools
    u-boot-tools
    
    # For rootfs manipulation
    binfmt-support
    qemu-user-static
    debootstrap
    
    # Archive tools
    bsdtar
    xz-utils
    zstd
    
    # Misc
    git
    wget
    curl
    python3
    python3-pip
    libssl-dev
    libncurses5-dev
    
    # For image creation
    parted
    dosfstools
    e2fsprogs
    mtools
)

log "Updating package list..."
sudo apt update 2>&1 | tee -a "$LOG_FILE"

log "Installing packages..."
sudo apt install -y "${PACKAGES[@]}" 2>&1 | tee -a "$LOG_FILE"

#------------------------------------------------------------------------------
# Step 2: Create directory structure
#------------------------------------------------------------------------------
log ""
log "Step 2: Creating directory structure..."

DIRS=(
    "$SCRIPT_DIR/bootloader/configs"
    "$SCRIPT_DIR/bootloader/src"
    "$SCRIPT_DIR/kernel/configs"
    "$SCRIPT_DIR/kernel/dts"
    "$SCRIPT_DIR/kernel/patches"
    "$SCRIPT_DIR/kernel/src"
    "$SCRIPT_DIR/rootfs/overlay/etc"
    "$SCRIPT_DIR/rootfs/overlay/usr/local/bin"
    "$SCRIPT_DIR/rootfs/staging"
    "$SCRIPT_DIR/config/emulationstation"
    "$SCRIPT_DIR/config/retroarch"
    "$SCRIPT_DIR/config/udev"
    "$SCRIPT_DIR/scripts"
    "$SCRIPT_DIR/output"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    log "  Created: $dir"
done

#------------------------------------------------------------------------------
# Step 3: Verify toolchain
#------------------------------------------------------------------------------
log ""
log "Step 3: Verifying toolchain..."

if command -v aarch64-linux-gnu-gcc &> /dev/null; then
    GCC_VERSION=$(aarch64-linux-gnu-gcc --version | head -1)
    log "  GCC: $GCC_VERSION"
else
    log "ERROR: aarch64-linux-gnu-gcc not found!"
    exit 1
fi

if command -v dtc &> /dev/null; then
    DTC_VERSION=$(dtc --version | head -1)
    log "  DTC: $DTC_VERSION"
else
    log "ERROR: dtc not found!"
    exit 1
fi

if command -v mkimage &> /dev/null; then
    log "  mkimage: Available"
else
    log "WARNING: mkimage not found. U-Boot builds may fail."
fi

#------------------------------------------------------------------------------
# Step 4: Setup QEMU for ARM64 emulation
#------------------------------------------------------------------------------
log ""
log "Step 4: Setting up QEMU for ARM64..."

if command -v qemu-aarch64-static &> /dev/null; then
    log "  QEMU AArch64 static: Available"
    
    # Register binfmt if not already done
    if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        log "  binfmt: Already registered"
    else
        log "  Registering binfmt..."
        sudo systemctl restart binfmt-support 2>/dev/null || true
    fi
else
    log "WARNING: qemu-aarch64-static not found. Chroot operations will fail."
fi

#------------------------------------------------------------------------------
# Step 5: Create environment file
#------------------------------------------------------------------------------
log ""
log "Step 5: Creating environment configuration..."

cat > "$SCRIPT_DIR/env.sh" << 'EOF'
#!/bin/bash
# Arch R Build Environment Configuration

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Paths
export ARCHR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ARCHR_BOOTLOADER="$ARCHR_ROOT/bootloader"
export ARCHR_KERNEL="$ARCHR_ROOT/kernel"
export ARCHR_ROOTFS="$ARCHR_ROOT/rootfs"
export ARCHR_CONFIG="$ARCHR_ROOT/config"
export ARCHR_OUTPUT="$ARCHR_ROOT/output"

# Build options
export MAKEFLAGS="-j$(nproc)"

# Device-specific
export ARCHR_DEVICE="r36s"
export ARCHR_SOC="rk3326"

echo "Arch R build environment loaded."
echo "  ARCH: $ARCH"
echo "  CROSS_COMPILE: $CROSS_COMPILE"
echo "  Device: $ARCHR_DEVICE"
EOF

log "  Created: $SCRIPT_DIR/env.sh"

#------------------------------------------------------------------------------
# Complete
#------------------------------------------------------------------------------
log ""
log "=== Setup Complete! ==="
log ""
log "To start building, source the environment:"
log "  source env.sh"
log ""
log "Then run the build scripts:"
log "  ./build-kernel.sh"
log "  ./build-rootfs.sh"
log "  ./build-image.sh"
