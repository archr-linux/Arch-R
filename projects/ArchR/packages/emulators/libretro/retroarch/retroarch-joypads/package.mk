# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="retroarch-joypads"
PKG_VERSION="38cf938bba0adbde375972053068f10d955a9d14"
# PKG_VERSION pins the upstream autoconfig db. The local gamepads/ overlay
# (e.g. the corrected GO-Super Gamepad.cfg) does not change that hash, so
# bump PKG_REV to ship overlay-only fixes as a pacman update. gen-pacman-repo
# now maps PKG_REV to the package release.
PKG_REV="3"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/libretro/retroarch-joypad-autoconfig"
PKG_URL="https://github.com/libretro/retroarch-joypad-autoconfig/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="RetroArch joypad autoconfigs."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/libretro/autoconfig
    cp -an ${PKG_BUILD}/{linuxraw,sdl2,udev,x,xinput}/*.cfg ${INSTALL}/usr/share/libretro/autoconfig
    cp -a ${PKG_DIR}/gamepads/* ${INSTALL}/usr/share/libretro/autoconfig

  # Upstream ships its own go_super_gamepad.cfg with a mapping that does not
  # match our hardware (up=8/down=9/left=10/...). It matches the device by
  # the same name as our corrected "GO-Super Gamepad.cfg" with equal
  # affinity, and RetroArch's external-autoconfig scan keeps whichever file
  # readdir() happens to return first - so the wrong map wins at random
  # (#40). Ours is the only ArchR pad name that collides with the upstream
  # db; drop the upstream copy.
  rm -f ${INSTALL}/usr/share/libretro/autoconfig/go_super_gamepad.cfg
}

post_install() {
  enable_service tmp-joypads.mount
}
