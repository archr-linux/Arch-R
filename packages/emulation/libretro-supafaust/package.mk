# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-supafaust"
PKG_VERSION="e25f66765938d33f9ad5850e8d6cd597e55b7299"
PKG_SHA256="0b0ff644b780d1565e8f097998f371b1a4255213846c2082d8e8c143d0868ef1"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/supafaust"
PKG_URL="https://github.com/libretro/supafaust/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="SNES emulator for multicore ARM Cortex A7,A9,A15,A53 Linux platforms"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mednafen_supafaust_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="SUPAFAUST_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
