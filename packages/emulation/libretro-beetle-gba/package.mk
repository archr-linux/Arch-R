# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-beetle-gba"
PKG_VERSION="6cee80685f735ea6c2373db2622a1f1ee9f39d39"
PKG_SHA256="33ef14eb0141e98323cc8c3e997f668df348fea7b7bf5a97766c2c91af075fa7"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-gba-libretro"
PKG_URL="https://github.com/libretro/beetle-gba-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libretro implementation of Mednafen gba"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mednafen_gba_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BEETLE-GBA_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
