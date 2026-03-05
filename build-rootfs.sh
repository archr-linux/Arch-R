#!/bin/bash

#==============================================================================
# Arch R - Root Filesystem Build Script
#==============================================================================
# Creates a minimal Arch Linux ARM rootfs optimized for R36S gaming
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

OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
CACHE_DIR="$SCRIPT_DIR/.cache"

# CRITICAL: Always clean up bind mounts on exit (success OR failure).
cleanup_mounts() {
    echo "[ROOTFS] Cleaning up bind mounts..."
    umount -l "$ROOTFS_DIR/run" 2>/dev/null || true
    umount -l "$ROOTFS_DIR/sys" 2>/dev/null || true
    umount -l "$ROOTFS_DIR/proc" 2>/dev/null || true
    umount -l "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
    umount -l "$ROOTFS_DIR/dev" 2>/dev/null || true
}
trap cleanup_mounts EXIT

# Arch Linux ARM rootfs
ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
ALARM_TARBALL="$CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz"

log "=== Arch R Rootfs Build ==="

#------------------------------------------------------------------------------
# Root check
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (for chroot and permissions)"
fi

#------------------------------------------------------------------------------
# Step 1: Download Arch Linux ARM
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking Arch Linux ARM tarball..."

mkdir -p "$CACHE_DIR"

if [ ! -f "$ALARM_TARBALL" ]; then
    log "  Downloading Arch Linux ARM..."
    wget -O "$ALARM_TARBALL" "$ALARM_URL"
else
    log "  ✓ Using cached tarball"
fi

#------------------------------------------------------------------------------
# Step 2: Extract Base System
#------------------------------------------------------------------------------
log ""
log "Step 2: Extracting base system..."

# Clean previous rootfs (unmount stale bind mounts first)
if [ -d "$ROOTFS_DIR" ]; then
    warn "Removing existing rootfs..."
    for mp in run sys proc dev/pts dev; do
        mountpoint -q "$ROOTFS_DIR/$mp" 2>/dev/null && umount -l "$ROOTFS_DIR/$mp" 2>/dev/null || true
    done
    rm -rf "$ROOTFS_DIR"
fi

mkdir -p "$ROOTFS_DIR"

log "  Extracting... (this may take a while)"
bsdtar -xpf "$ALARM_TARBALL" -C "$ROOTFS_DIR"

log "  ✓ Base system extracted"

#------------------------------------------------------------------------------
# Step 3: Setup for chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up chroot environment..."

# Copy QEMU for ARM64 emulation
if [ -f "/usr/bin/qemu-aarch64-static" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    log "  ✓ QEMU static copied"
else
    warn "qemu-aarch64-static not found, chroot may not work"
    warn "Install with: sudo apt install qemu-user-static"
fi

# Bind mounts
mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"
mount --bind /run "$ROOTFS_DIR/run"

log "  ✓ Chroot environment ready"

# Fix pacman for QEMU chroot environment
# - Disable CheckSpace (mount point detection fails in chroot)
sed -i 's/^CheckSpace/#CheckSpace/' "$ROOTFS_DIR/etc/pacman.conf"
log "  ✓ Pacman CheckSpace disabled (QEMU chroot compatibility)"

# Add multiple fallback mirrors (default mirror often has stale/404 packages)
cat > "$ROOTFS_DIR/etc/pacman.d/mirrorlist" << 'MIRRORS_EOF'
# Arch Linux ARM mirrors - all official, Americas first
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://eu.mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://de4.mirror.archlinuxarm.org/$arch/$repo
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
Server = http://hu.mirror.archlinuxarm.org/$arch/$repo
Server = http://gr.mirror.archlinuxarm.org/$arch/$repo
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
Server = http://tw.mirror.archlinuxarm.org/$arch/$repo
Server = http://tw2.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
MIRRORS_EOF
log "  ✓ Multiple ALARM mirrors configured (fallback for 404s)"

#------------------------------------------------------------------------------
# Step 4: Configure System
#------------------------------------------------------------------------------
log ""
log "Step 4: Configuring system..."

# Create setup script to run inside chroot
cat > "$ROOTFS_DIR/tmp/setup.sh" << 'SETUP_EOF'
#!/bin/bash
set -e

echo "=== Inside chroot ==="

# Disable pacman Landlock sandbox (fails in QEMU chroot)
# Shell function wraps all pacman calls with --disable-sandbox
pacman() { command pacman --disable-sandbox "$@"; }
echo "  Pacman sandbox disabled (--disable-sandbox wrapper)"

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Remove stock ALARM kernel + mkinitcpio BEFORE upgrade
# We build our own kernel 6.6.89 — stock linux-aarch64 triggers mkinitcpio
# hooks during pacman -Syu, causing harmless but noisy warnings.
pacman -Rdd --noconfirm linux-aarch64 mkinitcpio mkinitcpio-busybox 2>/dev/null || true

# Full system upgrade — multiple mirrors configured for 404 fallback
pacman -Syu --noconfirm --disable-download-timeout

# Install essential packages
pacman -S --noconfirm --needed \
    base \
    linux-firmware \
    networkmanager \
    wpa_supplicant \
    dhcpcd \
    sudo \
    nano \
    htop \
    wget \
    usb_modeswitch \
    dosfstools \
    parted \
    i2c-tools

# Audio
pacman -S --noconfirm --needed \
    alsa-utils \
    alsa-plugins

# Bluetooth
pacman -S --noconfirm --needed \
    bluez \
    bluez-utils

# Graphics & GPU runtime dependencies
# NOTE: Do NOT install 'mesa' here! build-mesa.sh builds Mesa 26 from source
# with -Dgles1=enabled -Dglvnd=false. Installing pacman's mesa first would
# add glvnd files that conflict with our custom build.
pacman -S --noconfirm --needed \
    libdrm \
    sdl2 \
    sdl2_mixer \
    sdl2_image \
    sdl2_ttf

# Gaming stack dependencies
# NOTE: Do NOT install 'retroarch' here! build-retroarch.sh builds from source
# with KMS/DRM + EGL (no X11/Qt). ALARM's retroarch package uses X11/Qt,
# pulling in ~200MB of unnecessary X11 dependencies.
# Note: freeimage is not in ALARM repos — installed in build-emulationstation.sh
pacman -S --noconfirm --needed \
    libretro-core-info \
    freetype2 \
    libglvnd \
    mbedtls \
    curl \
    unzip \
    p7zip \
    evtest \
    brightnessctl \
    python-evdev

# LibRetro cores — all from ALARM pacman repos (native aarch64)
# The libretro buildbot has NO aarch64 Linux builds — ALARM is the only source.
# Install each individually (some may not exist in all mirror snapshots)
for core in \
    libretro-snes9x \
    libretro-gambatte \
    libretro-mgba \
    libretro-genesis-plus-gx \
    libretro-pcsx-rearmed \
    libretro-flycast \
    libretro-beetle-pce-fast \
    libretro-scummvm \
    libretro-melonds \
    libretro-nestopia \
    libretro-picodrive \
    libretro-mesen \
    libretro-duckstation \
    libretro-beetle-psx-hw \
    libretro-mame2016 \
    libretro-yabause \
    libretro-sameboy \
    libretro-beetle-supergrafx; do
    pacman -S --noconfirm --needed "$core" 2>/dev/null \
        && echo "  Installed: $core" \
        || echo "  Not available: $core"
done

# Clean up any 0-byte core files (from previous failed downloads)
CORES_DIR="/usr/lib/libretro"
find "$CORES_DIR" -name "*_libretro.so" -size 0 -delete -print 2>/dev/null | \
    while read f; do echo "  Removed 0-byte: $(basename "$f")"; done


# Enable services
systemctl enable NetworkManager

# Disable unnecessary services for faster boot
systemctl disable systemd-timesyncd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
systemctl disable remote-fs.target 2>/dev/null || true

# Create gaming user 'archr'
if ! id archr &>/dev/null; then
    useradd -m -G wheel,audio,video,render,input -s /bin/bash archr
    echo "archr:archr" | chpasswd
fi

# Allow wheel group passwordless sudo
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

# Set hostname
echo "archr" > /etc/hostname

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Performance tuning
cat > /etc/sysctl.d/99-archr.conf << 'SYSCTL_EOF'
# Arch R Performance Tuning
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=5
kernel.sched_latency_ns=1000000
kernel.sched_min_granularity_ns=500000
SYSCTL_EOF

# Memory manager — ZRAM swap with delayed start (15s after boot)
# Timer avoids blocking multi-user.target (ES is already running by then)
cat > /etc/systemd/system/archr-memory-manager.service << 'MEM_SVC'
[Unit]
Description=Arch R Memory Manager

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/archr-memory-manager setup
ExecStop=/usr/local/bin/archr-memory-manager stop
ExecReload=/usr/local/bin/archr-memory-manager reload
MEM_SVC

cat > /etc/systemd/system/archr-memory-manager.timer << 'MEM_TIMER'
[Unit]
Description=Delayed Memory Manager Setup

[Timer]
OnBootSec=15s
Unit=archr-memory-manager.service

[Install]
WantedBy=timers.target
MEM_TIMER

systemctl enable archr-memory-manager.timer

# Create directories
mkdir -p /home/archr/.config/retroarch/cores
mkdir -p /home/archr/.config/retroarch/saves
mkdir -p /home/archr/.config/retroarch/states
mkdir -p /home/archr/.config/retroarch/screenshots
mkdir -p /roms
chown -R archr:archr /home/archr

# Fix RetroArch core info cache: allow archr to write cache file
# Without this, RetroArch logs "Failed to write core info cache file" every launch
mkdir -p /usr/share/libretro/info
chmod 777 /usr/share/libretro/info

# Ensure mbedtls .so symlinks exist (RetroArch links against libmbedtls.so.21)
# Package updates may change the .so version; create compat symlinks
for lib in libmbedtls libmbedcrypto libmbedx509; do
    LATEST=$(ls /usr/lib/${lib}.so.* 2>/dev/null | sort -V | tail -1)
    if [ -n "$LATEST" ]; then
        # Create .so.21 symlink if it doesn't exist (RetroArch v1.22.2 expects it)
        [ ! -e /usr/lib/${lib}.so.21 ] && ln -sf "$(basename "$LATEST")" /usr/lib/${lib}.so.21
    fi
done

# Add ROMS partition to fstab (firstboot creates the partition)
# Note: build-image.sh overwrites fstab with final version, this is a fallback
if ! grep -q '/roms' /etc/fstab; then
    echo '# ROMS partition (created by firstboot)'  >> /etc/fstab
    echo 'LABEL=ROMS  /roms  vfat  defaults,utf8,noatime,uid=1001,gid=1001,nofail,x-systemd.device-timeout=10s  0  0' >> /etc/fstab
fi

# Firstboot service
cat > /etc/systemd/system/firstboot.service << 'FB_EOF'
[Unit]
Description=Arch R First Boot Setup
After=local-fs.target
Before=emulationstation.service
ConditionPathExists=!/var/lib/archr/.first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FB_EOF

systemctl enable firstboot

# Variant sync: copies variant marker from BOOT → /etc/archr/variant
# Only runs if /etc/archr/variant doesn't exist yet (no-panel images flashed by Flasher)
cat > /etc/systemd/system/archr-variant-sync.service << 'VARSYNC_EOF'
[Unit]
Description=Sync variant from BOOT partition
After=local-fs.target
RequiresMountsFor=/boot
ConditionPathExists=!/etc/archr/variant

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test -f /boot/variant && mkdir -p /etc/archr && cp /boot/variant /etc/archr/variant'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
VARSYNC_EOF

systemctl enable archr-variant-sync

# EmulationStation launch — PRIMARY: systemd service (created by build-emulationstation.sh)
# FALLBACK: autologin + .bash_profile (if ES service not installed)
# The emulationstation.service Conflicts with getty@tty1, so only one runs.
# Autologin override below is kept as fallback for manual/debug scenarios.

# Boot-time setup service (runs as root before ES: GPU + governors + DRM + runtime dir)
# DefaultDependencies=no + After=udevd → starts ASAP after devices appear
cat > /etc/systemd/system/archr-boot-setup.service << 'BOOTSETUP_SVC'
[Unit]
Description=Arch R Boot Setup
DefaultDependencies=no
After=systemd-udevd.service
Before=emulationstation.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe panfrost 2>/dev/null; mkdir -p /run/user/1001 && chown 1001:1001 /run/user/1001; echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; echo performance > /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/governor 2>/dev/null'

[Install]
WantedBy=multi-user.target
BOOTSETUP_SVC

systemctl enable archr-boot-setup

# .bash_profile for archr — launches EmulationStation on tty1 only
# exec replaces the shell process (saves memory, cleaner process tree)
cat > /home/archr/.bash_profile << 'PROFILE_EOF'
# Arch R: Auto-launch EmulationStation on tty1
if [ "$(tty)" = "/dev/tty1" ]; then
    echo "$(cut -d' ' -f1 /proc/uptime) bash_profile_start" >> /tmp/boot-timeline.txt
    exec /usr/bin/emulationstation/emulationstation.sh
fi
PROFILE_EOF
chown archr:archr /home/archr/.bash_profile

# Boot splash: handled by initramfs (archr-init with embedded BMP).
# Initramfs displays splash at ~0.7s after kernel start, before systemd.
# No systemd service needed — splash persists until ES takes DRM master.
systemctl disable splash 2>/dev/null || true
systemctl disable archr-splash 2>/dev/null || true
rm -f /etc/systemd/system/splash.service /etc/systemd/system/archr-splash.service

# Battery LED warning service
cat > /etc/systemd/system/battery-led.service << 'BATT_EOF'
[Unit]
Description=Arch R Battery LED Warning
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/batt_life_warning.py
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
BATT_EOF

systemctl enable battery-led

# Hotkey daemon (volume/brightness)
cat > /etc/systemd/system/archr-hotkeys.service << 'HK_EOF'
[Unit]
Description=Arch R Hotkey Daemon (volume/brightness)
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/archr-hotkeys.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
HK_EOF

systemctl enable archr-hotkeys

# Boot timing capture — Type=simple + background fork so it doesn't block boot completion!
# Previous Type=oneshot was self-defeating: sleep 3s → systemd-analyze says "not yet finished"
# because the boot-timing service ITSELF was still a pending job.
cat > /etc/systemd/system/boot-timing.service << 'TIMING_EOF'
[Unit]
Description=Capture boot timing
After=emulationstation.service
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash -c '\
    sleep 15; \
    { \
        echo "=== Boot Timing ==="; \
        systemd-analyze 2>&1 || true; \
        echo ""; \
        echo "=== Blame (top 20) ==="; \
        systemd-analyze blame --no-pager 2>&1 | head -20 || true; \
        echo ""; \
        echo "=== Critical Chain ==="; \
        systemd-analyze critical-chain --no-pager 2>&1 || true; \
        echo ""; \
        echo "=== ES Timeline ==="; \
        cat /home/archr/es-timeline.txt 2>/dev/null || echo "no timeline"; \
        echo ""; \
        echo "=== ES Debug (profiling) ==="; \
        grep "\\[BOOT" /home/archr/es-debug.log 2>/dev/null || echo "no profiling"; \
        echo ""; \
        echo "=== boot_setup marker ==="; \
        cat /tmp/boot-timeline.txt 2>/dev/null || echo "no marker"; \
    } > /boot/boot-timing.txt 2>&1; \
    chmod 644 /boot/boot-timing.txt'

[Install]
WantedBy=multi-user.target
TIMING_EOF

systemctl enable boot-timing

# Debug dump: comprehensive system info to /boot/debug.log (readable from PC)
cat > /etc/systemd/system/archr-debug-dump.service << 'DEBUG_EOF'
[Unit]
Description=Arch R Debug Dump
After=emulationstation.service
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    sleep 20; \
    { \
        echo "=== Arch R Debug Dump ($(date)) ==="; \
        echo ""; \
        echo "--- Kernel ---"; \
        uname -a; \
        echo ""; \
        echo "--- Input Devices ---"; \
        for d in /dev/input/event*; do \
            name=$(cat /sys/class/input/$(basename $d)/device/name 2>/dev/null); \
            echo "  $d: $name"; \
        done; \
        echo ""; \
        echo "--- DRM ---"; \
        for c in /sys/class/drm/card*/status; do \
            echo "  $c: $(cat $c 2>/dev/null)"; \
        done; \
        cat /sys/class/drm/card*/modes 2>/dev/null | head -5; \
        echo ""; \
        echo "--- Backlight ---"; \
        for bl in /sys/class/backlight/*/; do \
            echo "  $(basename $bl): cur=$(cat ${bl}brightness 2>/dev/null) max=$(cat ${bl}max_brightness 2>/dev/null)"; \
        done; \
        echo ""; \
        echo "--- ALSA Controls ---"; \
        amixer scontrols 2>/dev/null || echo "  (no ALSA)"; \
        echo ""; \
        echo "--- CPU/GPU ---"; \
        echo "  CPU: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)kHz ($(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null))"; \
        echo "  GPU: $(cat /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/cur_freq 2>/dev/null)Hz"; \
        echo "  Temp: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"; \
        echo ""; \
        echo "--- Memory ---"; \
        free -h; \
        echo ""; \
        echo "--- Loaded Modules ---"; \
        lsmod 2>/dev/null | head -30; \
        echo ""; \
        echo "--- Failed Services ---"; \
        systemctl --failed --no-pager 2>/dev/null; \
        echo ""; \
        echo "--- dmesg errors ---"; \
        dmesg -l err,warn 2>/dev/null | tail -30; \
    } > /boot/debug.log 2>&1; \
    chmod 644 /boot/debug.log'

[Install]
WantedBy=multi-user.target
DEBUG_EOF

systemctl enable archr-debug-dump

# USB auto-mount service (triggered by udev on device insertion)
cat > /etc/systemd/system/archr-automount.service << 'AUTOMOUNT_SVC'
[Unit]
Description=Arch R USB Auto-Mount

[Service]
Type=oneshot
ExecStart=/usr/local/bin/archr-automount mount
AUTOMOUNT_SVC

# Save config on shutdown (backs up ALSA state, brightness, WiFi to /boot)
cat > /etc/systemd/system/archr-save-config.service << 'SAVECONF_SVC'
[Unit]
Description=Arch R Save Config
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/archr-save-config backup

[Install]
WantedBy=shutdown.target
SAVECONF_SVC

systemctl enable archr-save-config

# Bluetooth auto-pairing agent (runs alongside bluetoothd)
cat > /etc/systemd/system/archr-bluetooth-agent.service << 'BTAGENT_SVC'
[Unit]
Description=Arch R Bluetooth Agent
After=bluetooth.service
PartOf=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/local/bin/archr-bluetooth-agent
Restart=on-failure
RestartSec=10

[Install]
WantedBy=bluetooth.target
BTAGENT_SVC

systemctl enable archr-bluetooth-agent

# Sleep configuration (suspend disabled by default, user enables via archr-suspend-mode)
mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/archr.conf << 'SLEEP_CONF'
[Sleep]
AllowSuspend=yes
SuspendState=mem
AllowHibernation=no
SLEEP_CONF

# Modules blacklist for sleep (unloaded before suspend by archr-sleep hook)
mkdir -p /etc/archr
install -m 644 /tmp/modules.bad /etc/archr/modules.bad 2>/dev/null || true

# Delete stock ALARM initramfs and kernel (we use our own kernel + initramfs)
# Our initramfs.img is built by build-image.sh and placed on BOOT partition
rm -f /boot/initramfs-linux.img /boot/Image /boot/Image.gz 2>/dev/null

# Clean kernel modules: remove media tuners (154 modules, 13MB — useless for gaming)
rm -rf /lib/modules/*/kernel/drivers/media 2>/dev/null
rm -rf /lib/modules/*/kernel/drivers/misc 2>/dev/null
depmod -a 2>/dev/null || true

# Pre-seed random seed (even though random-seed service is masked)
mkdir -p /var/lib/systemd
dd if=/dev/urandom of=/var/lib/systemd/random-seed bs=512 count=1 2>/dev/null
chmod 600 /var/lib/systemd/random-seed

# Sudoers for perfmax/perfnorm/pmic-poweroff (allow archr to run without password)
echo "archr ALL=(ALL) NOPASSWD: /usr/local/bin/perfmax, /usr/local/bin/perfnorm, /usr/local/bin/pmic-poweroff, /usr/local/bin/input-merge, /usr/local/bin/archr-gptokeyb, /usr/local/bin/archr-factory-reset, /usr/local/bin/archr-suspend-mode, /usr/local/bin/archr-usbgadget, /usr/bin/kill, /usr/bin/ln, /usr/bin/dmesg, /usr/bin/chvt, /usr/bin/cp, /usr/bin/chmod, /usr/bin/tee, /usr/bin/systemctl, /bin/bash" > /etc/sudoers.d/archr-perf
chmod 440 /etc/sudoers.d/archr-perf

# Allow archr to use negative nice values (needed for nice -n -19 in ES launch commands)
echo "archr  -  nice  -20" >> /etc/security/limits.conf

# Distro version info
cat > /etc/archr-release << 'VER_EOF'
NAME="Arch R"
VERSION="1.0"
ID=archr
ID_LIKE=arch
BUILD_DATE="$(date +%Y-%m-%d)"
VARIANT="R36S"
VER_EOF

# Auto-login on tty1 — fast ES launch path
# --skip-login: bypass /bin/login entirely (no PAM, no visible login prompt)
# --noissue/--noclear: skip /etc/issue, keep splash on screen
# Type=simple: base getty@.service has Type=idle (waits for ALL jobs). Override to simple.
# ExecStartPre: blank VT text layer (black-on-black) so no text flickers on screen
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AL_EOF'
[Service]
ExecStartPre=-/bin/bash -c 'printf "\033[2J\033[H\033[?25l\033[30;40m" > /dev/tty1 2>/dev/null'
ExecStart=
ExecStart=-/sbin/agetty --autologin archr --skip-login --noclear --noissue %I $TERM
Type=simple
StandardInput=tty
StandardOutput=tty
TTYVTDisallocate=no
AL_EOF

# Journald size limit (save memory)
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf << 'JD_EOF'
[Journal]
SystemMaxUse=16M
RuntimeMaxUse=16M
JD_EOF

# Suppress login messages (silent boot)
touch /home/archr/.hushlogin
chown archr:archr /home/archr/.hushlogin

# logind: minimize overhead for single-user gaming device
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/fast.conf << 'LOGIND_EOF'
[Login]
NAutoVTs=1
ReserveVT=0
HandlePowerKey=suspend
HandleSuspendKey=suspend
HandleHibernateKey=ignore
HandleLidSwitch=ignore
KillUserProcesses=no
UserStopDelaySec=0
LOGIND_EOF

# user@.service: defer systemd user session (off critical path)
mkdir -p /etc/systemd/system/user@.service.d
cat > /etc/systemd/system/user@.service.d/fast-boot.conf << 'USER_EOF'
[Unit]
After=local-fs.target
USER_EOF

# Pre-create build-time configs (saves ~1s of shell fork/exec at ES startup)
# .drirc — suppresses Mesa warnings about missing per-app config
echo '<?xml version="1.0"?><driconf/>' > /home/archr/.drirc
chown archr:archr /home/archr/.drirc
# Mesa shader cache dir
mkdir -p /home/archr/.cache/mesa_shader_cache
chown -R archr:archr /home/archr/.cache

#------------------------------------------------------------------------------
# System Optimization
#------------------------------------------------------------------------------
echo "=== System Optimization ==="

# Note: tmpfs entries for /tmp and /var/log are set in build-image.sh's fstab
# (build-image.sh creates a fresh fstab that overrides what's in the rootfs)

# ======================================================================
# BOOT SPEED OPTIMIZATION
# ArkOS/dArkOS boot in ~3s. Full systemd with default ALARM services
# adds 15-30s of unnecessary overhead. Disable/mask everything not needed.
# ======================================================================

# Disable services that are not needed on this device
systemctl disable lvm2-monitor 2>/dev/null || true
systemctl mask lvm2-lvmpolld.service lvm2-lvmpolld.socket 2>/dev/null || true

# Network wait services — BIGGEST boot blocker! Waits for network that
# doesn't exist (no WiFi configured) = 5-30s timeout on EACH boot.
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# systemd-networkd conflicts with NetworkManager — only need one.
# NM is used for WiFi config UI. Networkd is server-oriented.
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl disable systemd-network-generator.service 2>/dev/null || true

# systemd-resolved — DNS resolver, overkill for embedded gaming device.
# NM handles DNS directly. Use /etc/resolv.conf as fallback.
systemctl disable systemd-resolved.service 2>/dev/null || true
rm -f /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf

# sshd — not useful until WiFi is configured. Can enable later.
systemctl disable sshd.service 2>/dev/null || true

# Mask ConditionNeedsUpdate services — caches are pre-built during
# rootfs creation. Without masking, any file change in /usr/ (deploying
# new cores, scripts, etc.) makes /usr newer than the update markers,
# triggering full ldconfig/hwdb/catalog rebuild on EVERY boot.
systemctl mask ldconfig.service 2>/dev/null || true
systemctl mask systemd-hwdb-update.service 2>/dev/null || true
systemctl mask systemd-journal-catalog-update.service 2>/dev/null || true
systemctl mask systemd-sysusers.service 2>/dev/null || true

# Mask slow boot services (saves ~12s on ARM)
# systemd-random-seed: blocks 6s+ waiting for entropy (no HW RNG on RK3326)
systemctl mask systemd-random-seed.service 2>/dev/null || true
# Debug/tracing/config/fuse mounts: ~3s total, not needed for gaming
systemctl mask sys-kernel-debug.mount sys-kernel-tracing.mount \
    sys-kernel-config.mount sys-fs-fuse-connections.mount 2>/dev/null || true
# Journal flush, vconsole, backlight, hostnamed: ~1.6s total
systemctl mask systemd-journal-flush.service systemd-vconsole-setup.service \
    "systemd-backlight@backlight:backlight.service" \
    systemd-hostnamed.service 2>/dev/null || true
# utmp, modules-load, binfmt, machine-id, pstore, sysext, time-sync, resolved, networkd
systemctl mask systemd-update-utmp.service systemd-update-utmp-runlevel.service \
    systemd-modules-load.service systemd-binfmt.service \
    systemd-machine-id-commit.service systemd-pstore.service \
    systemd-sysext.service systemd-confext.service \
    systemd-time-wait-sync.service systemd-timesyncd.service \
    systemd-networkd.service systemd-resolved.service \
    audit-rules.service auditd.service lastlog2-import.service \
    mkinitcpio-generate-shutdown-ramfs.service \
    alsa-restore.service 2>/dev/null || true
# alsa-restore: ES handles ALSA init (amixer sset), alsa-restore just loads asound.state

# Mask sockets not needed on R36S (saves socket activation overhead)
for sock in \
    polkit-agent-helper.socket systemd-factory-reset.socket \
    systemd-mute-console.socket systemd-bootctl.socket \
    systemd-creds.socket systemd-repart.socket \
    systemd-importd.socket systemd-machined.socket \
    systemd-hostnamed.socket \
    systemd-rfkill.socket dm-event.socket \
    systemd-coredump.socket systemd-sysext.socket \
    systemd-ask-password-wall.socket \
    dirmngr@etc-pacman.d-gnupg.socket \
    keyboxd@etc-pacman.d-gnupg.socket \
    gpg-agent@etc-pacman.d-gnupg.socket \
    gpg-agent-ssh@etc-pacman.d-gnupg.socket \
    gpg-agent-browser@etc-pacman.d-gnupg.socket \
    gpg-agent-extra@etc-pacman.d-gnupg.socket; do
    systemctl mask "$sock" 2>/dev/null || true
done

# Disable NetworkManager from boot entirely — it adds 2-6s waiting for non-existent WiFi.
# User enables it manually when they want WiFi: systemctl enable --now NetworkManager
systemctl disable NetworkManager.service 2>/dev/null || true

# Mask udev rules not applicable to R36S (reduces udev coldplug time)
mkdir -p /etc/udev/rules.d
for rule in 60-cdrom_id 60-dmi-id 60-fido-id 60-infiniband \
    60-persistent-storage-mtd 60-persistent-storage-tape 60-persistent-v4l \
    60-sensor 60-serial 60-tpm-udev 64-btrfs 65-libwacom 70-camera \
    70-infrared 70-touchpad 75-probe_mtd 81-net-bridge 81-net-dhcp \
    82-net-auto-link-local 90-image-dissect 90-iocost 90-vconsole \
    96-e2scrub 50-mali 10-dm 13-dm-disk 95-dm-notify; do
    ln -sf /dev/null "/etc/udev/rules.d/${rule}.rules"
done

# Allow input group to use /dev/uinput (needed by archr-gptokeyb and input-merge)
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' > /etc/udev/rules.d/99-archr-uinput.rules

# Pre-build caches NOW (inside chroot) so masks are safe
ldconfig 2>/dev/null || true
journalctl --update-catalog 2>/dev/null || true
systemd-hwdb update 2>/dev/null || true
# Pre-seed random entropy
dd if=/dev/urandom of=/var/lib/systemd/random-seed bs=512 count=1 2>/dev/null || true

# Update markers — must be NEWER than /usr to prevent NeedsUpdate triggers
touch /etc/.updated /var/.updated

# Disable Mali blob from ld.so.conf — use Mesa Panfrost instead
# Mali's old libgbm.so (2020) is incompatible with modern SDL3/sdl2-compat
# Mali libs stay in /usr/lib/mali-egl/ for manual use if needed
if [ -f /etc/ld.so.conf.d/mali.conf ]; then
    mv /etc/ld.so.conf.d/mali.conf /etc/ld.so.conf.d/mali.conf.disabled
    ldconfig
fi

# Suppress ALL kernel messages on console (0 = emergency only)
echo 'kernel.printk = 0 0 0 0' >> /etc/sysctl.d/99-archr.conf

# Fast shutdown: 2s timeout instead of default 90s
# On a handheld, no service needs 90s to stop gracefully
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/quick-shutdown.conf << 'SHUTDOWN_EOF'
[Manager]
DefaultTimeoutStopSec=2s
DefaultTimeoutAbortSec=2s
SHUTDOWN_EOF

# Faster TTY login (skip issue/motd)
echo "" > /etc/issue
echo "" > /etc/motd

# ALSA config for RK3326 (rk817 codec)
# Simple plug → hw:0,0 — no dmix needed (SDL_mixer handles mixing internally)
# dmix was causing issues with SDL_mixer; dArkOS also removes dmix for game launch
cat > /etc/asound.conf << 'ALSA_EOF'
# Arch R ALSA configuration for RK3326 (rk817 codec)
# Simple plug → hw:0,0 — no dmix needed (SDL_mixer handles mixing internally)
pcm.!default {
    type plug
    slave.pcm "hw:0,0"
}
ctl.!default {
    type hw
    card 0
}
ALSA_EOF

# Set default audio levels (rk817 BSP codec)
# ALSA simple mixer maps raw "DAC Playback Volume" to simple name "DAC"
# "Master" does NOT exist on rk817 — must use "DAC"
amixer -c 0 sset 'Playback Path' SPK 2>/dev/null || true
amixer -c 0 sset 'DAC' 80% 2>/dev/null || true

# Disable coredumps (save space)
echo 'kernel.core_pattern=|/bin/false' >> /etc/sysctl.d/99-archr.conf
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf << 'CORE_EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
CORE_EOF

# Network defaults (WiFi powersave off for lower latency)
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/archr.conf << 'NM_EOF'
[connection]
wifi.powersave=2
NM_EOF

# Clean package cache
pacman -Scc --noconfirm

# ======================================================================
# BLOAT REMOVAL — "Arch R deve ser leve como uma pluma"
# Gaming device needs runtime libs ONLY. Remove everything else.
# ======================================================================

echo "=== Bloat Removal ==="

# --- Firmware: keep only ARM + BT/WiFi USB dongles (782MB → 24MB) ---
FW="/usr/lib/firmware"
for dir in intel nvidia amdgpu ath11k ath12k ath10k i915 rtw89 \
    mediatek dpaa2 ti-connectivity cypress cirrus radeon cxgb4 xe \
    bnx2x ueagle-atm rsi nxp amlogic cnm ath6k ath9k_htc \
    HP LENOVO dell vxge atmel ar3k slicoss moxa amd amphion \
    amdnpu amdtee airoha meson aeonsemi go7007 bnx2 cxgb3 acenic \
    advansys edgeport dabusb ene-ub6250 tigon sb16 yam ttusb-budget \
    korg kaweth ess vicam dsp56k cpia2 av7110 adaptec sxg tehuti \
    myricom matrox cavium inside-secure ixp4xx wfx sdca powervr \
    isci e100 r128 ositech microchip imx keyspan keyspan_pda sun \
    ti-keystone cadence; do
    rm -rf "$FW/$dir" 2>/dev/null
done
# Remove individual firmware files for non-ARM hardware
find "$FW" -maxdepth 1 \( -name "*.bin" -o -name "*.fw" \) -size 0 -delete 2>/dev/null
rm -f "$FW"/iwlwifi-* "$FW"/phanfw.bin "$FW"/myri10ge_*.dat 2>/dev/null
rm -f "$FW"/hfi1_*.fw "$FW"/wil6210* "$FW"/s5p-mfc* "$FW"/wsm_22.bin 2>/dev/null
rm -f "$FW"/sms1xxx-*.fw "$FW"/dvb-*.fw "$FW"/v4l-*.fw 2>/dev/null
rm -f "$FW"/agere_*.bin "$FW"/isdbt_*.inp "$FW"/dvb_*.inp "$FW"/cmmb_*.inp "$FW"/tdmb_*.inp 2>/dev/null
rm -f "$FW"/lbtf_usb.bin "$FW"/ar5523.bin "$FW"/ar9170-*.fw "$FW"/ar7010*.fw 2>/dev/null
rm -f "$FW"/htc_*.fw "$FW"/f2255usb.bin "$FW"/tlg2300_firmware.bin 2>/dev/null
rm -f "$FW"/rcar_gen4_pcie.bin "$FW"/lt9611uxc_fw.bin "$FW"/tsse_firmware.bin 2>/dev/null
rm -f "$FW"/ctefx.bin "$FW"/ctspeq.bin "$FW"/ath3k-1.fw "$FW"/carl9170-*.fw 2>/dev/null
rm -f "$FW"/qat_*.bin "$FW"/r8a779x_*.dlmem "$FW"/usbdux*.bin "$FW"/whiteheat*.fw 2>/dev/null
rm -f "$FW"/TAS2XXX*.bin "$FW"/TXNW*.bin "$FW"/TIAS*.bin "$FW"/INT8866*.bin 2>/dev/null
echo "  Firmware cleaned (kept: rockchip, brcm, rtl_bt, qca, rtw88, arm)"

# --- Headers: NEVER needed at runtime (420MB) ---
rm -rf /usr/include && mkdir -p /usr/include
echo "  Removed /usr/include"

# --- Documentation (150MB + 75MB + 11MB) ---
rm -rf /usr/share/doc /usr/share/man /usr/share/info /usr/share/gtk-doc
mkdir -p /usr/share/doc
echo "  Removed docs/man/info"

# --- Locales: keep only en_US, pt_BR (213MB → 9MB) ---
cd /usr/share/locale
for d in */; do
    d="${d%/}"
    case "$d" in en|en_US|pt|pt_BR|locale.alias) continue ;; *) rm -rf "$d" ;; esac
done
# i18n: keep only needed locale definitions
cd /usr/share/i18n/locales 2>/dev/null
for f in *; do
    case "$f" in en_US|en_GB|pt_BR|POSIX|i18n|iso14651_t1|iso14651_t1_common|translit_*) continue ;; *) rm -f "$f" ;; esac
done
echo "  Locales cleaned (kept: en_US, pt_BR)"

# --- Build tools: compilers, linkers, static libs ---
rm -rf /usr/lib/gcc /usr/lib/clang
rm -f /usr/lib/libclang-cpp.so* /usr/lib/libclang.so*
rm -f /usr/lib/libgo.so* /usr/lib/libgphobos.so* /usr/lib/libgdruntime.so*
rm -f /usr/lib/libgfortran.so*
rm -f /usr/lib/libasan.so* /usr/lib/libtsan.so* /usr/lib/libubsan.so* /usr/lib/liblsan.so*
rm -f /usr/lib/libteflon.so*
find /usr/lib -name "*.a" -delete 2>/dev/null
echo "  Removed compilers, static libs, sanitizers"

# --- Unused libraries ---
rm -rf /usr/lib/mali-egl   # Mali proprietary (using Panfrost)
rm -rf /usr/lib/guile /usr/lib/glycin-loaders /usr/lib/vlc
rm -rf /usr/lib/qt6 /usr/lib/qt /usr/lib/cmake /usr/lib/git-core
rm -f /usr/lib/libguile* /usr/lib/libQt5*.so* /usr/lib/libQt6*.so*
# VLC: remove full library but KEEP libvlc.so.5 stub — ES links against it at load time!
# ES handles libvlc_new() returning NULL gracefully (just skips video backgrounds)
rm -f /usr/lib/libvlccore*.so*
# Replace full libvlc with a minimal stub (no-op functions, ~68KB vs 15MB+)
# The stub is cross-compiled and stored in the project
if [ -f /tmp/libvlc-stub.so ]; then
    cp /tmp/libvlc-stub.so /usr/lib/libvlc.so.5.6.0
    ln -sf libvlc.so.5.6.0 /usr/lib/libvlc.so.5
    ln -sf libvlc.so.5 /usr/lib/libvlc.so
    rm -f /usr/lib/libvlc.so.5.6.1 2>/dev/null  # remove real one if exists
else
    # Fallback: keep one libvlc.so.5 if it exists from pacman
    echo "  WARNING: libvlc stub not found at /tmp/libvlc-stub.so — keeping system libvlc"
fi
echo "  Removed: mali-egl, guile, vlccore, qt, git, cmake, glycin"

# --- Unused binaries ---
for bin in gcc g++ cc c++ cpp gccgo go gofmt \
    clang clangd clang++ clang-format clang-tidy c-index-test \
    cmake cmake-gui ctest cpack ccmake \
    make gmake perl perl5 guile guild git git-upload-pack git-receive-pack \
    ld ld.bfd ld.gold as objdump objcopy strip ranlib ar nm readelf \
    c++filt addr2line size strings gprof flex bison yacc m4 \
    autoconf automake autoreconf aclocal autoheader autoscan \
    libtool libtoolize pkg-config pkgconf \
    xgettext msgfmt msgmerge msginit gettext ngettext envsubst \
    obj2yaml rsvg-convert vlc cvlc nvlc rvlc svlc; do
    rm -f "/usr/bin/$bin" 2>/dev/null
done
rm -f /usr/bin/llvm-* /usr/bin/clang-* /usr/bin/yaml2obj 2>/dev/null
echo "  Removed build/tool binaries"

# --- Unused share data ---
rm -rf /usr/share/cmake /usr/share/guile /usr/share/gir-1.0 /usr/share/groff
rm -rf /usr/share/qt6 /usr/share/qt /usr/share/perl5
echo "  Removed unused share data"

# --- Python cleanup (keep runtime, remove IDE/test/build) ---
PY="/usr/lib/python3.14"
rm -rf "$PY/config-3.14-aarch64-linux-gnu" "$PY/idlelib" "$PY/ensurepip"
rm -rf "$PY/test" "$PY/unittest" "$PY/tkinter" "$PY/turtle"* "$PY/turtledemo"
rm -rf "$PY/distutils" "$PY/pydoc"* "$PY/lib2to3" "$PY/doctest.py"
find "$PY" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
echo "  Python cleaned (kept runtime only)"

# --- Mask systemd generators (50-100ms boot gain) ---
GENDIR="/etc/systemd/system-generators"
mkdir -p "$GENDIR"
for gen in systemd-cryptsetup-generator systemd-gpt-auto-generator \
    systemd-debug-generator systemd-hibernate-resume-generator \
    systemd-bless-boot-generator systemd-factory-reset-generator \
    systemd-import-generator systemd-integritysetup-generator \
    systemd-veritysetup-generator systemd-ssh-generator \
    systemd-tpm2-generator systemd-run-generator \
    systemd-system-update-generator; do
    ln -sf /dev/null "$GENDIR/$gen"
done
mkdir -p /etc/systemd/user-generators
ln -sf /dev/null /etc/systemd/user-generators/systemd-xdg-autostart-generator
echo "  Masked 14 systemd generators"

# --- Mask unnecessary sockets ---
for sock in systemd-networkd.socket systemd-networkd-varlink.socket \
    systemd-networkd-resolve-hook.socket systemd-userdbd.socket \
    systemd-resolved-monitor.socket systemd-resolved-varlink.socket; do
    ln -sf /dev/null "/etc/systemd/system/$sock"
done
rm -rf /etc/systemd/system/sockets.target.wants
echo "  Masked unnecessary socket activations"

# --- Mask unnecessary services and timers ---
ln -sf /dev/null /etc/systemd/system/polkit.service
ln -sf /dev/null /etc/systemd/system/systemd-userdbd.service
ln -sf /dev/null /etc/systemd/system/archlinux-keyring-wkd-sync.timer
echo "  Masked polkit, userdbd, keyring-sync timer"

# --- Fix PAM: remove pam_access.so reference (module deleted in bloat cleanup) ---
# pam_access.so provides host/network-based access control — not needed on gaming handheld
# Without this fix, login fails with "Module is unknown" → autologin loop
sed -i '/pam_access.so/d' /etc/pam.d/system-login 2>/dev/null
echo "  Fixed PAM: removed pam_access.so reference"

echo "=== Bloat removal complete ==="

echo "=== Chroot setup complete ==="
SETUP_EOF

chmod +x "$ROOTFS_DIR/tmp/setup.sh"

# Copy libvlc stub into chroot (needed by bloat cleanup — ES links against libvlc.so.5)
cp "$SCRIPT_DIR/scripts/libvlc-stub-aarch64.so" "$ROOTFS_DIR/tmp/libvlc-stub.so"

# Copy modules.bad into chroot (installed by setup.sh to /etc/archr/)
cp "$SCRIPT_DIR/config/modules.bad" "$ROOTFS_DIR/tmp/modules.bad"

# Run setup inside chroot
log "  Running setup inside chroot..."
chroot "$ROOTFS_DIR" /tmp/setup.sh

log "  ✓ System configured"

#------------------------------------------------------------------------------
# Step 5: Install Arch R Scripts and Configs
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing Arch R scripts and configs..."

# Performance scripts
install -m 755 "$SCRIPT_DIR/scripts/perfmax" "$ROOTFS_DIR/usr/local/bin/perfmax"
install -m 755 "$SCRIPT_DIR/scripts/perfnorm" "$ROOTFS_DIR/usr/local/bin/perfnorm"
install -m 755 "$SCRIPT_DIR/scripts/pmic-poweroff" "$ROOTFS_DIR/usr/local/bin/pmic-poweroff"
install -m 755 "$SCRIPT_DIR/scripts/retroarch-launch.sh" "$ROOTFS_DIR/usr/local/bin/retroarch-launch"
# RetroArch core options (per-core tuning for RK3326)
install -m 644 "$SCRIPT_DIR/config/retroarch-core-options.cfg" "$ROOTFS_DIR/home/archr/.config/retroarch/retroarch-core-options.cfg"
log "  ✓ RetroArch core options installed"
# Input merger daemon: combines gpio-keys + adc-joystick into single virtual device
# RetroArch needs all inputs on one device (udev driver assigns each to separate port)
if command -v aarch64-linux-gnu-gcc &>/dev/null; then
    aarch64-linux-gnu-gcc -static -O2 -o "$ROOTFS_DIR/usr/local/bin/input-merge" \
        "$SCRIPT_DIR/scripts/input-merge.c"
    chmod 755 "$ROOTFS_DIR/usr/local/bin/input-merge"
    log "  ✓ input-merge compiled and installed"
    # Gamepad-to-keyboard mapper for Linux ports (compatible with ROCKNIX .gptk configs)
    aarch64-linux-gnu-gcc -static -O2 -o "$ROOTFS_DIR/usr/local/bin/archr-gptokeyb" \
        "$SCRIPT_DIR/scripts/archr-gptokeyb.c"
    chmod 755 "$ROOTFS_DIR/usr/local/bin/archr-gptokeyb"
    log "  ✓ archr-gptokeyb compiled and installed"
else
    warn "aarch64-linux-gnu-gcc not found — input-merge/gptokeyb not compiled"
fi
# gptokeyb config files
mkdir -p "$ROOTFS_DIR/etc/archr/gptokeyb"
install -m 644 "$SCRIPT_DIR/config/gptokeyb/default.gptk" "$ROOTFS_DIR/etc/archr/gptokeyb/default.gptk"
install -m 644 "$SCRIPT_DIR/config/gptokeyb/tools.gptk" "$ROOTFS_DIR/etc/archr/gptokeyb/tools.gptk"
log "  ✓ gptokeyb configs installed (default + tools)"
# RetroArch joypad autoconfig (merged device + individual fallbacks)
mkdir -p "$ROOTFS_DIR/usr/share/retroarch/autoconfig/udev"
install -m 644 "$SCRIPT_DIR/config/autoconfig/udev/archr-gamepad.cfg" "$ROOTFS_DIR/usr/share/retroarch/autoconfig/udev/"
install -m 644 "$SCRIPT_DIR/config/autoconfig/udev/gpio-keys.cfg" "$ROOTFS_DIR/usr/share/retroarch/autoconfig/udev/"
install -m 644 "$SCRIPT_DIR/config/autoconfig/udev/adc-joystick.cfg" "$ROOTFS_DIR/usr/share/retroarch/autoconfig/udev/"
# systemd shutdown hook — runs pmic-poweroff at the very end of shutdown sequence
# (after all services stopped + filesystems unmounted, before kernel halt)
mkdir -p "$ROOTFS_DIR/usr/lib/systemd/system-shutdown"
install -m 755 "$SCRIPT_DIR/scripts/pmic-shutdown-hook" "$ROOTFS_DIR/usr/lib/systemd/system-shutdown/pmic-poweroff"
log "  ✓ Performance + power-off scripts installed (including systemd shutdown hook)"

# ES info bar scripts (called by ES-fcamod for status display)
install -m 755 "$SCRIPT_DIR/scripts/current_volume" "$ROOTFS_DIR/usr/local/bin/current_volume"
install -m 755 "$SCRIPT_DIR/scripts/current_brightness" "$ROOTFS_DIR/usr/local/bin/current_brightness"
log "  ✓ ES info bar scripts installed (current_volume, current_brightness)"

# ES-fcamod dArkOS compatibility scripts (timezones, auto-suspend)
install -m 755 "$SCRIPT_DIR/scripts/timezones" "$ROOTFS_DIR/usr/local/bin/timezones"
install -m 755 "$SCRIPT_DIR/scripts/auto_suspend_update.sh" "$ROOTFS_DIR/usr/local/bin/auto_suspend_update.sh"
log "  ✓ ES compatibility scripts installed (timezones, auto_suspend_update.sh)"

# System management scripts
install -m 755 "$SCRIPT_DIR/scripts/archr-automount" "$ROOTFS_DIR/usr/local/bin/archr-automount"
install -m 755 "$SCRIPT_DIR/scripts/archr-usbgadget" "$ROOTFS_DIR/usr/local/bin/archr-usbgadget"
install -m 755 "$SCRIPT_DIR/scripts/archr-bluetooth-agent" "$ROOTFS_DIR/usr/local/bin/archr-bluetooth-agent"
install -m 755 "$SCRIPT_DIR/scripts/archr-factory-reset" "$ROOTFS_DIR/usr/local/bin/archr-factory-reset"
install -m 755 "$SCRIPT_DIR/scripts/archr-suspend-mode" "$ROOTFS_DIR/usr/local/bin/archr-suspend-mode"
install -m 755 "$SCRIPT_DIR/scripts/archr-save-config" "$ROOTFS_DIR/usr/local/bin/archr-save-config"
install -m 755 "$SCRIPT_DIR/scripts/archr-memory-manager" "$ROOTFS_DIR/usr/local/bin/archr-memory-manager"
log "  ✓ System management scripts installed"

# System sleep hook (called by systemd on suspend/resume)
mkdir -p "$ROOTFS_DIR/usr/lib/systemd/system-sleep"
install -m 755 "$SCRIPT_DIR/scripts/archr-sleep" "$ROOTFS_DIR/usr/lib/systemd/system-sleep/archr-sleep"
log "  ✓ Sleep hook installed"

# ES Tools shared menu library (sourced by tool scripts)
mkdir -p "$ROOTFS_DIR/usr/lib/archr"
install -m 644 "$SCRIPT_DIR/scripts/opt-system/menu-lib.sh" "$ROOTFS_DIR/usr/lib/archr/menu-lib.sh"

# ES Tools menu scripts (shown in ES OPTIONS menu via GuiTools)
mkdir -p "$ROOTFS_DIR/opt/system"
for script in "$SCRIPT_DIR/scripts/opt-system/"*.sh; do
    [ -f "$script" ] || continue
    [ "$(basename "$script")" = "menu-lib.sh" ] && continue
    install -m 755 "$script" "$ROOTFS_DIR/opt/system/$(basename "$script")"
done
log "  ✓ ES Tools menu scripts installed (/opt/system/)"

# Udev rules
mkdir -p "$ROOTFS_DIR/etc/udev/rules.d"
install -m 644 "$SCRIPT_DIR/config/udev/99-archr-automount.rules" "$ROOTFS_DIR/etc/udev/rules.d/99-archr-automount.rules"
install -m 644 "$SCRIPT_DIR/config/udev/80-archr-usbgadget.rules" "$ROOTFS_DIR/etc/udev/rules.d/80-archr-usbgadget.rules"
log "  ✓ Udev rules installed (automount, usbgadget)"

# Install prebuilt libretro cores (not available in ALARM repos)
PREBUILT_CORES="$SCRIPT_DIR/prebuilt/cores"
if [ -d "$PREBUILT_CORES" ]; then
    mkdir -p "$ROOTFS_DIR/usr/lib/libretro"
    for core in "$PREBUILT_CORES"/*_libretro.so; do
        [ -f "$core" ] || continue
        install -m 644 "$core" "$ROOTFS_DIR/usr/lib/libretro/"
        log "  Prebuilt core: $(basename "$core")"
    done
fi

# Distro version for ES info bar (ES reads title= from this file)
mkdir -p "$ROOTFS_DIR/usr/share/plymouth/themes"
echo "title=Arch R v1.0 ($(date +%Y-%m-%d))" > "$ROOTFS_DIR/usr/share/plymouth/themes/text.plymouth"
log "  ✓ Distro version installed (text.plymouth)"

# First boot script
install -m 755 "$SCRIPT_DIR/scripts/first-boot.sh" "$ROOTFS_DIR/usr/local/bin/first-boot.sh"
log "  ✓ First boot script installed"

# Boot splash: no binary needed in rootfs — splash is embedded in initramfs /init
# (built by build-image.sh: archr-init.c + embedded splash BMP → initramfs.img)

# RetroArch config (install to user's config dir where retroarch expects it)
mkdir -p "$ROOTFS_DIR/home/archr/.config/retroarch"
cp "$SCRIPT_DIR/config/retroarch.cfg" "$ROOTFS_DIR/home/archr/.config/retroarch/retroarch.cfg"
log "  ✓ RetroArch config installed"

# Archr system config directory
mkdir -p "$ROOTFS_DIR/etc/archr"

# SDL GameController DB for R36S (gpio-keys + adc-joystick)
cp "$SCRIPT_DIR/config/gamecontrollerdb.txt" "$ROOTFS_DIR/etc/archr/gamecontrollerdb.txt"
log "  ✓ GameController DB installed"

# EmulationStation configs
mkdir -p "$ROOTFS_DIR/etc/emulationstation"
if [ -f "$SCRIPT_DIR/config/es_systems.cfg" ]; then
    cp "$SCRIPT_DIR/config/es_systems.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ ES systems config installed"
fi
if [ -f "$SCRIPT_DIR/config/es_input.cfg" ]; then
    cp "$SCRIPT_DIR/config/es_input.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ ES input config installed (gpio-keys + adc-joystick)"
fi

# Battery LED warning script
install -m 755 "$SCRIPT_DIR/scripts/batt_life_warning.py" "$ROOTFS_DIR/usr/local/bin/batt_life_warning.py"
log "  ✓ Battery LED script installed"

# Hotkey daemon (volume/brightness control)
install -m 755 "$SCRIPT_DIR/scripts/archr-hotkeys.py" "$ROOTFS_DIR/usr/local/bin/archr-hotkeys.py"
log "  ✓ Hotkey daemon installed"

# Screenshots directory (used by MODE+B hotkey)
mkdir -p "$ROOTFS_DIR/home/archr/screenshots"

# Fix ownership of archr home directory (files installed by root in Step 5)
chown -R 1001:1001 "$ROOTFS_DIR/home/archr"
log "  ✓ archr home ownership fixed (UID 1001)"

#------------------------------------------------------------------------------
# Step 6: Install Kernel and Modules
#------------------------------------------------------------------------------
log ""
log "Step 6: Installing kernel and modules..."

KERNEL_BOOT="$OUTPUT_DIR/boot"
KERNEL_MODULES="$OUTPUT_DIR/modules/lib/modules"

if [ -f "$KERNEL_BOOT/KERNEL" ]; then
    mkdir -p "$ROOTFS_DIR/boot"
    cp "$KERNEL_BOOT/KERNEL" "$ROOTFS_DIR/boot/"
    log "  ✓ Kernel installed to rootfs/boot/"

    # Copy board DTBs (build-image.sh handles BOOT partition separately)
    if [ -d "$KERNEL_BOOT/dtbs" ]; then
        mkdir -p "$ROOTFS_DIR/boot/dtbs"
        for dtb in "$KERNEL_BOOT/dtbs"/rk3326-*.dtb; do
            [ -f "$dtb" ] && cp "$dtb" "$ROOTFS_DIR/boot/dtbs/"
        done
        dtb_count=$(ls "$ROOTFS_DIR/boot/dtbs"/rk3326-*.dtb 2>/dev/null | wc -l)
        log "  ✓ $dtb_count DTBs installed to rootfs/boot/dtbs/"
    fi
else
    warn "Kernel not found at $KERNEL_BOOT/KERNEL. Run build-kernel.sh first!"
fi

if [ -d "$KERNEL_MODULES" ]; then
    cp -r "$KERNEL_MODULES"/* "$ROOTFS_DIR/lib/modules/"
    log "  ✓ Kernel modules installed"

    # Fix kernel version / modules directory mismatch (-dirty suffix)
    # Kernel may report version with -dirty suffix but modules dir lacks it
    for moddir in "$ROOTFS_DIR/lib/modules/"*; do
        [ -d "$moddir" ] || continue
        base=$(basename "$moddir")
        dirty="${base}-dirty"
        if [ ! -e "$ROOTFS_DIR/lib/modules/$dirty" ]; then
            ln -sf "$base" "$ROOTFS_DIR/lib/modules/$dirty"
            log "  ✓ Modules symlink: $dirty -> $base"
        fi
    done
else
    warn "Kernel modules not found. Run build-kernel.sh first!"
fi

#------------------------------------------------------------------------------
# Step 7: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 7: Cleaning up..."

# Remove setup script
rm -f "$ROOTFS_DIR/tmp/setup.sh"

# Remove QEMU
rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

# Bind mounts are cleaned up by the EXIT trap (cleanup_mounts)

log "  ✓ Cleanup complete"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== Rootfs Build Complete ==="

ROOTFS_SIZE=$(du -sh "$ROOTFS_DIR" | cut -f1)
log ""
log "Rootfs location: $ROOTFS_DIR"
log "Rootfs size: $ROOTFS_SIZE"
log ""
log "✓ Arch R rootfs ready!"
