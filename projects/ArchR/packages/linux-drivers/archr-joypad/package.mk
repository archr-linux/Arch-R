# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="archr-joypad"
PKG_VERSION="4a8392c1a15a9cf2cab43750c3246d53d6410301"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/archr-linux/archr-joypad"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="archr-joypad: ArchR joypad driver"
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  kernel_make -C $(kernel_path) M=${PKG_BUILD}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
    cp *.ko ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
}
