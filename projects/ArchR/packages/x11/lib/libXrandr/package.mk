# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/x11/lib/libXrandr/package.mk

PKG_DEPENDS_HOST="toolchain:host util-macros:host libX11:host libXrender:host libXext:host"
