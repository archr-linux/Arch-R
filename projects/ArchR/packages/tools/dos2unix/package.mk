# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="dos2unix"
PKG_VERSION="7.5.2"
PKG_SHA256="264742446608442eb48f96c20af6da303cb3a92b364e72cb7e24f88239c4bf3a"
PKG_LICENSE="BSD"
PKG_SITE="https://waterlan.home.xs4all.nl/dos2unix.html"
PKG_URL="https://waterlan.home.xs4all.nl/dos2unix/dos2unix-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="DOS/Mac to Unix and vice versa text file format converter."
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="prefix=/usr"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a ${PKG_BUILD}/dos2unix ${INSTALL}/usr/bin/
  cp -a ${PKG_BUILD}/unix2dos ${INSTALL}/usr/bin/
}
