# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-dosbox-pure"
PKG_VERSION="64600697f5623c755eaf47f198fa0c5080084b32"
PKG_SHA256="bc2b1062383a5089723afdb67febedeb8b6d0d1e14080086a6e90021f60a67ae"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/dosbox-pure"
PKG_URL="https://github.com/libretro/dosbox-pure/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="DOSBox Pure is a fork of DOSBox, an emulator for DOS games, built for RetroArch/Libretro aiming for simplicity and ease of use."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="dosbox_pure_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="DOSBOX-PURE_LIB"

PKG_BUILD_FLAGS="+pic"

make_target() {
  # remove optimization from CFLAGS, set via Makefile
  CFLAGS="${CFLAGS//-O3/}"
  CFLAGS="${CFLAGS//-O2/}"
  make CXX=${CXX} CPUFLAGS="${CFLAGS}"
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
