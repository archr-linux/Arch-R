# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libpng"
PKG_VERSION="1.6.50"
PKG_SHA256="4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307"
PKG_LICENSE="LibPNG2"
PKG_SITE="http://www.libpng.org/"
PKG_URL="${SOURCEFORGE_SRC}/libpng/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="zlib:host"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_LONGDESC="An extensible file format for the lossless, portable, well-compressed storage of raster images."
PKG_TOOLCHAIN="configure"
PKG_BUILD_FLAGS="+pic +pic:host"

PKG_CONFIGURE_OPTS_TARGET="ac_cv_lib_z_zlibVersion=yes \
                           --enable-static \
                           --disable-shared"

PKG_CONFIGURE_OPTS_HOST="--enable-static --disable-shared"

pre_configure_host() {
  export CPPFLAGS="${CPPFLAGS} -I${TOOLCHAIN}/include"
}

pre_configure_target() {
  export CPPFLAGS="${CPPFLAGS} -I${SYSROOT_PREFIX}/usr/include"
}

post_makeinstall_target() {
  sed -e "s:\([\"'= ]\)/usr:\\1${SYSROOT_PREFIX}/usr:g" \
      -e "s:libs=\"-lpng16\":libs=\"-lpng16 -lz\":g" \
      -i ${SYSROOT_PREFIX}/usr/bin/libpng*-config

  sed -e 's|^Libs: -L${libdir} -lpng16|Libs: -L${libdir} -lpng16 -lz|g' \
      -i ${SYSROOT_PREFIX}/usr/lib/pkgconfig/libpng*.pc

  rm -rf ${INSTALL}/usr/bin
}
