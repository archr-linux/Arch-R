# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="RTL8852AU"
PKG_VERSION="865ab0fa91471d595c283d2f3db323f7f15455f5"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/lwfinger/rtl8852au"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="Realtek RTL8852AU USB WiFi 6 driver. Out of tree because mainline has no USB glue for this chip on 6.12; the in-kernel rtw89 only gains 8852AU USB support past 6.17. NOTE: does not build against 6.12 yet (rtw_pwrctrl API break); kept out of ADDITIONAL_DRIVERS until ported."
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
