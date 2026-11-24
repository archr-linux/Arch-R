# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

# Boot files for the RK3562 handhelds. No U-Boot is built yet: the factory
# U-Boot on the eMMC boots the SD card through extlinux/extlinux.conf, so
# this package only ships the extlinux files, one per panel DTB.

PKG_NAME="u-boot"
PKG_VERSION="1.0"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/archr-linux/Arch-R"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Boot configuration (extlinux) for the RK3562 handhelds, booted by the factory U-Boot."
PKG_TOOLCHAIN="manual"

PKG_NEED_UNPACK="${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/bootloader"
PKG_NEED_UNPACK+=" ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/options ${PROJECT_DIR}/${PROJECT}/config.xml"

makeinstall_target() {
  local extl dtbase

  mkdir -p "${INSTALL}/usr/share/bootloader/extlinux"
  extl="${INSTALL}/usr/share/bootloader/extlinux/extlinux.conf"

  sed -e "s|@DISTRO_BOOTLABEL@|${DISTRO_BOOTLABEL}|" \
      -e "s|@DISTRO_ROOTLABEL@|${DISTRO_ROOTLABEL}|" \
      -e "s|@DISTRO_DISKLABEL@|${DISTRO_DISKLABEL}|" \
      -e "s|@EXTRA_CMDLINE@|${EXTRA_CMDLINE}|" \
      "${PKG_DIR}/config/extlinux/extlinux.conf" > "${extl}"
  cp -av "${PKG_DIR}/config/extlinux/README.txt" "${INSTALL}/usr/share/bootloader/extlinux/"

  # extlinux.conf.<board>: one per DTB in config.xml, named after the DTB
  # without the SoC and vendor (rk3562-aislpc-rg52-mini -> rg52-mini).
  for dtbase in $(xmlstarlet sel -t -v "//archr/${DEVICE}//file" "${CONFIGXML}"); do
    sed -e '/##/d' -e "s|^ *FDT .*$|  FDT /dtbs/${dtbase}.dtb|" "${extl}" \
      > "${extl}.${dtbase#rk3562-aislpc-}"
    echo "extlinux: ${extl##*/}.${dtbase#rk3562-aislpc-} -> ${dtbase}.dtb"
  done
}
