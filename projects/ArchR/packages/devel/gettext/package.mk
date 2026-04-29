# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
# Override: downgrade to 0.24 to avoid gnulib _Generic conflicts with GCC 15+

PKG_NAME="gettext"
PKG_VERSION="0.24"
PKG_SHA256="e1620d518b26d7d3b16ac570e5018206e8b0d725fb65c02d048397718b5cf318"
PKG_LICENSE="GPL"
PKG_SITE="https://www.gnu.org/s/gettext/"
PKG_URL="https://mirrors.kernel.org/gnu/gettext/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="make:host"
PKG_DEPENDS_TARGET="autotools:host make:host gcc:host"
PKG_LONGDESC="A program internationalization library and tools."
PKG_BUILD_FLAGS="+local-cc"
