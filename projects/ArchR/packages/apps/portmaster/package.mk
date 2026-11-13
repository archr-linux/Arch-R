# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="portmaster"
PKG_VERSION="2026.04.01-1426"
PKG_REV="7"
PKG_ARCH="arm aarch64"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/PortsMaster/PortMaster-GUI"
PKG_URL="https://github.com/PortsMaster/PortMaster-GUI/releases/download/${PKG_VERSION}/PortMaster.zip"
PKG_DEPENDS_TARGET="toolchain archr-hotkey gamecontrollerdb oga_controls control-gen xmlstarlet list-guid gst-plugins-base Python3 xz portmaster-compat-libs lib32-openssl11"
PKG_LONGDESC="Portmaster - a simple tool that allows you to download various game ports"
PKG_TOOLCHAIN="manual"
# Consoles updated with pacman get the 32-bit libssl 1.1 too.
PKG_PACMAN_DEPENDS="lib32-openssl11"

COMPAT_URL="https://github.com/archr-linux/packages/raw/main/compat.zip"

makeinstall_target() {
  export STRIP=true

  mkdir -p ${INSTALL}/usr/config/PortMaster
    cp -a ${PKG_DIR}/sources/* ${INSTALL}/usr/config/PortMaster

  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_DIR}/scripts/* ${INSTALL}/usr/bin

  # Ports the launcher offers to run with panfrost (see the file).
  mkdir -p ${INSTALL}/usr/share/archr/portmaster
    cp -a ${PKG_DIR}/share/panfrost.txt ${INSTALL}/usr/share/archr/portmaster

  mkdir -p ${INSTALL}/usr/config/PortMaster/release
    curl -Lo ${INSTALL}/usr/config/PortMaster/release/PortMaster.zip ${PKG_URL}

  mkdir -p ${INSTALL}/usr/lib/compat
    curl -Lo ${PKG_BUILD}/compat.zip ${COMPAT_URL}
    unzip -qq ${PKG_BUILD}/compat.zip -d ${INSTALL}/usr/lib/compat

    # libcodec2.so.0.9, libx264.so.160 e libx265.so.192 (SONAMEs do
    # Debian 11 listados no PortMaster_CFW.md) sao instaladas como
    # arquivos reais pelo pacote portmaster-compat-libs (dependencia).
}
