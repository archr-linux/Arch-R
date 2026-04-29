# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/devel/binutils/package.mk

# gprofng fails to build with GCC 15 / glibc _Generic conflict
PKG_CONFIGURE_OPTS_HOST="${PKG_CONFIGURE_OPTS_HOST} --disable-gprofng"
