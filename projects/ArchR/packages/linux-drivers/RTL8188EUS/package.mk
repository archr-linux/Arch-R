# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="RTL8188EUS"
PKG_VERSION="af3bf004458f76b7aec33e9ba552cd382ed1f5c3"
PKG_REV="4"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/aircrack-ng/rtl8188eus"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="Realtek RTL8188EUS USB WiFi driver (out-of-tree). The
in-tree rtl8xxxu claims this chip but fails the WPA2 4-way handshake
on RTL8188EUS dongles (scan ok, auth times out — issue #19). The
aircrack-ng fork is the maintained driver that completes the
handshake with iwd/wpa_supplicant; the shipped udev rule unbinds
rtl8xxxu from the specific USB IDs at hotplug and lets 8188eu take
over."
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"
GET_HANDLER_SUPPORT="git"

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  make V=1 \
       ARCH=${TARGET_KERNEL_ARCH} \
       KSRC=$(kernel_path) \
       CROSS_COMPILE=${TARGET_KERNEL_PREFIX} \
       CONFIG_POWER_SAVING=y
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/realtek/r8188eu
    cp 8188eu.ko ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/realtek/r8188eu/
}
