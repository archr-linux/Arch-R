# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-cap32"
PKG_VERSION="dbfa1aa2dc132f57289329252829174c1cea4230"
PKG_SHA256="7296917304e07a67a0fa66e5da30c8f855a9c0ed3cb65e6b8e50dd262f078bf0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/libretro-cap32"
PKG_URL="https://github.com/libretro/libretro-cap32/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="caprice32 4.2.0 libretro"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="cap32_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="CAP32_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
