# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-bluemsx"
PKG_VERSION="572c91856a5288b7433c619af651e31f00f3ce7e"
PKG_SHA256="86625bb7f6d1a5abb22d4eaf4691906aa985352519ad8193e63995b010ed214d"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/blueMSX-libretro"
PKG_URL="https://github.com/libretro/blueMSX-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Port of blueMSX to the libretro API."
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

PKG_LIBNAME="bluemsx_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BLUEMSX_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
