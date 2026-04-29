# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/devel/readline/package.mk

PKG_CONFIGURE_OPTS_TARGET="bash_cv_wcwidth_broken=no \
                           --enable-shared \
                           --disable-static \
                           --with-curses"

# Ensure shared libreadline.so links against ncurses (provides termcap symbols: BC, UP, tputs, etc.)
PKG_MAKE_OPTS_TARGET="SHLIB_LIBS=-lncursesw"
PKG_MAKEINSTALL_OPTS_TARGET="SHLIB_LIBS=-lncursesw"

pre_configure_target() {
  export LDFLAGS="${LDFLAGS} -lncursesw"
}
