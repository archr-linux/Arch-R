# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024 ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="swayimg"
PKG_VERSION="v2.1"
PKG_SHA256="d82fb8e75cdabf470677797444ec19b00c83e0e06d80be774727194404624e7e"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/artemsen/swayimg"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain cairo wayland-protocols libpng libjpeg-turbo libwebp libxkbcommon jsoncpp zlib"
PKG_LONGDESC="A fast, lightweight and minimalistic Wayland terminal emulator"
PKG_TOOLCHAIN="meson"

PKG_MESON_OPTS_TARGET="-D bash=disabled \
        		    	-D desktop=true \
        				-D exif=disabled \
        				-D gif=disabled \
        				-D heif=disabled \
        				-D jpeg=enabled \
        				-D jxl=disabled \
        				-D man=false \
        				-D png=enabled \
				        -D svg=disabled \
				        -D tiff=enabled \
				        -D webp=enabled"

pre_configure_target() {
  export TARGET_LDFLAGS="-L${SYSROOT_PREFIX}/usr/lib -lm -lz"
}
