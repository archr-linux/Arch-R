# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="xdelta3"
PKG_VERSION="3.1.0"
PKG_SHA256="114543336ab6cee3764e3c03202701ef79d7e5e8e4863fe64811e4d9e61884dc"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/jmacd/xdelta-gpl"
PKG_URL="https://github.com/jmacd/xdelta-gpl/releases/download/v${PKG_VERSION}/xdelta3-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain xz"
PKG_LONGDESC="Binary delta compression tool, used by PortMaster ports for patching game files."
PKG_TOOLCHAIN="autotools"

PKG_CONFIGURE_OPTS_TARGET="--with-liblzma"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a xdelta3 ${INSTALL}/usr/bin/
}
