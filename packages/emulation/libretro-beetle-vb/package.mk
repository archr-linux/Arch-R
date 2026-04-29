# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-beetle-vb"
PKG_VERSION="8f837ebc077afdd6652efb2827fd8308a07113ca"
PKG_SHA256="d2733026bde2b8049b8258f68d49954687ab43e2639d6a879c79cca68e91dea6"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-vb-libretro"
PKG_URL="https://github.com/libretro/beetle-vb-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libretro implementation of Mednafen VB (VirtualBoy)"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mednafen_vb_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BEETLE-VB_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
