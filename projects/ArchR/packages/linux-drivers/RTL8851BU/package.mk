# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="RTL8851BU"
PKG_VERSION="f94ea820634d3bd050009e861952d3b8eeef869a"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/neatojones/RTL8851bu"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="Realtek 8851BU Linux driver"
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS

  # Switch platform for cross-compilation
  sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' ${PKG_BUILD}/Makefile
  sed -i 's/CONFIG_PLATFORM_ARM64_PC = n/CONFIG_PLATFORM_ARM64_PC = y/' ${PKG_BUILD}/Makefile
}

make_target() {
  make V=1 \
       ARCH=${TARGET_KERNEL_ARCH} \
       KSRC=$(kernel_path) \
       CROSS_COMPILE=${TARGET_KERNEL_PREFIX} \
       CONFIG_RTW_DEBUG=n
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
    cp *.ko ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
}
