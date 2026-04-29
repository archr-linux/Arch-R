# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/devel/glib/package.mk

PKG_MESON_OPTS_HOST="-Ddefault_library=shared \
                     -Dinstalled_tests=false \
                     -Dlibmount=disabled \
                     -Dintrospection=disabled \
                     -Dtests=false"
