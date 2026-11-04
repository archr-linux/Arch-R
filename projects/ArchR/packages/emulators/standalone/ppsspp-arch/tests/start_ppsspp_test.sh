#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for start_ppsspp.sh: the Select+Start "Exit App" mapping, the
# frame skip settings and VerticalSync, run against the RK3326 configs with
# a stub ppsspp and a temporary system.cfg.
#   bash projects/ArchR/packages/emulators/standalone/ppsspp-arch/tests/start_ppsspp_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
FUNCTIONS="${PKG}/../../../archr/profile.d/001-functions"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

mkdir -p "${TMP}/bin" "${TMP}/src/PSP/SYSTEM"
cp "${PKG}/sources/RK3326/ppsspp.ini" "${PKG}/sources/RK3326/controls.ini" "${TMP}/src/PSP/SYSTEM/"
printf '#!/bin/sh\nexit 0\n' >"${TMP}/bin/ppsspp"
chmod +x "${TMP}/bin/ppsspp"
cat >"${TMP}/profile" <<PROFILE
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
PATH="${TMP}/bin:\${PATH}"
PROFILE
# The real script with its fixed paths moved into the scratch folder.
sed -e "s#^\. /etc/profile#. ${TMP}/profile#" \
    -e "s#/usr/config/ppsspp#${TMP}/src#g" \
    -e "s#/storage/.config/ppsspp#${TMP}/conf#g" \
    -e "s#/storage/roms/savestates#${TMP}/states#g" \
    -e "s#^/usr/bin/cheevos_ppsspp.sh#:#" \
    -e "s#@GRENDERER@#0 (OPENGL)#" \
    "${PKG}/scripts/start_ppsspp.sh" >"${TMP}/start.sh"
bash -n "${TMP}/start.sh" || fail "start_ppsspp.sh syntax"
INI="${TMP}/conf/PSP/SYSTEM/ppsspp.ini"
CTL="${TMP}/conf/PSP/SYSTEM/controls.ini"

# run SYSTEM.CFG-LINES...: one start of a game with those settings
run() {
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  bash "${TMP}/start.sh" "/roms/psp/Game.iso" psp >/dev/null 2>&1 || fail "start_ppsspp.sh exited with $?"
}
key() { sed -n "s/^${1} = //p" "$2"; }

# A new install: Exit App from the pad's Select and Start, auto frame skip
# with a cap of 3, vsync on as shipped.
run
expect "exit app added" "10-196:10-197" "$(key 'Exit App' "${CTL}")"
expect "auto frame skip" "True" "$(key AutoFrameSkip "${INI}")"
expect "frame skip cap" "3" "$(key FrameSkip "${INI}")"
expect "vsync as shipped" "True" "$(key VerticalSync "${INI}")"
expect "no old vsync key" "" "$(key VSyncInterval "${INI}")"

# A second start adds no second Exit App; a cap of 0 left behind is fixed.
sed -i 's/^FrameSkip = .*/FrameSkip = 0/' "${INI}"
run
expect "one exit app" "1" "$(grep -c '^Exit App = ' "${CTL}")"
expect "cap 0 fixed" "3" "$(key FrameSkip "${INI}")"

# The user's own Exit App stays.
sed -i 's/^Exit App = .*/Exit App = 10-196:10-193/' "${CTL}"
run
expect "user exit app kept" "10-196:10-193" "$(key 'Exit App' "${CTL}")"

# Skip buffer effects: fixed skip of one frame in two, no auto skip.
run "psp.skip_buffer_effects=1"
expect "sbe auto off" "False" "$(key AutoFrameSkip "${INI}")"
expect "sbe fixed skip" "1" "$(key FrameSkip "${INI}")"
expect "sbe on" "True" "$(key SkipBufferEffects "${INI}")"

# Frame skip off: nothing skipped.
run "psp.auto_frame_skip=0"
expect "no skip auto" "False" "$(key AutoFrameSkip "${INI}")"
expect "no skip" "0" "$(key FrameSkip "${INI}")"

# frame_skip sets the cap.
run "psp.frame_skip=2"
expect "cap set" "2" "$(key FrameSkip "${INI}")"

# vsync off and on; a config from an older package has no VerticalSync.
run "psp.vsync=0"
expect "vsync off" "False" "$(key VerticalSync "${INI}")"
sed -i '/^VerticalSync =/d' "${INI}"
run "psp.vsync=1"
expect "vsync key added" "True" "$(key VerticalSync "${INI}")"
expect "vsync key in Graphics" "VerticalSync = True" \
  "$(sed -n '/^\[Graphics\]/{n;p;}' "${INI}")"
expect "vsync key once" "1" "$(grep -c '^VerticalSync =' "${INI}")"

[ ${FAILED} -eq 0 ] && echo "ok   start_ppsspp.sh"
exit ${FAILED}
