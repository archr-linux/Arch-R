# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-handy"
PKG_VERSION="4e9e072796e5552a9d57f6ab83b3f85f27b17fb6"
PKG_SHA256="7c21fe578d1ba4271ee07530552b3cfb7deb905147edc3fb7d8c33cf5f45ec4c"
PKG_LICENSE="Zlib"
PKG_SITE="https://github.com/libretro/libretro-handy"
PKG_URL="https://github.com/libretro/libretro-handy/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="K. Wilkins' Atari Lynx emulator Handy for libretro"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="handy_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="HANDY_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
