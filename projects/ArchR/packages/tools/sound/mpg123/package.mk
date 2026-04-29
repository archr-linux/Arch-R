# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
# Standalone: original sourced from packages/addons/ which is gitignored

PKG_NAME="mpg123"
PKG_VERSION="1.33.0"
PKG_SHA256="2290e3aede6f4d163e1a17452165af33caad4b5f0948f99429cfa2d8385faa9d"
PKG_LICENSE="LGPLv2"
PKG_SITE="https://www.mpg123.org/"
PKG_URL="https://downloads.sourceforge.net/sourceforge/mpg123/mpg123-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain alsa-lib SDL2 openal-soft"
PKG_LONGDESC="A console based real time MPEG Audio Player for Layer 1, 2 and 3."
PKG_BUILD_FLAGS="+pic"

if [ "${PIPEWIRE_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" pipewire"
fi
