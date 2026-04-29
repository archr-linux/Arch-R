# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-tgbdual"
PKG_VERSION="8d305769eebd67266c284558f9d3a30498894d3d"
PKG_SHA256="c9286b91fd7840902075601749507e08f9e734aae5a9ccc37805324a348295c5"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/tgbdual-libretro"
PKG_URL="https://github.com/libretro/tgbdual-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libretro port of TGB Dual"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="tgbdual_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="TGBDUAL_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
