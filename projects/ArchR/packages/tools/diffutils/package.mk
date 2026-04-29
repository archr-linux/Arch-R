# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="diffutils"
PKG_VERSION="3.11"
PKG_SHA256="a73ef05fe37dd585f7d87068e4a0639760419f810138bd75c61ddaa1f9e2131e"
PKG_LICENSE="GPL"
PKG_SITE="http://www.gnu.org/software/diffutils/"
PKG_URL="https://mirrors.kernel.org/gnu/diffutils/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A package of several programs related to finding differences between files."

PKG_CONFIGURE_OPTS_TARGET="--disable-nls \
                           --without-libsigsegv-prefix \
                           --without-libiconv-prefix \
                           --without-libintl-prefix"
