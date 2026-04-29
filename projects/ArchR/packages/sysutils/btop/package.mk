# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="btop"
PKG_VERSION="v1.4.0"
PKG_LICENSE="Apache-2.0"
PKG_SITE="https://github.com/aristocratos/btop"
PKG_URL="https://github.com/aristocratos/btop/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain coreutils gcc"
PKG_LONGDESC="Resource monitor that shows usage and stats for processor, memory, disks, network and processes."
PKG_TOOLCHAIN="cmake"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/local/share/btop/themes

  cp ${PKG_BUILD}/themes/* ${INSTALL}/usr/local/share/btop/themes
  cp ${PKG_BUILD}/.${TARGET_NAME}/btop ${INSTALL}/usr/bin/btop

  chmod 755 ${INSTALL}/usr/bin/btop
}