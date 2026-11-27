# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="archr-launcher"
PKG_VERSION="66dc2ec7e64195ef1714c03f13a80cbdb62e2ca0"
PKG_SHA256="59df932b7484567ef3ac6baf500c4ad814833617a21ec0bd53431a2de9ef7e23"
PKG_ARCH="aarch64"
# Bundled fonts retain their separate OFL licenses.
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/archr-linux/archr-launcher"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain SDL2 SDL2_image SDL2_ttf SDL2_mixer cargo:host rust:host archr-gamma"
# Settings › Sound and display › Picture; the session unit wants it.
PKG_PACMAN_DEPENDS="archr-gamma"
PKG_LONGDESC="ArchR's game launcher, its UI session (SDL2, under sway) and the volume/brightness OSD"
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
  PKG_SHA256=""
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
  # The ScreenScraper developer login reaches option_env! in archr-scraper
  # only through the inherited environment; never echo its value.
  # Without it "Sign in" can never work, and nothing on the console says
  # why: refuse to build unless that is asked for (ARCHR_NO_SCRAPER_LOGIN=1,
  # a development build that will not reach a console).
  if [ -n "${SCREENSCRAPER_DEV_LOGIN}" ]; then
    export SCREENSCRAPER_DEV_LOGIN
  elif [ "${ARCHR_NO_SCRAPER_LOGIN}" = "1" ]; then
    echo "WARNING: SCREENSCRAPER_DEV_LOGIN not set: scraper built without a developer login"
  else
    die "SCREENSCRAPER_DEV_LOGIN is not set: the ScreenScraper sign-in would not work. Export it (see ~/.archr/credentials.env), or set ARCHR_NO_SCRAPER_LOGIN=1 for a development build"
  fi
  cargo build --locked --release --target "${TARGET_NAME}" \
    --manifest-path "${PKG_BUILD}/Cargo.toml" --package archr-launcher --package archr-osd
}

makeinstall_target() {
  install -Dm644 "${PKG_BUILD}/LICENSE" "${INSTALL}/usr/share/licenses/archr-launcher/LICENSE"
  install -Dm755 "${PKG_BUILD}/.${TARGET_NAME}/target/${TARGET_NAME}/release/archr-launcher" \
    "${INSTALL}/usr/bin/archr-launcher"
  # Started by the sway kiosk config; input_sense sends it the levels.
  install -Dm755 "${PKG_BUILD}/.${TARGET_NAME}/target/${TARGET_NAME}/release/archr-osd" \
    "${INSTALL}/usr/bin/archr-osd"
  install -Dm755 "${PKG_BUILD}/session/archr-launcher-session" \
    "${INSTALL}/usr/bin/archr-launcher-session"
  install -Dm644 "${PKG_BUILD}/session/archr-launcher-session.service" \
    "${INSTALL}/usr/lib/systemd/system/archr-launcher-session.service"
  mkdir -p "${INSTALL}/usr/share/archr-launcher/themes" \
    "${INSTALL}/usr/share/archr-launcher/locales"
  # The default theme, and Ellegance (the reference theme of the 3.1 theme
  # API) for users to pick in Appearance; other folders are examples.
  for theme in default ellegance; do
    cp -a "${PKG_BUILD}/themes/${theme}" "${INSTALL}/usr/share/archr-launcher/themes/"
  done
  install -m644 "${PKG_BUILD}"/locales/*.toml "${INSTALL}/usr/share/archr-launcher/locales/"

  # Not enabled: autostart starts it through UI_SERVICE (090-ui_service).
}
