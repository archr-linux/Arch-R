# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 ArchR (standalone - original sourced from packages/addons/)

PKG_NAME="btrfs-progs"
PKG_VERSION="6.14"
PKG_SHA256="5a85b791f0f32a4994e864ac4cb7abccce08e56db3010a1855ad0edeebc70b4c"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL"
PKG_SITE="https://btrfs.readthedocs.io/"
PKG_URL="https://github.com/kdave/btrfs-progs/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Tools for the btrfs filesystem (disabled - not needed for gaming handheld)"
PKG_TOOLCHAIN="manual"
PKG_SECTION="virtual"

# btrfs-progs needs git submodules (libbtrfsutil) not available in GitHub archive tarballs.
# Not essential for R36S gaming handheld - rootfs is ext4, not btrfs.
unpack() { true; }
configure_target() { true; }
make_target() { true; }
makeinstall_target() { true; }
