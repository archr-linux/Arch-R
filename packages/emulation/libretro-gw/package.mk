# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-gw"
PKG_VERSION="435e5cfd4bf6aea03a84259e9b8dba3daf3ff5bd"
PKG_SHA256="610f613aedb6182b00bd4231e53d4350977b97e28f6f551cec138ef810cbb761"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/gw-libretro"
PKG_URL="https://github.com/libretro/gw-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A libretro core for Game & Watch simulators"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="gw_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="GW_LIB"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
