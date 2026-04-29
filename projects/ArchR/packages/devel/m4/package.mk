# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
# Override: downgrade to 1.4.19 to avoid gnulib _Generic conflicts with GCC 15+
# m4 1.4.20 ships gnulib with _Generic macros that produce syntax errors on GCC 15

PKG_NAME="m4"
PKG_VERSION="1.4.19"
PKG_SHA256="63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96"
PKG_LICENSE="GPL"
PKG_SITE="http://www.gnu.org/software/m4/"
PKG_URL="https://mirrors.kernel.org/gnu/m4/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="ccache:host"
PKG_LONGDESC="The m4 macro processor."
PKG_BUILD_FLAGS="-cfg-libs:host"

PKG_CONFIGURE_OPTS_HOST="gl_cv_func_gettimeofday_clobber=no --target=${TARGET_NAME}"

post_makeinstall_host() {
  make prefix=${SYSROOT_PREFIX}/usr install
}
