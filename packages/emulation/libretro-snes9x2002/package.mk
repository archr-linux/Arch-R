# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-snes9x2002"
PKG_VERSION="a0709ec7dcd6de2fbebb43106bd757b649e3b7cf"
PKG_SHA256="58abd84309d0fafacccd94920aa4b99eeb935c4157971487c1052b6104de2412"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/libretro/snes9x2002"
PKG_URL="https://github.com/libretro/snes9x2002/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Snes9x 2002. Port of SNES9x 1.39 for libretro (was previously called PocketSNES). Heavily optimized for ARM."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="snes9x2002_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="SNES9X2002_LIB"

PKG_MAKE_OPTS_TARGET="platform=unix"

if [ "${PROJECT}" = "RPi" ] && [ "${DEVICE}" = "RPi" -o "${DEVICE}" = "GPICase" ]; then
  PKG_MAKE_OPTS_TARGET+=" ARM_ASM=1"
fi

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
