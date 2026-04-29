# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="gpgme"
PKG_VERSION="2.0.0"
PKG_SHA256="ddf161d3c41ff6a3fcbaf4be6c6e305ca4ef1cc3f1ecdfce0c8c2a167c0cc36d"
PKG_LICENSE="LGPLv2.1+"
PKG_SITE="https://gnupg.org/software/gpgme/index.html"
PKG_URL="https://gnupg.org/ftp/gcrypt/gpgme/gpgme-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain libassuan libgpg-error"
PKG_LONGDESC="GnuPG Made Easy (GPGME) is a library designed to make access to GnuPG easier for applications."
PKG_TOOLCHAIN="autotools"

PKG_CONFIGURE_OPTS_TARGET="--enable-languages=cl \
                           --disable-static \
                           --enable-shared \
                           --disable-glibtest \
                           --disable-gpgconf-test \
                           --disable-gpg-test \
                           --disable-gpgsm-test \
                           --disable-g13-test \
                           --with-pic \
                           --with-libgpg-error-prefix=${SYSROOT_PREFIX}/usr \
                           --with-libassuan-prefix=${SYSROOT_PREFIX}/usr"

pre_configure_target() {
  CFLAGS+=" -I${SYSROOT_PREFIX}/usr/include"
  LDFLAGS+=" -L${SYSROOT_PREFIX}/usr/lib"
}

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin
  rm -rf ${INSTALL}/usr/share
}
