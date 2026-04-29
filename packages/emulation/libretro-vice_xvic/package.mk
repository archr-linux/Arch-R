# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2023-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-vice_xvic"
PKG_VERSION="8afb6a3a407e5ee40d48df45031c615507dd094e"
PKG_SHA256="3d0f24ff795241d56678f6cffb78875c8ea0274dfeb59e83b919ab0cca946c6d"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/vice-libretro"
PKG_URL="https://github.com/libretro/vice-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Versatile Commodore 8-bit Emulator version"
PKG_TOOLCHAIN="manual"

PKG_LIBNAME="vice_xvic_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="VICE-XVIC_LIB"

make_target() {
  make EMUTYPE=xvic
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
