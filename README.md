<p align="center">
  <img src="distributions/ArchR/logos/archr-logo.png" width="280" alt="Arch R" style="background:#000">
</p>

<p align="center">
  <strong>Arch Linux gaming distribution for handheld devices.</strong>
</p>

<p align="center">
  <a href="https://github.com/archr-linux/Arch-R/releases/latest"><img src="https://img.shields.io/github/release/archr-linux/Arch-R.svg?color=0080FF&label=latest%20version&style=flat-square" alt="Latest Version"></a>
  <a href="https://github.com/archr-linux/Arch-R/commits"><img src="https://img.shields.io/github/commit-activity/m/archr-linux/Arch-R?color=0080FF&style=flat-square" alt="Activity"></a>
  <a href="https://github.com/archr-linux/Arch-R/pulls"><img src="https://img.shields.io/github/issues-pr-closed/archr-linux/Arch-R?color=0080FF&style=flat-square" alt="Pull Requests"></a>
</p>

---

Arch R is an **Arch Linux** distribution for the **R36S** handheld gaming console and its many variants. In the same spirit as SteamOS, it pairs a genuine Arch userland (pacman, systemd, up-to-date packages) with a curated console experience: flash it, turn the device on, play. System updates are delivered through the built-in updater, kernel included; reflashing is only needed for a fresh install or recovery.

The image build pipeline descends from the LibreELEC family of embedded build systems (through JELOS and ROCKNIX), but the operating system it assembles is Arch Linux ARM, not a JELOS derivative.

## Features

- Genuine Arch Linux ARM base with pacman and signed package repositories (stable, next and dev channels).
- Built-in system updater in EmulationStation; kernel and device trees update through it too, with checksum-verified writes to the boot partition.
- Mainline kernel 6.12 LTS with board auto-detection via SARADC.
- Memory clock trained at 666MHz from boot (twice the BSP-era default) and tuned Mali-G31 graphics.
- EmulationStation frontend with RetroArch and 18+ cores pre-installed, plus PortMaster.
- Full audio support with speaker/headphone auto-switch across board revisions.
- Power button light sleep: screen and backlight fully off, instant wake.
- Power LED control (on, off, heartbeat) on every supported family.
- USB WiFi dongle support, including the common RTL8188EUS family (TP-Link, Edimax).
- MIPI panel overlays for every known motherboard revision, generated on demand by the online overlay generator at https://arch-r.io/overlay-generator/ (or during flashing by the Arch R Flasher). The generator also extracts board-specific wiring (audio amplifier, jack detect, LEDs, PMIC interrupt) from your stock DTB.
- Separate images for original and clone boards, both with hardware auto-detection.
- Integrated cross-device local and remote network play.
- Fine-grained control for battery life and performance.
- Bluetooth audio and controller support (via USB Bluetooth adapter; the boards have no internal radio).
- USB audio devices (DACs, headsets, controllers with audio).
- Device sync with Syncthing and rclone.
- VPN support with WireGuard, Tailscale, and ZeroTier.
- Built-in scraping and RetroAchievements.

## Supported Hardware

### Boards

| Board | Image |
|-------|-------|
| R36S (original), R33S, R36S Soysauce | Original |
| Odroid Go Advance / v1.1 / Super | Original |
| Anbernic RG351V / RG351M | Original |
| GameForce Chi, MagicX XU10, Powkiddy RGB10 | Original |
| K36 / R36S V20 clones / EE Clone | Clone |
| Powkiddy RGB10X, MagicX XU-Mini-M | Clone |

### Display Panels

Panel overlays are not baked into the images. Generate the overlay for your exact motherboard revision at the online generator, https://arch-r.io/overlay-generator/ (pick your board, or upload the stock `dtb` from the SD card that shipped with the device), then copy the resulting file to `overlays/mipi-panel.dtbo` on the boot partition. The Arch R Flasher can also generate and install the overlay during flashing. The `/flash/overlays/` folder on a fresh install contains a `README.txt` with the same instructions.

If the online generator cannot load (it downloads an 8 MB WebAssembly runtime first), the same generator is published as an offline terminal script: https://arch-r.io/archr-dtbo-offline.zip (about 100 KB, Python 3.5+ only, no `pip`, no network). Extract it, open a terminal in the folder and run:

```bash
python3 archr_dtbo.py rk3326-r36s-linux.dtb SDORIG -o mipi-panel.dtbo
```

First argument: your stock `dtb`. Second: the option string for the console, `SDORIG` (R36S Original), `SDCLONE` (R36S Clone) or `SDORIG-NAm` (R36S Soysauce), with extra flags appended by a dash (`SDCLONE-LSi`). On Windows the command is `python`. Full instructions: https://arch-r.io/docs/installation#panel-overlay-generator

## Quick Start

Download the latest images from [Releases](https://github.com/archr-linux/Arch-R/releases):

- **Original image** -- for genuine R36S and compatible boards.
- **Clone image** -- for K36 clones and compatible boards.

The easiest path is the [Arch R Flasher](https://github.com/archr-linux/archr-flasher), which downloads, verifies, flashes and installs your panel overlay in one go. Manual flashing works too:

```bash
gzip -d ArchR-R36S-*.img.gz
sudo dd if=ArchR-R36S-*.img of=/dev/sdX bs=4M status=progress
sync
```

Always verify the download against the published `SHA256SUMS` before flashing. Insert the SD card and power on; the correct board DTB is selected automatically.

## Updates

- **In place (default after install)**: EmulationStation > Updates, or `archr-update` over SSH. Updates come from the signed pacman repository; after each transaction the boot partition is synchronized automatically, so kernel and device-tree fixes arrive without reflashing. User overlays and configuration are never touched.
- **Reflash**: for fresh installs, recovery, or the rare low-level bootloader change (TPL/U-Boot, e.g. a DDR frequency change), which lives outside the filesystem.

Release channel is configurable (stable, next, dev) under updates settings.

## Building from Source

### Requirements

- Docker (recommended) or native Linux build environment
- ~40 GB free disk space
- ~8 GB RAM recommended

### Build

```bash
git clone https://github.com/archr-linux/Arch-R.git
cd Arch-R

# Build Docker image (first time only)
make docker-image-build

# Build for R36S (all variants)
make docker-RK3326
```

Output images are generated in `target/`. Add `OFFICIAL=yes` for release-stamped images.

### Build Commands

| Command | Description |
|---------|-------------|
| `make docker-RK3326` | Full build inside Docker |
| `make RK3326` | Native build (requires all dependencies) |
| `make docker-image-build` | Build the Docker build environment |
| `make clean` | Remove build artifacts |

## Architecture

Arch R separates **board configuration** from **panel configuration**:

- **Board DTB** = hardware profile (GPIOs, PMIC, joypad, audio codec). Selected automatically by U-Boot via SARADC. One generic DTB per hardware family; board-revision differences are carried by the overlay.
- **Panel overlay** = display init sequence, timings and board-specific wiring extracted from the stock DTB. Applied on top of the board DTB at boot time.

This means the same image works on all boards of a variant. Only the overlay needs to match the specific device.

### Boot Flow

```
Power On
  U-Boot (mainline, legacy BSP loader for clone boards)
    boot script: read SARADC hwrev, select board DTB
    sysboot: load kernel + DTB + overlay from extlinux.conf
  Kernel 6.12 + initramfs
    mount root (ext4) + storage, resolved by partition label
    switch_root to systemd
  systemd
    archr-autostart (quirks by device-tree model, governors, audio)
    EmulationStation
```

### Partition Layout

| Partition | Filesystem | Label | Purpose |
|-----------|-----------|-------|---------|
| 1 | FAT32 | ARCHR | Boot (kernel, DTBs, overlays, boot.scr) |
| 2 | ext4 | ARCHR_ROOT | Root filesystem (Arch Linux ARM) |
| 3 | ext4 | STORAGE | User data, ROMs, configs |

## Community

Contributions are welcome. Please open issues or pull requests on [GitHub](https://github.com/archr-linux/Arch-R).

## Licenses

The Arch R operating system is Arch Linux ARM plus original Arch R software. The image build tooling in this repository descends from [ROCKNIX](https://github.com/ROCKNIX/distribution) and [JELOS](https://github.com/JustEnoughLinuxOS/distribution/); the licenses of that inherited tooling continue to apply to the portions derived from it.

You are free to:

- **Share**: copy and redistribute the material in any medium or format.
- **Adapt**: remix, transform, and build upon the material.

Under the following terms:

- **Attribution**: You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- **NonCommercial**: You may not use the material for commercial purposes.
- **ShareAlike**: If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.

### Arch R Software

Copyright (C) 2026-present [Arch R](https://github.com/archr-linux/Arch-R)

Original software and scripts developed by Arch R are licensed under the terms of the [GNU GPL Version 2](https://choosealicense.com/licenses/gpl-2.0/). The full license can be found in this project's licenses folder.

### Bundled Works

All other software is provided under each component's respective license. These licenses can be found in the software sources or in this project's licenses folder. Modifications to bundled software and scripts by upstream projects are licensed under the terms of the software being modified.

## Credits

Like any Linux distribution, this project is not the work of one person. It is the work of many people around the world who have developed the open-source components without which this project could not exist.

Special thanks to:

- **[Arch Linux](https://archlinux.org/)** and **[Arch Linux ARM](https://archlinuxarm.org/)** -- the operating system Arch R is built on.
- **[ROCKNIX](https://github.com/ROCKNIX/distribution)** and **[JELOS](https://github.com/JustEnoughLinuxOS/distribution/)** -- the projects whose build tooling and RK3326 device knowledge Arch R inherited and still learns from.
- **[CoreELEC](https://coreelec.org/)** and **[LibreELEC](https://libreelec.tv/)** -- the embedded Linux distributions whose build system forms the backbone of the image pipeline.
- **[Hardkernel](https://www.hardkernel.com/)** -- for the Odroid Go Advance BSP U-Boot and kernel device trees.
- **[Rockchip](https://www.rock-chips.com/)** -- for the RK3326 SoC, rkbin firmware and the libmali GPU driver.
- **[Mesa](https://mesa3d.org/)** -- for the open-source graphics stack.
- **[RetroArch](https://www.retroarch.com/)** and **[Libretro](https://www.libretro.com/)** -- for the emulation framework and cores.
- **[EmulationStation](https://emulationstation.org/)** -- for the frontend.
- All developers and contributors across the open-source community who made this possible.
