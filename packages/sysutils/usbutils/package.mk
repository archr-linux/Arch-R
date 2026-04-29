# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2020-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="usbutils"
PKG_VERSION="018"
PKG_SHA256="83f68b59b58547589c00266e82671864627593ab4362d8c807f50eea923cad93"
PKG_LICENSE="GPL"
PKG_SITE="http://www.linux-usb.org/"
PKG_URL="http://kernel.org/pub/linux/utils/usb/usbutils/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain libusb systemd"
PKG_LONGDESC="This package contains various utilities for inspecting and setting of devices connected to the USB bus."

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin/lsusb.py
  rm -rf ${INSTALL}/usr/bin/usbhid-dump
}
