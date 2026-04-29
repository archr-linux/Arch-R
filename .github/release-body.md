&nbsp;&nbsp;<img src="distributions/ArchR/logos/archr-logo.png" width=192>
#
ArchR is a community developed Linux distribution for handheld gaming devices, forked from [ROCKNIX](https://github.com/ROCKNIX/distribution).  Our goal is to produce an operating system that has the features and capabilities that we need, and to have fun as we develop it.

## Licenses
ArchR is a Linux distribution forked from ROCKNIX, made up of many open-source components.  Components are provided under their respective licenses.  This distribution includes components licensed for non-commercial use only.

### ArchR Branding
ArchR branding and images are licensed under a [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-nc-sa/4.0/).

#### You are free to
* Share — copy and redistribute the material in any medium or format
* Adapt — remix, transform, and build upon the material

#### Under the following terms
* Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
* NonCommercial — You may not use the material for commercial purposes.
* ShareAlike — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.

### ArchR Software
Copyright (C) 2024-2026 ArchR (https://github.com/archr-linux).  Derived from ROCKNIX, Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX).

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Installation
* Download the latest version of ArchR.
* Decompress the image.
* Write the image to an SDCARD using an imaging tool.  Common imaging tools include [Balena Etcher](https://www.balena.io/etcher/), [Raspberry Pi Imager](https://www.raspberrypi.com/software/), and [Win32 Disk Imager](https://sourceforge.net/projects/win32diskimager/).  If you're skilled with the command line, dd works fine too.

### Installation Package Downloads
| **Device/Platform**                                                                                                                                              | **Download Package**                                                                                                                                                 | **Documentation**                                                    |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| **Anbernic RG351P/M/V, Game Console R33S/R35S/R36S, ODROID Go Advance, ODROID Go Super, Magicx XU10, Powkiddy V10/RGB10**                                        | [ArchR-RK3326.aarch64-$DATE-a.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3326.aarch64-$DATE-a.img.gz)                       | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3326/)     |
| **Magicx XU Mini M, Powkiddy RGB10X**                                                                                                                            | [ArchR-RK3326.aarch64-$DATE-b.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3326.aarch64-$DATE-b.img.gz)                       | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3326/)     |
| **Anbernic RG353P/M/V/VS/PS, RG503, RGARC-D/S, Powkiddy RK2023, RGB10 Max 3, RGB30, RGB20SX, RGB20 Pro**                                                         | [ArchR-RK3566.aarch64-$DATE-Generic.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3566.aarch64-$DATE-Generic.img.gz)           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3566/)     |
| **Anbernic RG552**                                                                                                                                               | [ArchR-RK3399.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3399.aarch64-$DATE.img.gz)                           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3399/)     |
| **Anbernic RG35XX PLUS/H/SP/2024, RG40XX V/H, RGCUBEXX, RG34XX SP, RG28XX [Must Follow Install Instructions](https://github.com/archr-linux/Arch-R/wiki/h700-installation)** | [ArchR-H700.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-H700.aarch64-$DATE.img.gz)                               | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/H700/)       |
| **Hardkernel ODROID Go Ultra, Powkiddy RGB10 Max 3 Pro**                                                                                                         | [ArchR-S922X.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-S922X.aarch64-$DATE.img.gz)                             | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/S922X/)      |
| **Gameforce Ace (default). Orange Pi 5 / 5 Plus, Radxa Rock 5a / 5b / 5b+ / CM5, and Indiedroid Nova**                                                           | [ArchR-RK3588.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3588.aarch64-$DATE.img.gz)                           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3588/)     |
| **Powkiddy x55**                                                                                                                                                 | [ArchR-RK3566.aarch64-$DATE-Powkiddy_x55.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3566.aarch64-$DATE-Powkiddy_x55.img.gz) | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/RK3566-X55/) |
| **Retroid Pocket 5, Pocket Mini, Pocket Mini V2, Pocket Flip2**                                                                                                  | [ArchR-SM8250.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8250.aarch64-$DATE.img.gz)                           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/SM8250/)     |
| **Ayn Odin 2, Odin 2 Mini, Odin 2 Portal, Thor, Ayaneo Pocket ACE/EVO/DMG/DS**                                                                                   | [ArchR-SM8550.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8550.aarch64-$DATE.img.gz)                           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/SM8550/)     |
| **Ayaneo Pocket S2**                                                                                                                                             | [ArchR-SM8650.aarch64-$DATE.img.gz](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8650.aarch64-$DATE.img.gz)                           | [documentation](/documentation/PER_DEVICE_DOCUMENTATION/SM8650/)     |

## Upgrading
* Download and install the update online via the System Settings menu.
* If you are unable to update online
* Download the latest version of ArchR from Github
* Copy the update to your device over the network to your device's update share.
* Reboot the device, and the update will begin automatically.

### Update Package Downloads
| **Device/Platform**                                                                                                                         | **Download Package**                                                                                                                 |
|---------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| **Anbernic RG351P/M/V, Game Console R33S/R35S/R36S, ODROID Go Advance, ODROID Go Super, Magicx XU10, XU Mini M, Powkiddy V10/RGB10/RGB10X** | [ArchR-RK3326.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3326.aarch64-$DATE.tar) |
| **Anbernic RG353P/M/V/VS/PS, RG503, RGARC-D/S, Powkiddy RK2023, RGB10 Max 3, RGB30, RGB20SX, RGB20 Pro, X55**                               | [ArchR-RK3566.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3566.aarch64-$DATE.tar) |
| **Anbernic RG552**                                                                                                                          | [ArchR-RK3399.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3399.aarch64-$DATE.tar) |
| **Anbernic RG35XX PLUS/H/SP/2024, RG40XX V/H, RGCUBEXX, RG34XX SP, RG28XX**                                                                 | [ArchR-H700.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-H700.aarch64-$DATE.tar)     |
| **Hardkernel ODROID Go Ultra, Powkiddy RGB10 Max 3 Pro**                                                                                    | [ArchR-S922X.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-S922X.aarch64-$DATE.tar)   |
| **Gameforce Ace, Orange Pi 5 / 5 Plus, Radxa Rock 5a / 5b / 5b+ / CM5 and Indiedroid Nova**                                                 | [ArchR-RK3588.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-RK3588.aarch64-$DATE.tar) |
| **Retroid Pocket 5, Pocket Mini, Pocket Mini V2, Pocket Flip2**                                                                             | [ArchR-SM8250.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8250.aarch64-$DATE.tar) |
| **Ayn Odin 2, Odin 2 Mini, Odin 2 Portal, Thor, Ayaneo Pocket ACE/EVO/DMG/DS**                                                              | [ArchR-SM8550.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8550.aarch64-$DATE.tar) |
| **Ayaneo Pocket S2**                                                                                                                        | [ArchR-SM8650.aarch64-$DATE.tar](https://github.com/archr-linux/Arch-R/releases/download/$DATE/ArchR-SM8650.aarch64-$DATE.tar) |

## Documentation

### Contribute

* [Building ArchR](https://github.com/archr-linux/distribution/wiki/contribute/build/)
* [Code of Conduct](https://github.com/archr-linux/distribution/wiki/contribute/code-of-conduct/)
* [Contributing to ArchR](https://github.com/archr-linux/distribution/wiki/contribute/)
* [Modifying ArchR](https://github.com/archr-linux/distribution/wiki/contribute/modify/)
* [Adding Hardware Quirks](https://github.com/archr-linux/distribution/wiki/contribute/quirks/)
* [Creating Packages](https://github.com/archr-linux/distribution/wiki/contribute/packages/)
* [Pull Request Template](/PULL_REQUEST_TEMPLATE.md)

### Play

* [Installing ArchR](https://github.com/archr-linux/distribution/wiki/play/install/)
* [Updating ArchR](https://github.com/archr-linux/distribution/wiki/play/update/)
* [Controls](https://github.com/archr-linux/distribution/wiki/play/controls/)
* [Netplay](https://github.com/archr-linux/distribution/wiki/play/netplay/)
* [Configuring Moonlight](https://github.com/archr-linux/distribution/wiki/systems/moonlight/)
* [Device Specific Documentation](/documentation/PER_DEVICE_DOCUMENTATION)

### Configure

* [Optimizations](https://github.com/archr-linux/distribution/wiki/configure/optimizations/)
* [Shaders](https://github.com/archr-linux/distribution/wiki/configure/shaders/)
* [Cloud Sync](https://github.com/archr-linux/distribution/wiki/configure/cloud-sync/)
* [VPN](https://github.com/archr-linux/distribution/wiki/configure/vpn/)

### Other

* [Frequently Asked Questions](https://github.com/archr-linux/distribution/wiki/faqs/)
* [Donating to ArchR](https://github.com/archr-linux/Arch-R)

## Change Log

### New Features
* Added...?

### Updates
* Updated...?

### Bug Fixes
* Fixed...?

**Full Changelog**: https://github.com/archr-linux/Arch-R/compare/$LAST_TAG...$DATE
