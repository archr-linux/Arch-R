# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="geolith-lr"
PKG_VERSION="1391cef3d373cd2aaf4f8a0478b9d6f831c7dfac"
PKG_ARCH="aarch64"
PKG_LICENSE="BSD"
PKG_SITE="https://github.com/libretro/geolith-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Geolith is a highly accurate emulator for the Neo Geo AES and MVS."
PKG_TOOLCHAIN="make"

make_target() {
cd libretro
  make -f ./Makefile platform=${DEVICE}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp geolith_libretro.so ${INSTALL}/usr/lib/libretro/
}
