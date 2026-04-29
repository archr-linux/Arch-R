# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/web/curl/package.mk

PKG_CMAKE_OPTS_TARGET="${PKG_CMAKE_OPTS_TARGET//\/run\/libreelec\/cacert.pem/\/run\/archr\/cacert.pem}"
