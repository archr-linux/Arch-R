# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-snes9x"
PKG_VERSION="49f484569ff2aec7ff08e7598a97d6c9e6eae72d"
PKG_SHA256="54036e672494f38d7a12a242ed9ddf124685c2cf3563ffc3ebf07c4882405cb0"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/libretro/snes9x"
PKG_URL="https://github.com/libretro/snes9x/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Snes9x - Portable Super Nintendo Entertainment System (TM) emulator"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="snes9x_libretro.so"
PKG_LIBPATH="libretro/${PKG_LIBNAME}"
PKG_LIBVAR="SNES9X_LIB"

PKG_MAKE_OPTS_TARGET="-C libretro/"

if [ "${DEVICE}" = "OdroidGoAdvance" ]; then
  PKG_MAKE_OPTS_TARGET+=" platform=classic_armv8_a35"
fi

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
