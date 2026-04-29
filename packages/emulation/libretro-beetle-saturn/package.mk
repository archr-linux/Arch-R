# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2023-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-beetle-saturn"
PKG_VERSION="0a78a9a5ab0088ba19f21e028dda9f4b4d7c9e48"
PKG_SHA256="3d342a7b29640042af7e245b97375f4e287925c0f5b7f95144ae57b12f96bef8"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-saturn-libretro"
PKG_URL="https://github.com/libretro/beetle-saturn-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Standalone port of Mednafen Saturn to libretro."
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="HAVE_CDROM=1"

PKG_LIBNAME="mednafen_saturn_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BEETLE-SATURN_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
