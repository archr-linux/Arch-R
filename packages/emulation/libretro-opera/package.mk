# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-opera"
PKG_VERSION="67a29e60a4d194b675c9272b21b61eaa022f3ba3"
PKG_SHA256="e4135d62160f84d3bc287d165ef514a3e4ea31b759888ee29bde05e8c899b666"
PKG_LICENSE="LGPL with additional notes"
PKG_SITE="https://github.com/libretro/opera-libretro"
PKG_URL="https://github.com/libretro/opera-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Port of 4DO/libfreedo to libretro."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="opera_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="OPERA_LIB"

pre_make_target() {
  PKG_MAKE_OPTS_TARGET="CC=${CC} CXX=${CXX} AR=${AR}"
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
