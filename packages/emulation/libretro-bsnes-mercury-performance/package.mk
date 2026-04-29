# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-bsnes-mercury-performance"
PKG_VERSION="0f35d044bf2f2b879018a0500e676447e93a1db1"
PKG_SHA256="aba28b88898492239bbe752cc8fa5c62d89d5a9f6ddbafd4b4ae97b1d34c41ec"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/bsnes-mercury"
PKG_URL="https://github.com/libretro/bsnes-mercury/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Fork of bsnes with HLE DSP emulation restored."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="bsnes_mercury_performance_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BSNES-MERCURY-PERFORMANCE_LIB"

PKG_MAKE_OPTS_TARGET="ui=target-libretro profile=performance"

pre_make_target() {
  PKG_MAKE_OPTS_TARGET+=" compiler=${CXX}"
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
