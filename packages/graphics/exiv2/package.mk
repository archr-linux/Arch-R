# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2024-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="exiv2"
PKG_VERSION="0.28.5"
PKG_SHA256="e1671f744e379a87ba0c984617406fdf8c0ad0c594e5122f525b2fb7c28d394d"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://exiv2.org"
PKG_URL="https://github.com/Exiv2/exiv2/archive/refs/tags/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Exiv2 is a Cross-platform C++ library to manage image metadata."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DBUILD_SHARED_LIBS=OFF \
                       -DEXIV2_ENABLE_WEBREADY=OFF \
                       -DEXIV2_ENABLE_XMP=OFF \
                       -DEXIV2_ENABLE_CURL=OFF \
                       -DEXIV2_ENABLE_NLS=OFF \
                       -DEXIV2_BUILD_SAMPLES=OFF \
                       -DEXIV2_BUILD_UNIT_TESTS=OFF \
                       -DEXIV2_ENABLE_VIDEO=OFF \
                       -DEXIV2_ENABLE_BMFF=OFF \
                       -DEXIV2_ENABLE_BROTLI=OFF \
                       -DEXIV2_ENABLE_INIH=OFF \
                       -DEXIV2_ENABLE_FILESYSTEM_ACCESS=OFF \
                       -DEXIV2_BUILD_EXIV2_COMMAND=OFF \
                       -DBUILD_WITH_CCACHE=ON"
