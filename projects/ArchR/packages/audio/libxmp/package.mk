# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="libxmp"
PKG_VERSION="8201d26cf933688a8be64292457c429fd8e654ab" #v4.6.0
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libxmp/libxmp"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libxmp is a library that renders module files to PCM data."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
