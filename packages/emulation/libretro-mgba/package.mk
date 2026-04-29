# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-mgba"
PKG_VERSION="747362c02d2e71ee7c363e8dcb240925be8af906"
PKG_SHA256="9a49e66b28296f11e04161dacf8cfc89f113504b87f40f5857a884d513c394a8"
PKG_LICENSE="MPLv2.0"
PKG_SITE="https://github.com/libretro/mgba"
PKG_URL="https://github.com/libretro/mgba/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="mGBA Game Boy Advance Emulator"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="mgba_libretro.so"
PKG_LIBPATH="../${PKG_LIBNAME}"
PKG_LIBVAR="MGBA_LIB"

PKG_MAKE_OPTS_TARGET="-C ../ -f Makefile.libretro"

if [ "${ARCH}" = "arm" ]; then
  PKG_MAKE_OPTS_TARGET+=" platform=unix-armv"
fi

if target_has_feature neon; then
  PKG_MAKE_OPTS_TARGET+=" HAVE_NEON=1"
fi

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
