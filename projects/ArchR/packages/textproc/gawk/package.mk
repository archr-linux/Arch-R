# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="gawk"
PKG_VERSION="5.3.1"
PKG_SHA256="694db764812a6236423d4ff40ceb7b6c4c441301b72ad502bb5c27e00cd56f78"
PKG_LICENSE="GPL"
PKG_SITE="http://www.gnu.org/software/gawk/"
PKG_URL="https://mirrors.kernel.org/gnu/gawk/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="GNU awk - pattern scanning and processing language."

PKG_CONFIGURE_OPTS_TARGET="--disable-nls \
                           --without-readline \
                           --without-mpfr"

post_makeinstall_target() {
  # Remove gawk profile.d scripts (csh syntax causes errors in sh/bash login shells)
  rm -rf ${INSTALL}/etc/profile.d/gawk.*
}

post_install() {
  # Create awk -> gawk symlink
  ln -sf gawk ${INSTALL}/usr/bin/awk
}
