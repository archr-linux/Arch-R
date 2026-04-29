# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="RTL8831"
PKG_VERSION="905fc2dd7890a6d91cb6fe9e2139664a22c7839f"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/biglinux/rtl8831"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="Realtek RTL8831/RTL8851BU USB WiFi 6 driver"
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS

  # Switch platform from I386_PC to ARM64 for cross-compilation
  sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' ${PKG_BUILD}/Makefile
  sed -i 's/CONFIG_PLATFORM_ARM64_PC = n/CONFIG_PLATFORM_ARM64_PC = y/' ${PKG_BUILD}/Makefile

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
