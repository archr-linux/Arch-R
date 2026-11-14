# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="commander"
PKG_VERSION="b3c008cac3bff9de54a3542cecc53cc271058744"
PKG_REV="2"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/ROCKNIX/commander"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain SDL2 SDL2_image SDL2_gfx SDL2_ttf dejavu"
PKG_LONGDESC="A minimal SDL2 file manager for embedded Linux devices."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET+=" -DCMAKE_BUILD_TYPE=Release"

# Commander's defaults (open B, back A) suit a positional SDL mapping where
# the right face button is "b". Arch R's controller mapping names the
# buttons as printed (the right one is A), so open/back came out swapped.
pre_configure_target() {
  CXXFLAGS+=" -DCMDR_GAMEPAD_OPEN=ControllerButton::A -DCMDR_GAMEPAD_PARENT=ControllerButton::B"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/share/commander

  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/commander ${INSTALL}/usr/bin/
  cp -rf ${PKG_BUILD}/res ${INSTALL}/usr/share/commander/res

  chmod 0755 ${INSTALL}/usr/bin/commander
}
