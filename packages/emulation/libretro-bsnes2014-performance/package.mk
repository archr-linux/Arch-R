# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2023-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-bsnes2014-performance"
PKG_VERSION="3beff8ebfa91d6faaf8b854140fbcb7542a3c516"
PKG_SHA256="39b329918124d39f33267f04b5e7a1fec5561b9c37da47ffd7edcc59fc1abf49"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/bsnes2014"
PKG_URL="https://github.com/libretro/bsnes2014/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro fork of bsnes. As close to upstream as possible."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="bsnes2014_performance_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="BSNES2014-PERFORMANCE_LIB"

pre_make_target() {
  if [ "${ARCH}" = "aarch64" ]; then
    LDFLAGS+=" -lgcc"
  fi
}

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
