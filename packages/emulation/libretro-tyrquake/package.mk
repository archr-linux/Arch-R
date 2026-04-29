# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-tyrquake"
PKG_VERSION="5486f35371ba7b495d00094e2c343b99f2cc0fa9"
PKG_SHA256="5defdaf1a9a708fa8ef1e630b508621e4541e060a07416686809372ae4d849ba"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/tyrquake"
PKG_URL="https://github.com/libretro/tyrquake/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro port of Tyrquake (Quake 1 engine)"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="tyrquake_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="TYRQUAKE_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
