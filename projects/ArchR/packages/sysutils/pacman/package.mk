# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="pacman"
PKG_VERSION="7.0.0"
PKG_SHA256="ef08f258cb3e0885c5884ad43fb6cff0e9c327ed33024d79d03555f99c583744"
PKG_LICENSE="GPL"
PKG_SITE="https://archlinux.org/pacman/"
PKG_URL="https://gitlab.archlinux.org/pacman/pacman/-/archive/v${PKG_VERSION}/pacman-v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain libarchive curl gpgme openssl bash archr-keyring"
PKG_LONGDESC="A library-based package manager with dependency support."
PKG_TOOLCHAIN="meson"

PKG_MESON_OPTS_TARGET="-Ddoc=disabled \
                       -Ddoxygen=disabled \
                       -Di18n=false \
                       -Dscriptlet-shell=/usr/bin/bash \
                       -Dldconfig=/usr/bin/ldconfig \
                       -Dbuildscript=PKGBUILD \
                       -Dpkg-ext=.pkg.tar.zst \
                       -Dsrc-ext=.src.tar.gz"

pre_configure_target() {
  # Ensure pkg-config finds dependencies in sysroot
  export PKG_CONFIG_PATH="${SYSROOT_PREFIX}/usr/lib/pkgconfig:${SYSROOT_PREFIX}/usr/share/pkgconfig"

  # gpgme-config and libassuan-config need to point to sysroot
  export GPGME_CONFIG="${SYSROOT_PREFIX}/usr/bin/gpgme-config"
  export LIBASSUAN_CONFIG="${SYSROOT_PREFIX}/usr/bin/libassuan-config"
}

post_makeinstall_target() {
  # Install ArchR pacman configuration
  mkdir -p ${INSTALL}/etc/pacman.d
  cp ${PKG_DIR}/config/pacman.conf ${INSTALL}/etc/pacman.conf
  cp ${PKG_DIR}/config/mirrorlist ${INSTALL}/etc/pacman.d/mirrorlist
  cp ${PKG_DIR}/config/makepkg.conf ${INSTALL}/etc/makepkg.conf

  # Create pacman state directories (symlinked to /storage at runtime)
  mkdir -p ${INSTALL}/var/lib/pacman
  mkdir -p ${INSTALL}/var/cache/pacman/pkg
  mkdir -p ${INSTALL}/var/log

  # Remove unnecessary files
  rm -rf ${INSTALL}/usr/share/locale
  rm -rf ${INSTALL}/usr/share/doc
  rm -rf ${INSTALL}/usr/share/man

  # Install pacman-init script
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/pacman-init ${INSTALL}/usr/bin/pacman-init
  chmod +x ${INSTALL}/usr/bin/pacman-init
}

post_install() {
  enable_service pacman-init.service

  # Create /storage symlinks for pacman mutable state
  mkdir -p ${INSTALL}/var/lib
  ln -sf /storage/.pacman/db ${INSTALL}/var/lib/pacman
  mkdir -p ${INSTALL}/var/cache/pacman
  ln -sf /storage/.pacman/cache ${INSTALL}/var/cache/pacman/pkg
}
