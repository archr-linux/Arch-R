# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-fmsx"
PKG_VERSION="9eb5f25df5397212a3e3088ca1a64db0740bbe5f"
PKG_SHA256="a20197dc2bf8ab01f79dc341233656053de8bd78cf8e597b6e375bf0722d2b28"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/libretro/fmsx-libretro"
PKG_URL="https://github.com/libretro/fmsx-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Port of fMSX to the libretro API."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="fmsx_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="FMSX_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
