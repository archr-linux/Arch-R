# Arch R

<p align="center">
  <img src="ArchR.png" alt="Arch R" width="480">
</p>

> **Arch Linux-based gaming distribution for R36S and all clones.**
>
> Leve como uma pluma.

Arch R is a custom Linux distribution built from scratch for the R36S handheld gaming console (RK3326 SoC, Mali-G31 GPU, 640x480 MIPI DSI display). It supports all R36S variants and clones — 16 board profiles and 20 display panels.

## Features

- **Kernel 6.12.61** (Mainline LTS) — board auto-detection via SARADC, 16 board DTBs, panel overlays
- **Mesa 26 Panfrost** — open-source GPU driver, GLES 1.0/2.0/3.1, no proprietary blobs
- **EmulationStation** (fcamod fork) — 78fps stable, GLES 1.0 native rendering
- **RetroArch 1.22.2** — KMS/DRM + EGL, 18+ cores pre-installed
- **19-second boot** — initramfs splash at 0.7s, systemd to EmulationStation
- **Full audio** — ALSA, speaker + headphone auto-switch, volume/brightness hotkeys
- **Battery monitoring** — capacity/voltage reporting, LED warning
- **Multi-panel support** — 20 panel overlays (7 original + 13 clone variants)
- **Two images** — Original R36S and Clone boards, both auto-detect hardware

## Quick Start

Download the latest images from [Releases](../../releases):

- **`ArchR-R36S-*.img.xz`** — for genuine R36S, OGA, OGS, RG351V/M, Chi, R33S
- **`ArchR-R36S-clone-*.img.xz`** — for K36 clones, RGB20S, RGB10X, XU-Mini-M, R36Max

### Using Arch R Flasher (recommended)

Download the [Arch R Flasher](https://github.com/archr-linux/archr-flasher) app, select your console type and display panel, and flash directly. The Flasher handles image download, panel overlay selection, and SD card writing.

### Manual Flash

```bash
xz -d ArchR-R36S-*.img.xz
sudo dd if=ArchR-R36S-*.img of=/dev/sdX bs=4M status=progress
sync
```

After flashing, mount the BOOT partition and copy your panel overlay:

```bash
sudo mount /dev/sdX1 /mnt
sudo cp /mnt/overlays/panel4-v22.dtbo /mnt/overlays/mipi-panel.dtbo
sudo umount /mnt
sync
```

Insert the SD card and power on. The correct board DTB is selected automatically.

## Building from Source

### Host Requirements

- **OS:** Ubuntu 22.04+ (or any Linux with QEMU user-static support)
- **Disk:** 30GB+ free space
- **RAM:** 4GB+ recommended

### Install Dependencies

```bash
sudo apt install -y \
    gcc-aarch64-linux-gnu \
    qemu-user-static \
    binfmt-support \
    parted \
    dosfstools \
    e2fsprogs \
    rsync \
    xz-utils \
    imagemagick \
    device-tree-compiler \
    git \
    bc \
    flex \
    bison \
    libssl-dev
```

### Build Everything

```bash
git clone --recurse-submodules https://github.com/archr-linux/Arch-R.git
cd Arch-R

# Full build: kernel + rootfs + mesa + ES + retroarch + panels + both images
sudo ./build-all.sh
```

Output: `output/images/ArchR-R36S-YYYYMMDD.img.xz` and `ArchR-R36S-clone-YYYYMMDD.img.xz`

### Build Individual Components

```bash
sudo ./build-all.sh --kernel     # Kernel + initramfs (~10 min, cross-compile)
sudo ./build-all.sh --rootfs     # Rootfs + Mesa + ES + RetroArch (~3 hours, QEMU chroot)
sudo ./build-all.sh --uboot      # U-Boot (~2 min)
sudo ./build-all.sh --image      # Image assembly only (~2 min per variant)
sudo ./build-all.sh --clean      # Remove all build artifacts
```

### Build Pipeline

```
build-all.sh
  ├── build-initramfs.sh           # Boot splash (SVG rendering, ~648KB)
  ├── build-kernel.sh              # Cross-compile kernel 6.12.61 (~10 min)
  ├── build-rootfs.sh              # Arch Linux ARM in QEMU chroot (~45 min)
  ├── build-mesa.sh                # Mesa 26 Panfrost + GLES 1.0 (~30 min)
  ├── build-emulationstation.sh    # ES-fcamod with patches (~20 min)
  ├── build-retroarch.sh           # RetroArch + cores (~40 min)
  ├── generate-panel-dtbos.sh      # 20 panel overlays (~10 sec)
  ├── build-uboot.sh               # BSP U-Boot for original boards
  ├── build-uboot-clone.sh         # Mainline U-Boot for clone boards
  └── build-image.sh               # SD card image (×2 variants)
```

## Project Structure

```
Arch-R/
├── build-all.sh                     # Master build orchestrator
├── build-kernel.sh                  # Kernel 6.12.61 cross-compilation
├── build-initramfs.sh               # Initramfs with boot splash
├── build-rootfs.sh                  # Root filesystem (Arch Linux ARM)
├── build-mesa.sh                    # Mesa 26 GPU driver
├── build-emulationstation.sh        # EmulationStation frontend
├── build-retroarch.sh               # RetroArch + cores
├── build-uboot.sh                   # BSP U-Boot (original boards)
├── build-uboot-clone.sh             # Mainline U-Boot (clone boards)
├── build-image.sh                   # SD card image assembly
├── config/
│   ├── linux-archr-base.config      # Kernel config (mainline 6.12)
│   ├── a_boot.ini                   # Boot script — original variant
│   ├── b_boot.ini                   # Boot script — clone variant
│   ├── es_systems.cfg               # EmulationStation systems
│   ├── retroarch.cfg                # RetroArch base config
│   ├── asound.conf                  # ALSA audio config
│   ├── gptokeyb/                    # Gamepad-to-keyboard mappings
│   ├── udev/                        # udev rules (automount, USB gadget)
│   └── autoconfig/                  # RetroArch controller autoconfig
├── kernel/
│   ├── dts/archr/                   # Board device trees (16 boards)
│   └── drivers/                     # Out-of-tree joypad driver
├── patches/                         # Kernel patches (mainline + device)
├── scripts/
│   ├── emulationstation.sh          # ES launch wrapper
│   ├── retroarch-launch.sh          # RetroArch launch wrapper
│   ├── archr-hotkeys.py             # Volume/brightness hotkey daemon
│   ├── archr-init.c                 # Initramfs splash (static binary)
│   ├── archr-gptokeyb.c             # Gamepad-to-keyboard mapper
│   ├── panel-detect.py              # Panel detection
│   ├── generate-panel-dtbos.sh      # Panel overlay generator
│   ├── pmic-poweroff                # PMIC shutdown handler
│   └── opt-system/                  # ES Tools menu scripts
├── bootloader/
│   └── u-boot-rk3326/              # U-Boot source (submodule)
├── prebuilt/
│   └── cores/                       # Pre-built RetroArch cores
├── ArchR.png                        # Boot logo
├── ROADMAP.md                       # Development diary
└── FLASHER.md                       # Flasher app specification
```

## Hardware

| Component | Details |
|-----------|---------|
| SoC | Rockchip RK3326 (4x Cortex-A35 @ 1.5GHz) |
| GPU | Mali-G31 Bifrost (Mesa Panfrost, 600MHz) |
| RAM | 1GB DDR3L (786MHz) |
| Display | 640x480 MIPI DSI (20 panel variants) |
| Audio | RK817 codec, speaker + headphone jack |
| Storage | MicroSD (BOOT + rootfs + ROMS) |
| Controls | D-pad, ABXY, L1/L2/R1/R2, dual analog sticks |
| Battery | 3200mAh Li-Po (RK817 charger) |
| USB | OTG with host/gadget mode switching |

## Architecture

Arch R separates **board configuration** from **panel configuration**:

- **Board DTB** = hardware profile (GPIOs, PMIC, joypad, audio codec). One per board variant. Selected automatically by U-Boot via SARADC ADC reading.
- **Panel overlay** = display init sequence and timings. One per panel type. Applied on top of the board DTB at boot time.

This means the same image works on all boards of a variant — only the panel overlay needs to match your specific display.

### Supported Boards

| Board | DTB | Image |
|-------|-----|-------|
| R36S (original) | rk3326-gameconsole-r36s | Original |
| Odroid Go Advance | rk3326-odroid-go2 | Original |
| Odroid Go Advance v1.1 | rk3326-odroid-go2-v11 | Original |
| Odroid Go Super | rk3326-odroid-go3 | Original |
| Anbernic RG351V | rk3326-anbernic-rg351v | Original |
| Anbernic RG351M | rk3326-anbernic-rg351m | Original |
| GameForce Chi | rk3326-gameforce-chi | Original |
| R33S | rk3326-gameconsole-r33s | Original |
| MagicX XU10 | rk3326-magicx-xu10 | Original |
| K36 / R36S clone | rk3326-gameconsole-r36max | Clone |
| EE clone | rk3326-gameconsole-eeclone | Clone |
| Powkiddy RGB10 | rk3326-powkiddy-rgb10 | Clone |
| Powkiddy RGB10X | rk3326-powkiddy-rgb10x | Clone |
| Powkiddy RGB20S | rk3326-powkiddy-rgb20s | Clone |
| MagicX XU-Mini-M | rk3326-magicx-xu-mini-m | Clone |
| BatLexp G350 | rk3326-batlexp-g350 | Clone |

### Supported Panels

#### Original R36S (7 panels)

| Panel | Overlay file | Controller | Notes |
|-------|-------------|------------|-------|
| Panel 0 | panel0.dtbo | ST7703 | Early R36S units |
| Panel 1 | panel1.dtbo | ST7703 | V10 board |
| Panel 2 | panel2.dtbo | ST7703 | V12 board |
| Panel 3 | panel3.dtbo | ST7703 | V20 board |
| Panel 4 | panel4.dtbo | ST7703 | V22 board |
| Panel 4-V22 | panel4-v22.dtbo | ST7703 | Most common (~60%) |
| Panel 5 | panel5.dtbo | ST7703 | V22 Q8 variant |

R46H (1024x768): `r46h.dtbo`

#### Clone R36S (13 panels)

| Panel | Overlay file | Controller | Notes |
|-------|-------------|------------|-------|
| Clone 1 | clone_panel_1.dtbo | ST7703 | |
| Clone 2 | clone_panel_2.dtbo | ST7703 | |
| Clone 3 | clone_panel_3.dtbo | NV3051D | |
| Clone 4 | clone_panel_4.dtbo | NV3051D | |
| Clone 5 | clone_panel_5.dtbo | ST7703 | |
| Clone 6 | clone_panel_6.dtbo | NV3051D | |
| Clone 7 | clone_panel_7.dtbo | JD9365DA | |
| Clone 8 | clone_panel_8.dtbo | ST7703 | G80CA — most common |
| Clone 9 | clone_panel_9.dtbo | NV3051D | |
| Clone 10 | clone_panel_10.dtbo | ST7703 | |
| R36 Max | r36_max.dtbo | ST7703 | 720x720 |
| RX6S | rx6s.dtbo | NV3051D | |

### Manual Panel Selection

Mount the BOOT partition and copy the correct overlay as `mipi-panel.dtbo`:

```bash
sudo mount /dev/sdX1 /mnt

# Example: set Panel 4-V22 (most common original R36S panel)
sudo cp /mnt/overlays/panel4-v22.dtbo /mnt/overlays/mipi-panel.dtbo

# Example: set Clone 8 (most common clone panel)
sudo cp /mnt/overlays/clone_panel_8.dtbo /mnt/overlays/mipi-panel.dtbo

sudo umount /mnt
sync
```

## Boot Flow

```
Power On
  → U-Boot loads (idbloader → trust → uboot.img)
  → boot.ini: read SARADC hwrev → select board DTB
  → boot.ini: apply overlays/mipi-panel.dtbo (panel init sequence)
  → Kernel 6.12.61 + initramfs splash (0.7s)
  → systemd → archr-boot-setup (GPU + governors)
  → emulationstation.service → EmulationStation UI
  ≈ 19 seconds total
```

## Contributing

See [ROADMAP.md](ROADMAP.md) for current development status and planned features.

## License

GPL v3
