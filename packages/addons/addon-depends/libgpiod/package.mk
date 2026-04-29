# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libgpiod"
PKG_VERSION="2.2.2"
PKG_SHA256="d0b1380c3cbabbb49b82f709b3288376d98347d4436613407d19cc4cbbfc45a6"
PKG_LICENSE="GPLv2+"
PKG_SITE="https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/about/"
PKG_URL="https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/snapshot/libgpiod-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain Python3 setuptools:host"
PKG_LONGDESC="Tools for interacting with the linux GPIO character device."
PKG_TOOLCHAIN="autotools"
PKG_BUILD_FLAGS="+pic -sysroot"

PKG_CONFIGURE_OPTS_TARGET="--enable-tools --disable-shared"

post_make_target() {
  (
    LDFLAGS+=" -L${PKG_BUILD}/.${TARGET_NAME}/lib/.libs"
    CFLAGS+=" -I${PKG_BUILD}/include"
    cd ../bindings/python
    python_target_env python3 -m build -n -w -x
  )
}
