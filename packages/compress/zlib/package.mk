# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

# Drop-in zlib replacement using zlib-ng compiled with --zlib-compat.
# ABI/API identical to upstream zlib (libz.so.1), but ships SIMD-aware
# inflate/deflate paths that NEON-enabled the inner loops on Cortex-A35.
# Real impact: ROM zip extraction in PortMaster/RetroArch and ext2/ext4
# compression utilities run noticeably faster.
#
# We keep PKG_NAME="zlib" so every other package's PKG_DEPENDS_*="zlib"
# transparently picks up the replacement. Source unpack is overridden
# because the upstream tarball expands to zlib-ng-${PKG_VERSION}/.

PKG_NAME="zlib"
PKG_VERSION="2.2.4"
PKG_SHA256="a73343c3093e5cdc50d9377997c3815b878fd110bf6511c2c7759f2afb90f5a3"
PKG_LICENSE="OSS"
PKG_SITE="https://github.com/zlib-ng/zlib-ng"
PKG_URL="https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_SOURCE_NAME="zlib-ng-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="ccache:host cmake:host"
PKG_DEPENDS_TARGET="cmake:host gcc:host"
PKG_LONGDESC="zlib-ng compiled in --zlib-compat mode — drop-in libz with SIMD-accelerated inflate/deflate."
PKG_TOOLCHAIN="cmake-make"

# zlib-ng reads CMAKE flags directly. ZLIB_COMPAT=ON is what makes this
# build emit libz.so.1 (instead of libz-ng.so.2) so existing pkgconfig
# pointers keep working. WITH_GZFILEOP keeps gzopen()/gzread()/etc.
# Tests/benchmarks off to avoid pulling gtest into the cross toolchain.
PKG_CMAKE_OPTS_HOST="-DZLIB_COMPAT=ON \
                     -DZLIB_ENABLE_TESTS=OFF \
                     -DZLIBNG_ENABLE_TESTS=OFF \
                     -DWITH_GTEST=OFF \
                     -DWITH_GZFILEOP=ON \
                     -DINSTALL_PKGCONFIG_DIR=${TOOLCHAIN}/lib/pkgconfig"

PKG_CMAKE_OPTS_TARGET="-DZLIB_COMPAT=ON \
                       -DZLIB_ENABLE_TESTS=OFF \
                       -DZLIBNG_ENABLE_TESTS=OFF \
                       -DWITH_GTEST=OFF \
                       -DWITH_GZFILEOP=ON \
                       -DWITH_OPTIM=ON \
                       -DWITH_NEON=ON \
                       -DINSTALL_PKGCONFIG_DIR=/usr/lib/pkgconfig"

unpack() {
  mkdir -p "${PKG_BUILD}"
  tar --strip-components=1 -xf "${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME}" -C "${PKG_BUILD}"
}
