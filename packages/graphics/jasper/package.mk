# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="jasper"
PKG_VERSION="4.2.5"
PKG_SHA256="3f4b1df7cab7a3cc67b9f6e28c730372f030b54b0faa8548a9ee04ae83fffd44"
PKG_LICENSE="OpenSource"
PKG_SITE="http://www.ece.uvic.ca/~mdadams/jasper/"
PKG_URL="https://github.com/jasper-software/jasper/archive/refs/tags/version-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain libjpeg-turbo"
PKG_LONGDESC="A implementation of the ISO/IEC 15444-1 also known as JPEG-2000 standard for image compression."
PKG_BUILD_FLAGS="+pic"

PKG_CMAKE_OPTS_TARGET="-DJAS_ENABLE_DOC=false \
                       -DJAS_ENABLE_PROGRAMS=false \
                       -DJAS_ENABLE_SHARED=false \
                       -DALLOW_IN_SOURCE_BUILD=ON \
                       -DJAS_STDC_VERSION=201710L"

pre_configure_target() {
  export CFLAGS="${CFLAGS} -std=gnu17"
}
