# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="nvidia-vaapi-driver"
PKG_VERSION="0.0.14"
PKG_SHA256="4ded132ec4164f3e05656061675dffce677327e4af0d8da33da5f8527609ad2a"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/elFarto/nvidia-vaapi-driver"
PKG_URL="https://github.com/elFarto/nvidia-vaapi-driver/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain libva nv-codec-headers gst-plugins-bad"
PKG_LONGDESC="A VA-API implementation using NVIDIA's NVDEC"
