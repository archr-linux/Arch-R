# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="findutils"
PKG_VERSION="4.10.0"
PKG_SHA256="1387e0b67ff247d2abde998f90dfbf70c1491391a59ddfecb8ae698789f0a4f5"
PKG_LICENSE="GPL"
PKG_SITE="http://www.gnu.org/software/findutils/"
PKG_URL="https://mirrors.kernel.org/gnu/findutils/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="GNU findutils - find, xargs, and locate utilities."

PKG_CONFIGURE_OPTS_TARGET="--disable-nls \
                           --without-selinux \
                           --disable-locate"
