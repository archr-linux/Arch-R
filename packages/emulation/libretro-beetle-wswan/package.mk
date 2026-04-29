# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-beetle-wswan"
PKG_VERSION="2aeb47d3a58bf0360c686f842d9bb5bd201306fe"
PKG_SHA256="035c0ebdad6740511cc395199db134d20c29611b830cf11831d6ec8744a33d42"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-wswan-libretro"
PKG_URL="https://github.com/libretro/beetle-wswan-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libretro implementation of Mednafen wswan"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mednafen_wswan_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BEETLE-WSWAN_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
