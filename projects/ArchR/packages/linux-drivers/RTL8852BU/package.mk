# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="RTL8852BU"
PKG_REV="2"
PKG_VERSION="59a5918e3dc188bb9055e9ba4690623c434e0e11"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/morrownr/rtl8852bu-20250826"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="Realtek RTL8852BU USB WiFi 6 driver. Out of tree because mainline has no USB glue for this chip on 6.12; the in-kernel rtw89 only gains 8852BU USB support in 6.17."
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"

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
  mkdir -p ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
    cp *.ko ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
}
