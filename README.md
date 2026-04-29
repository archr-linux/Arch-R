<p align="center">
  <img src="distributions/ArchR/logos/archr-logo.png" width="280" alt="Arch R" style="background:#000">
</p>

<p align="center">
  <strong>Arch Linux-based gaming distribution for handheld devices.</strong>
</p>

<p align="center">
  <a href="https://github.com/archr-linux/Arch-R/releases/latest"><img src="https://img.shields.io/github/release/archr-linux/Arch-R.svg?color=0080FF&label=latest%20version&style=flat-square" alt="Latest Version"></a>
  <a href="https://github.com/archr-linux/Arch-R/commits"><img src="https://img.shields.io/github/commit-activity/m/archr-linux/Arch-R?color=0080FF&style=flat-square" alt="Activity"></a>
  <a href="https://github.com/archr-linux/Arch-R/pulls"><img src="https://img.shields.io/github/issues-pr-closed/archr-linux/Arch-R?color=0080FF&style=flat-square" alt="Pull Requests"></a>
</p>

---

Arch R is a custom Linux distribution for the **R36S** handheld gaming console and all its variants, built on top of [ROCKNIX](https://github.com/ROCKNIX/distribution) with an **Arch Linux-based** build environment. It supports **16 board profiles** and **20 display panels** across original and clone hardware.

## Features

- Arch Linux-based build system with Docker support.
- Kernel 6.12 LTS with board auto-detection via SARADC.
- Mesa Panfrost open-source GPU driver (GLES 3.1, no proprietary blobs).
- EmulationStation frontend with RetroArch and 18+ cores pre-installed.
- Full audio support with speaker/headphone auto-switch.
- Battery monitoring with capacity reporting and LED warning.
- 43 pre-generated MIPI panel overlays (15 original + 18 clone + 10 soysauce variants), one per motherboard revision.
- Separate images for original and clone boards, both with hardware auto-detection.
- Integrated cross-device local and remote network play.
- Fine-grained control for battery life and performance.
- Bluetooth audio and controller support.
- HDMI audio/video output, USB audio.
- Device sync with Syncthing and rclone.
- VPN support with WireGuard, Tailscale, and ZeroTier.
- Built-in scraping and RetroAchievements.

## Supported Hardware

### Boards

| Board | Image |
|-------|-------|
| R36S (original), R33S | Original |
| Odroid Go Advance / v1.1 / Super | Original |
| Anbernic RG351V / RG351M | Original |
| GameForce Chi, MagicX XU10 | Original |
| K36 / R36S clones / EE Clone | Clone |
| Powkiddy RGB10 / RGB10X / RGB20S | Clone |
| MagicX XU-Mini-M, BatLexp G350 | Clone |

### Display Panels

Arch R ships 43 pre-generated MIPI panel overlays covering all known R36S display variants, named after the exact motherboard revision (e.g. `R36S-V21_2024-12-18_2551.dtbo`, `G80CA-MB_V1.3-20251212_Panel_8.dtbo`). Panel selection is done by copying the correct `.dtbo` file to `overlays/mipi-panel.dtbo` on the boot partition. Sources live under `config/archr-dts/{original,clone,soysauce}/<MB-revision>/`; the build extracts the panel description from each revision's `rk3326-r36s-linux.dtb` via `config/mipi-generator/generator.sh`.

## Quick Start

Download the latest images from [Releases](https://github.com/archr-linux/Arch-R/releases):

- **Original image** -- for genuine R36S and compatible boards.
- **Clone image** -- for K36 clones and compatible boards.

Flash to a MicroSD card:

```bash
xz -d ArchR-R36S-*.img.xz
sudo dd if=ArchR-R36S-*.img of=/dev/sdX bs=4M status=progress
sync
```

Insert the SD card and power on. The correct board DTB is selected automatically.

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

Output images are generated in `target/`.

### Build Commands

| Command | Description |
|---------|-------------|
| `make docker-RK3326` | Full build inside Docker |
| `make RK3326` | Native build (requires all dependencies) |
| `make docker-image-build` | Build the Docker build environment |
| `make clean` | Remove build artifacts |

## Architecture

Arch R separates **board configuration** from **panel configuration**:

- **Board DTB** = hardware profile (GPIOs, PMIC, joypad, audio codec). Selected automatically by U-Boot via SARADC.
- **Panel overlay** = display init sequence and timings. Applied on top of the board DTB at boot time.

This means the same image works on all boards of a variant. Only the panel overlay needs to match the specific display.

### Boot Flow

```
Power On
  U-Boot (BSP or mainline)
    boot.scr: read SARADC hwrev, select board DTB
    sysboot: load kernel + DTB + overlay from extlinux.conf
  Kernel 6.12 + initramfs
    mount root (ext4) + storage
    switch_root to systemd
  systemd
    archr-autostart (quirks, governors, audio)
    EmulationStation
```

### Partition Layout

| Partition | Filesystem | Label | Purpose |
|-----------|-----------|-------|---------|
| 1 | FAT32 | ARCHR | Boot (kernel, DTBs, overlays, boot.scr) |
| 2 | ext4 | ARCHR_ROOT | Root filesystem |
| 3 | ext4 | STORAGE | User data, ROMs, configs |

## Community

Contributions are welcome. Please open issues or pull requests on [GitHub](https://github.com/archr-linux/Arch-R).

## Licenses

**Arch R** is a fork of [ROCKNIX](https://github.com/ROCKNIX/distribution), which is a fork of [JELOS](https://github.com/JustEnoughLinuxOS/distribution/). All upstream licenses apply.

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

- **[ROCKNIX](https://github.com/ROCKNIX/distribution)** -- the upstream distribution that Arch R is forked from. ROCKNIX provided the complete build system, device support, EmulationStation integration, and the foundation for handheld gaming on Linux.
- **[JELOS](https://github.com/JustEnoughLinuxOS/distribution/)** -- the project that ROCKNIX was originally forked from.
- **[CoreELEC](https://coreelec.org/)** and **[LibreELEC](https://libreelec.tv/)** -- the embedded Linux distributions whose build system forms the backbone of this project.
- **[Hardkernel](https://www.hardkernel.com/)** -- for the Odroid Go Advance BSP U-Boot and kernel device trees.
- **[Rockchip](https://www.rock-chips.com/)** -- for the RK3326 SoC and rkbin firmware.
- **[Mesa](https://mesa3d.org/)** -- for the Panfrost open-source GPU driver.
- **[RetroArch](https://www.retroarch.com/)** and **[Libretro](https://www.libretro.com/)** -- for the emulation framework and cores.
- **[EmulationStation](https://emulationstation.org/)** -- for the frontend.
- All developers and contributors across the open-source community who made this possible.
