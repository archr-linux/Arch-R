#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for start_ppsspp.sh: the Select+Start "Exit App" mapping, the
# settings it writes to ppsspp.ini (only those set in system.cfg; the rest
# stays as the player left it in PPSSPP), run against the RK3326 configs
# with a stub ppsspp and a temporary system.cfg.
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
    -e "s#/sys/module/panfrost#${TMP}/panfrost#g" \
    "${PKG}/scripts/start_ppsspp.sh" >"${TMP}/start.sh"
bash -n "${TMP}/start.sh" || fail "start_ppsspp.sh syntax"
INI="${TMP}/conf/PSP/SYSTEM/ppsspp.ini"
CTL="${TMP}/conf/PSP/SYSTEM/controls.ini"

# run SYSTEM.CFG-LINES...: one start of a game with those settings
run() {
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  bash "${TMP}/start.sh" "/roms/psp/${GAMEFILE:-Game.iso}" psp >/dev/null 2>&1 || fail "start_ppsspp.sh exited with $?"
}
key() { sed -n "s/^${1} = //p" "$2"; }
ini() { sed -i "s/^${1} = .*/${1} = ${2}/" "${INI}"; }

# A new install: Exit App from the pad's Select and Start, the shipped
# auto frame skip with a cap of 2, vsync on.
run
expect "exit app added" "10-196:10-197" "$(key 'Exit App' "${CTL}")"
expect "auto frame skip" "True" "$(key AutoFrameSkip "${INI}")"
expect "frame skip cap" "2" "$(key FrameSkip "${INI}")"
expect "vsync as shipped" "True" "$(key VerticalSync "${INI}")"
expect "no old vsync key" "" "$(key VSyncInterval "${INI}")"

# A second start adds no second Exit App; the user's own Exit App stays.
run
expect "one exit app" "1" "$(grep -c '^Exit App = ' "${CTL}")"
sed -i 's/^Exit App = .*/Exit App = 10-196:10-193/' "${CTL}"
run
expect "user exit app kept" "10-196:10-193" "$(key 'Exit App' "${CTL}")"

# What the player set in PPSSPP stays while system.cfg sets nothing.
ini AutoFrameSkip False; ini FrameSkip 5; ini SkipBufferEffects False
ini InternalResolution 3; ini iShowStatusFlags 2; ini CPUSpeed 333
run
expect "player auto skip kept" "False" "$(key AutoFrameSkip "${INI}")"
expect "player frame skip kept" "5" "$(key FrameSkip "${INI}")"
expect "player buffer effects kept" "False" "$(key SkipBufferEffects "${INI}")"
expect "player resolution kept" "3" "$(key InternalResolution "${INI}")"
expect "player fps kept" "2" "$(key iShowStatusFlags "${INI}")"
expect "player clock kept" "333" "$(key CPUSpeed "${INI}")"

# Each setting, when set, is written.
run "psp.internal_resolution=2" "psp.show_fps=0" "psp.clock_speed=222"
expect "resolution set" "2" "$(key InternalResolution "${INI}")"
expect "fps off set" "0" "$(key iShowStatusFlags "${INI}")"
expect "clock set" "222" "$(key CPUSpeed "${INI}")"

# Skip buffer effects: a fixed skip, 2 unless frame_skip says otherwise.
run "psp.skip_buffer_effects=1"
expect "sbe auto off" "False" "$(key AutoFrameSkip "${INI}")"
expect "sbe fixed skip" "2" "$(key FrameSkip "${INI}")"
expect "sbe on" "True" "$(key SkipBufferEffects "${INI}")"
run "psp.skip_buffer_effects=1" "psp.frame_skip=1"
expect "sbe own skip" "1" "$(key FrameSkip "${INI}")"

# Frame skip off: nothing skipped.
run "psp.auto_frame_skip=0"
expect "no skip auto" "False" "$(key AutoFrameSkip "${INI}")"
expect "no skip" "0" "$(key FrameSkip "${INI}")"

# frame_skip sets the cap; auto skip with a cap of 0 would skip nothing.
run "psp.frame_skip=4"
expect "cap set" "4" "$(key FrameSkip "${INI}")"
run "psp.auto_frame_skip=1" "psp.frame_skip=0"
expect "auto on" "True" "$(key AutoFrameSkip "${INI}")"
expect "cap 0 fixed" "2" "$(key FrameSkip "${INI}")"

# Renderer: Vulkan only while panfrost drives the GPU, set here or in PPSSPP.
run "psp.graphics_backend=vulkan"
expect "vulkan without panfrost" "0 (OPENGL)" "$(key GraphicsBackend "${INI}")"
mkdir -p "${TMP}/panfrost"
run "psp.graphics_backend=vulkan"
expect "vulkan with panfrost" "3 (VULKAN)" "$(key GraphicsBackend "${INI}")"
rmdir "${TMP}/panfrost"
run
expect "player vulkan without panfrost" "0 (OPENGL)" "$(key GraphicsBackend "${INI}")"

# God of War skips buffer effects unless a setting says otherwise: 7-8 fps
# with them on the R36S, 17-19 without (its cutscenes go black).
GOW="God of War - Chains of Olympus (USA).iso"
ini SkipBufferEffects False
GAMEFILE="${GOW}" run "psp.vsync=1"
expect "gow skips buffer effects" "True" "$(key SkipBufferEffects "${INI}")"
expect "gow fixed skip" "2" "$(key FrameSkip "${INI}")"
GAMEFILE="${GOW}" run "psp[\"${GOW}\"].skip_buffer_effects=0"
expect "gow game setting wins" "False" "$(key SkipBufferEffects "${INI}")"
ini SkipBufferEffects True
GAMEFILE="${GOW}" run "psp.skip_buffer_effects=0"
expect "gow platform setting wins" "False" "$(key SkipBufferEffects "${INI}")"

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
