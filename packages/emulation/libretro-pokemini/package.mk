# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-pokemini"
PKG_VERSION="78656d4615691c393e65e48672ce5fff5b1f97d3"
PKG_SHA256="ded9849c2bc8c3b9ca363202324760f4d967f1536eb557364ef94e757fa675d2"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/pokemini"
PKG_URL="https://github.com/libretro/PokeMini/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Obscure nintendo handheld emulator (functional,no color files or savestates currently)"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="pokemini_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="POKEMINI_LIB"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
