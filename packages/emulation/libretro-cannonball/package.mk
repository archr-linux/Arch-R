# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2023-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-cannonball"
PKG_VERSION="5137a791d229a5b9c7c089cf1edcce4db3c57d64"
PKG_SHA256="f066944897cde7bbf3df365ac75c2cc1ef5114059d1a0c51782f12bff5bcfa73"
PKG_LICENSE="MAME"
PKG_SITE="https://github.com/libretro/cannonball"
PKG_URL="https://github.com/libretro/cannonball/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Cannonball: An Enhanced OutRun Engine"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="cannonball_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="CANNONBALL_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake

  mkdir -p ${SYSROOT_PREFIX}/usr/share/retroarch/system/cannonball/res/
  cp -v res/{tilemap.bin,tilepatch.bin} docs/license.txt ${SYSROOT_PREFIX}/usr/share/retroarch/system/cannonball/res/
  cp -v roms/roms.txt ${SYSROOT_PREFIX}/usr/share/retroarch/system/cannonball/
}
