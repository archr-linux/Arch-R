# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2020-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="lcms2"
PKG_VERSION="2.17"
PKG_SHA256="d11af569e42a1baa1650d20ad61d12e41af4fead4aa7964a01f93b08b53ab074"
PKG_LICENSE="MIT/GPLv3"
PKG_SITE="http://www.littlecms.com"
PKG_URL="https://github.com/mm2/Little-CMS/releases/download/lcms${PKG_VERSION}/lcms2-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain tiff"
PKG_LONGDESC="An small-footprint color management engine, with special focus on accuracy and performance."
PKG_BUILD_FLAGS="+pic"

PKG_MESON_OPTS_TARGET="-Ddefault_library=static \
                       -Dprefer_static=true \
                       -Dtests=disabled \
                       -Dutils=true"
