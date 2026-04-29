# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-fuse"
PKG_VERSION="cad85b7b1b864c65734f71aa4a510b6f6536881c"
PKG_SHA256="6fda1a3ffc0d2faeebe27fae94e5b7790337dd96d1ea29922ad804a425d2852b"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/fuse-libretro"
PKG_URL="https://github.com/libretro/fuse-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain bzip2"
PKG_LONGDESC="A port of the Fuse Unix Spectrum Emulator to libretro "
PKG_TOOLCHAIN="make"

PKG_LIBNAME="fuse_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="FUSE_LIB"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

pre_make_target() {
  CFLAGS+=" -DHAVE_LIBBZ2"
  CXXFLAGS+=" -DHAVE_LIBBZ2"
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
