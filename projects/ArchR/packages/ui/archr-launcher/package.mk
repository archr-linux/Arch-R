# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="archr-launcher"
# Needs the systems catalog at /usr/share/archr, the archr-launcher app_id
# and the session's locale handling. Publish this commit (or bump to the
# final upstream revision); use ARCHR_LAUNCHER_SOURCE_DIR until then.
PKG_VERSION="4d4a935858e4df8b6932defd19a5085fbcb025ec"
PKG_ARCH="aarch64"
# Bundled fonts retain their separate OFL licenses.
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/archr-linux/archr-launcher"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain SDL2 SDL2_image SDL2_ttf SDL2_mixer cargo:host rust:host"
PKG_LONGDESC="ArchR's game launcher and its UI session (SDL2, under sway)"
# Devices updated with pacman get the launcher in place of the old UI.
PKG_REPLACES="emulationstation es-theme-art-book-next"
PKG_TOOLCHAIN="manual"

# Native scripts/get + scripts/extract support file:// source directories.
# Copy a development snapshot, not build output or repository metadata. Include
# source inputs in the unpack stamp so edits trigger a fresh local snapshot.
if [ -n "${ARCHR_LAUNCHER_SOURCE_DIR}" ]; then
  case "${ARCHR_LAUNCHER_SOURCE_DIR}" in
    /*) ;;
    *) die "ARCHR_LAUNCHER_SOURCE_DIR must be an absolute directory" ;;
  esac
  [ -f "${ARCHR_LAUNCHER_SOURCE_DIR}/Cargo.toml" ] || die "Invalid launcher source directory"
  PKG_URL="file://${ARCHR_LAUNCHER_SOURCE_DIR}"
  PKG_TAR_COPY_OPTS="--exclude=./.git --exclude=./.svn --exclude=./target --exclude=./.superpowers --exclude=./.serena --exclude=./supertool"
  PKG_NEED_UNPACK+=" ${ARCHR_LAUNCHER_SOURCE_DIR}/LICENSE ${ARCHR_LAUNCHER_SOURCE_DIR}/Cargo.toml ${ARCHR_LAUNCHER_SOURCE_DIR}/Cargo.lock ${ARCHR_LAUNCHER_SOURCE_DIR}/crates ${ARCHR_LAUNCHER_SOURCE_DIR}/session ${ARCHR_LAUNCHER_SOURCE_DIR}/themes ${ARCHR_LAUNCHER_SOURCE_DIR}/locales"
elif [ "${0##*/}" = "get" ] && \
     [ ! -f "${SOURCES}/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.gz.sha256" ] && \
     ! wget -q --spider --timeout=30 --tries=2 "${PKG_URL}" >/dev/null 2>&1; then
  # Checked only when scripts/get is about to download, once: an unpublished
  # revision otherwise ends in ten wget rounds and "Try later!".
  die "archr-launcher: cannot download ${PKG_URL}
The pinned revision is not published at ${PKG_SITE} (or the network is down).
Publish it, or build from a local checkout:
  ARCHR_LAUNCHER_SOURCE_DIR=/abs/path/to/archr-launcher
For docker builds that path must also be visible in the container, e.g.
  DOCKER_EXTRA_OPTS=\"-v /abs/path/to/archr-launcher:/abs/path/to/archr-launcher\""
fi

make_target() {
  # config/functions supplies CARGO_HOME, CARGO_TARGET_DIR, RUST_TARGET_PATH
  # and the toolchain's cargo/rustc + target linker, as for touchhle-sa.
  cargo build --locked --release --target "${TARGET_NAME}" \
    --manifest-path "${PKG_BUILD}/Cargo.toml" --package archr-launcher
}

makeinstall_target() {
  install -Dm644 "${PKG_BUILD}/LICENSE" "${INSTALL}/usr/share/licenses/archr-launcher/LICENSE"
  install -Dm755 "${PKG_BUILD}/.${TARGET_NAME}/target/${TARGET_NAME}/release/archr-launcher" \
    "${INSTALL}/usr/bin/archr-launcher"
  install -Dm755 "${PKG_BUILD}/session/archr-launcher-session" \
    "${INSTALL}/usr/bin/archr-launcher-session"
  install -Dm644 "${PKG_BUILD}/session/archr-launcher-session.service" \
    "${INSTALL}/usr/lib/systemd/system/archr-launcher-session.service"
  mkdir -p "${INSTALL}/usr/share/archr-launcher/themes" \
    "${INSTALL}/usr/share/archr-launcher/locales"
  cp -a "${PKG_BUILD}/themes/default" "${INSTALL}/usr/share/archr-launcher/themes/"
  install -m644 "${PKG_BUILD}"/locales/*.toml "${INSTALL}/usr/share/archr-launcher/locales/"

  # Not enabled: autostart starts it through UI_SERVICE (090-ui_service).
}
