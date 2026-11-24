# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="pacman"
PKG_VERSION="7.0.0"
PKG_SHA256="ef08f258cb3e0885c5884ad43fb6cff0e9c327ed33024d79d03555f99c583744"
# 2: pacman-init loads the ArchR key by the key itself and retries next boot without it.
PKG_REV="2"
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
  # Each SoC family has its own repo tags (archr-update keeps this line
  # in step with the channel); RK3326 keeps the bare tag.
  case ${DEVICE} in
    RK3562) sed -i 's|/repo-stable$|/repo-stable-rk3562|' ${INSTALL}/etc/pacman.d/mirrorlist ;;
  esac
  cp ${PKG_DIR}/config/makepkg.conf ${INSTALL}/etc/makepkg.conf

  # /var/lib/pacman is a symlink directly into the rw storage overlay.
  # Earlier versions did `mkdir -p /var/lib/pacman` here and then
  # `ln -sf /storage/.pacman/db /var/lib/pacman` in post_install, but
  # `ln -sf TARGET LINK` when LINK is an existing directory creates
  # LINK/$(basename TARGET) instead of replacing LINK — so we ended up
  # with /var/lib/pacman/db as a symlink (correct destination) inside
  # an empty real /var/lib/pacman directory in the read-only rootfs,
  # while pacman went looking for /var/lib/pacman/local and
  # /var/lib/pacman/sync and reported "could not find or read directory".
  mkdir -p ${INSTALL}/var/lib
  ln -sf /storage/.pacman/db ${INSTALL}/var/lib/pacman

  # /var/cache/pacman keeps the package cache. Same shape as above.
  mkdir -p ${INSTALL}/var/cache/pacman
  ln -sf /storage/.pacman/cache ${INSTALL}/var/cache/pacman/pkg

  mkdir -p ${INSTALL}/var/log

  # Remove unnecessary files
  rm -rf ${INSTALL}/usr/share/locale
  rm -rf ${INSTALL}/usr/share/doc
  rm -rf ${INSTALL}/usr/share/man

  # Install pacman-init script
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/pacman-init ${INSTALL}/usr/bin/pacman-init
  chmod +x ${INSTALL}/usr/bin/pacman-init

  # Pacman ships several bash scripts (pacman-key, makepkg, vercmp, etc.)
  # whose shebang is built against the upstream sbindir which on Arch
  # is /usr/sbin (with /usr/sbin -> /usr/bin via usrmerge). LibreELEC
  # does not merge usr/sbin, so /usr/sbin/bash does not exist and every
  # one of these scripts dies with "bad interpreter: No such file or
  # directory". Rewrite the shebangs to /usr/bin/bash where bash
  # actually lives in our rootfs.
  find ${INSTALL}/usr -type f -exec \
    sed -i '1s|^#!/usr/sbin/bash$|#!/usr/bin/bash|' {} +
}

post_install() {
  enable_service pacman-init.service
}
