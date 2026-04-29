# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="libassuan"
PKG_VERSION="3.0.2"
PKG_SHA256="d2931cdad266e633510f9970e1a2f346055e351bb19f9b78912475b8074c36f6"
PKG_LICENSE="LGPLv2.1+"
PKG_SITE="https://gnupg.org/software/libassuan/index.html"
PKG_URL="https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain libgpg-error"
PKG_LONGDESC="Libassuan is a small library implementing the so-called Assuan protocol."
PKG_TOOLCHAIN="autotools"

PKG_CONFIGURE_OPTS_TARGET="--enable-static \
                           --enable-shared \
                           --with-gnu-ld \
                           --with-pic \
                           --with-libgpg-error-prefix=${SYSROOT_PREFIX}/usr"

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin
  rm -rf ${INSTALL}/usr/share
}
