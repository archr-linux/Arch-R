# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-beetle-bsnes"
PKG_VERSION="f7bfa217cf7150779902c3a998f7624d92a5f17d"
PKG_SHA256="a299383932e35d5030145e14c7fbab57ba6e1fa81e00c866b1bdcbc70bfac1c6"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-bsnes-libretro"
PKG_URL="https://github.com/libretro/beetle-bsnes-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Standalone port of Mednafen bSNES to libretro, itself a fork of bsnes 0.59."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mednafen_snes_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BEETLE-BSNES_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
