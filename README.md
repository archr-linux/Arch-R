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

Arch R is an **Arch Linux** distribution for handheld gaming consoles: the **R36S** and its many variants (Rockchip RK3326) and, in beta since 3.1.1, the **AISLPC RG43V PRO** and **RG52 MINI** (Rockchip RK3562). In the same spirit as SteamOS, it pairs a genuine Arch userland (pacman, systemd, up-to-date packages) with a curated console experience: flash it, turn the device on, play. System updates are delivered through the built-in updater, kernel included; reflashing is only needed for a fresh install or recovery.

The image build pipeline descends from the LibreELEC family of embedded build systems (through JELOS and ROCKNIX), but the operating system it assembles is Arch Linux ARM, not a JELOS derivative.

Website and documentation: https://arch-r.io

## Features

- Genuine Arch Linux ARM base with pacman and signed package repositories (stable, next and dev channels).
- **archr-launcher**, a game launcher written in Rust and SDL2 for handheld screens, running under sway. It replaced EmulationStation in 3.0. Themes can change the layout of every screen (theme API 3.1), and modules add tiles, shortcuts and apps (module API 4).
- RetroArch with its cores, standalone emulators chosen per system (PPSSPP, DuckStation, Flycast, mupen64plus, DraStic and others) and PortMaster.
- Built-in system updater (**Settings › System › Updates**, or `archr-update` over SSH). Kernel and device trees update through it too, with checksum-verified writes to the boot partition. Without network, a signed update file copied to the card installs from the same page (https://arch-r.io/update/).
- Both GPU stacks in the image: the Arm libmali driver (default) and Mesa with Panfrost, switched in **Settings › System › GPU driver**. Vulkan through Mesa's PanVK with Panfrost.
- Sound and display settings for gamma, colour temperature and saturation, applied in menus, games and ports.
- Full audio support with speaker/headphone auto-switch across board revisions.
- Power button light sleep: screen and backlight fully off, instant wake.
- Wi-Fi: internal RK915 or AIC8800 radios where the board has one, USB dongles otherwise (Realtek RTL81xx/88x2 families, AIC8800).
- Bluetooth audio and controllers (on the R36S family through a USB Bluetooth adapter; the boards have no internal Bluetooth).
- RetroAchievements, ScreenScraper scraping, RetroArch netplay and Moonlight streaming.
- Save sync (PC folder or rclone cloud), Syncthing, and VPN with WireGuard, Tailscale and ZeroTier.
- Anonymous error reports (can be turned off) and an on-device diagnostics report.

## Supported Hardware

| Console | Chip | Image | Status |
|---|---|---|---|
| R36S (original), R33S, R36S Soysauce | RK3326 | Original | Stable |
| Odroid Go Advance / v1.1 / Super | RK3326 | Original | Stable |
| Anbernic RG351V / RG351M | RK3326 | Original | Stable |
| GameForce Chi, MagicX XU10, Powkiddy RGB10 | RK3326 | Original | Stable |
| K36 / R36S V20 clones / EE Clone | RK3326 | Clone | Stable |
| Powkiddy RGB10X, MagicX XU-Mini-M | RK3326 | Clone | Stable |
| AISLPC RG43V PRO (1024x768) | RK3562 | AISLPC | Beta 1 |
| AISLPC RG52 MINI (720x1280) | RK3562 | AISLPC | Beta 1, not yet tested on the console |

How well a board works also depends on its revision and panel.

### R36S family (RK3326)

- CPU: 4x Cortex-A35, 1416 MHz (1512 MHz with the opt-in CPU turbo).
- GPU: Mali-G31, 600 MHz by default (650 MHz opt-in). libmali by default, Panfrost selectable, Vulkan through PanVK with Panfrost.
- RAM at 528 MHz through the kernel's memory frequency scaling, switched in the vertical blank.
- Kernel: Linux 6.12 LTS, board DTB selected at boot via SARADC for recognised boards.

### AISLPC RG43V PRO and RG52 MINI (RK3562), Beta 1

- CPU: 4x Cortex-A53 up to 2.0 GHz. GPU: Mali-G52 2EE up to 900 MHz.
- Kernel: Linux 7.3.x, used only on the RK3562 (the R36S family stays on 6.12 LTS).
- GPU: libmali by default (Arm, kbase r52p0 with the g24p0 driver), Panfrost selectable. OpenGL ES runs on libmali; Vulkan exists only through PanVK 1.0 and is experimental here.
- Tested on an RG43V PRO, board v10: display, GPU, Wi-Fi (RK915), battery, controls, audio, restart, firewall, gamma/temperature/saturation, rumble with strength (**Settings › Controls › Vibration**) and the stick RGB LEDs (**Settings › Controls › Stick LEDs**). The RG52 MINI and the v14 boards (AIC8800 Wi-Fi) are supported from their stock device trees and have not been on the bench yet.
- Not in Beta 1: HDMI (RK628 bridge, coming by update), Bluetooth, the RG43V PRO 1024x600 panel, an Arch R U-Boot (the console boots through the factory U-Boot on its eMMC), installing to the eMMC (planned).
- Own update channel (`repo-stable-rk3562`): `archr-update` reads the SoC from the device tree, so these consoles never install R36S packages.

Details: https://arch-r.io/docs/aislpc/

## Display Panels (R36S family)

Panel overlays are not baked into the RK3326 images. Generate the overlay for your exact motherboard revision at the online generator, https://arch-r.io/overlay-generator/ (pick your board, or upload the stock `dtb` from the SD card that shipped with the device), then copy the resulting file to `overlays/mipi-panel.dtbo` on the boot partition. The Arch R Flasher can also generate and install the overlay during flashing. The `/flash/overlays/` folder on a fresh install contains a `README.txt` with the same instructions. The generator also extracts board-specific wiring (audio amplifier, jack detect, LEDs, PMIC interrupt, Wi-Fi) from your stock DTB.

If the online generator cannot load (it downloads an 8 MB WebAssembly runtime first), the same generator is published as an offline terminal script: https://arch-r.io/archr-dtbo-offline.zip (about 100 KB, Python 3 only, no `pip`, no network). Extract it, open a terminal in the folder and run:

```bash
python3 archr_dtbo.py rk3326-r36s-linux.dtb SDORIG -o mipi-panel.dtbo
```

First argument: your stock `dtb`. Second: the option string for the console, `SDORIG` (R36S Original), `SDCLONE` (R36S Clone) or `SDORIG-NAm` (R36S Soysauce), with extra flags appended by a dash (`SDCLONE-LSi`). On Windows the command is `python`. Full instructions: https://arch-r.io/docs/installation#panel-overlay-generator

The RG43V PRO and RG52 MINI use no overlay: each screen has its own device tree.

## Quick Start

Download the latest images from [Releases](https://github.com/archr-linux/Arch-R/releases):

- **Original image** (`ArchR-R36S.aarch64-<date>-original.img.gz`) for genuine R36S and compatible boards.
- **Clone image** (`ArchR-R36S.aarch64-<date>-clone.img.gz`) for K36 clones and compatible boards.
- **AISLPC image** (`ArchR-RK3562.aarch64-<date>-beta1-aislpc.img.gz`) for the RG43V PRO and RG52 MINI.

The easiest path is the [Arch R Flasher](https://github.com/archr-linux/archr-flasher) (1.4.0 or later), which downloads, verifies and flashes the image: on the R36S family it also installs your panel overlay, and on the AISLPC consoles it sets the board's `extlinux.conf` for the model you pick. Manual flashing works for every image:

```bash
gzip -d ArchR-<device>.aarch64-<date>-<variant>.img.gz
sudo dd if=ArchR-<device>.aarch64-<date>-<variant>.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

**RG52 MINI (manual flashing):** the AISLPC image starts as an RG43V PRO (1024x768). Before the first boot, open the `ARCHR` partition and copy `extlinux/extlinux.conf.rg52-mini` over `extlinux/extlinux.conf`. The same folder has `extlinux.conf.rg43v-pro` (the default) and `extlinux.conf.rg43v-pro-1024x600` (that screen is not supported yet), and a `README.txt` listing them.

**microSD card: 32 GB or larger is recommended.** The first boot gives the system its own partitions and puts the ROMs on an exFAT partition (`ARCHR_ROMS`) that opens on any computer. Cards of 16 GB or less have no room for it and keep the older layout, with the ROMs inside the ext4 `STORAGE` partition: everything works, but the ROMs are only reachable from a PC over the network (Samba/SSH). 8 GB is the minimum.

Always verify the download against the published `SHA256SUMS` before flashing. Insert the SD card and power on; on the R36S family the correct board DTB is selected automatically.

## Updates

- **In place (default after install)**: **Settings › System › Updates** in the launcher, or `archr-update` over SSH. Updates come from the signed pacman repository; after each transaction the boot partition is synchronized automatically, so kernel and device-tree fixes arrive without reflashing. User overlays and configuration are never touched.
- **Without network**: download the newest update file from https://arch-r.io/update/, copy it to `roms/update/` on the card and choose **Update from the card** (R36S family; offline files for the RK3562 are not published yet).
- **Reflash**: for fresh installs, recovery, or the rare low-level bootloader change (TPL/U-Boot), which lives outside the filesystem.

The channel (stable, next, dev) is set under **Settings › System › Updates › Options**. Each channel is a release tag on [archr-repo](https://github.com/archr-linux/archr-repo): `repo-stable`, `repo-next` and `repo-dev` for the RK3326, with a `-rk3562` suffix for the RK3562 (only `repo-stable-rk3562` exists for now).

## Building from Source

### Requirements

- Docker (recommended) or native Linux build environment
- About 160 GB free disk space per device target (build trees plus sources)
- 16 GB RAM or more (32 GB recommended)

### Build

```bash
git clone https://github.com/archr-linux/Arch-R.git
cd Arch-R

# Build Docker image (first time only)
make docker-image-build

# R36S family: original and clone images
make docker-RK3326

# AISLPC RG43V PRO / RG52 MINI image
make docker-RK3562
```

Output images are generated in `target/`. Add `OFFICIAL=yes` for release-stamped images. Each target builds a 32-bit (`arm`) tree for the 32-bit libraries first, then the `aarch64` image.

### Build Commands

| Command | Description |
|---------|-------------|
| `make docker-RK3326` | Full build inside Docker, R36S family (original and clone) |
| `make docker-RK3562` | Full build inside Docker, AISLPC RG43V PRO / RG52 MINI |
| `make RK3326`, `make RK3562` | Native build (requires all dependencies) |
| `make docker-image-build` | Build the Docker build environment |
| `make clean` | Remove build artifacts |

Full guide: https://arch-r.io/docs/build/

## Architecture

On the R36S family, Arch R separates **board configuration** from **panel configuration**:

- **Board DTB** = hardware profile (GPIOs, PMIC, joypad, audio codec). Selected automatically by the boot script via SARADC. One generic DTB per hardware family; board-revision differences are carried by the overlay.
- **Panel overlay** = display init sequence, timings and board-specific wiring extracted from the stock DTB. Applied on top of the board DTB at boot time.

This means the same image works on all boards of a variant. Only the overlay needs to match the specific device.

On the RK3562 consoles there is no overlay: one DTB per model and screen, picked by `extlinux.conf`.

### Boot Flow

```
Power On
  U-Boot
    RK3326: BSP U-Boot (original image) or mainline U-Boot (clone image) on the SD card
            boot script reads the SARADC hwrev and selects the board DTB
    RK3562: factory U-Boot on the internal eMMC
    sysboot: load kernel + DTB (+ panel overlay on RK3326) from extlinux.conf
  Kernel (6.12 LTS on RK3326, 7.3 on RK3562) + initramfs
    mount root (ext4) + storage, resolved by partition label
    switch_root to systemd
  systemd
    archr-autostart (quirks by device-tree model, governors, audio)
    sway + archr-launcher
```

### Partition Layout

| Partition | Filesystem | Label | Purpose |
|-----------|-----------|-------|---------|
| 1 | FAT32 | ARCHR | Boot (kernel, DTBs, extlinux; overlays and boot.scr on RK3326) |
| 2 | ext4 | ARCHR_ROOT | Root filesystem (Arch Linux ARM) |
| 3 | ext4 | STORAGE | User data, configs (and ROMs on cards of 16 GB or less) |
| 4 | exFAT | ARCHR_ROMS | ROMs, created at first boot on cards of 32 GB or more |

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
- **[Armbian](https://www.armbian.com/)** -- for the RK3562 kernel patch series the RK3562 kernel builds on.
- **[Rockchip](https://www.rock-chips.com/)** and **[Arm](https://www.arm.com/)** -- for the RK3326 and RK3562 SoCs, rkbin firmware and the libmali GPU driver.
- **[Mesa](https://mesa3d.org/)** -- for the open-source graphics stack.
- **[RetroArch](https://www.retroarch.com/)** and **[Libretro](https://www.libretro.com/)** -- for the emulation framework and cores.
- **[SDL](https://www.libsdl.org/)** and **[sway](https://swaywm.org/)** -- for the libraries and compositor archr-launcher runs on.
- All developers and contributors across the open-source community who made this possible.
