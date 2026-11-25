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
trap '[ -n "${KEEP:-}" ] || rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

mkdir -p "${TMP}/bin" "${TMP}/src/PSP/SYSTEM"
# An SDL with Vulkan, as the image ships it.
printf 'stuff VK_KHR_wayland_surface stuff' >"${TMP}/libSDL2.so"
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
    -e "s#/usr/lib/libSDL2-2.0.so.0#${TMP}/libSDL2.so#g" \
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
expect "new install: high quality depth" "True" "$(key HighQualityDepth "${INI}")"
expect "new install: backoff cache" "False" "$(key TextureBackoffCache "${INI}")"

# A config from before 20261119.6 (the values we shipped then; one the
# player changed in PPSSPP): back to PPSSPP's defaults once, except the
# player's own.
rm -f "${TMP}/conf/.defaults-20261119"
ini HighQualityDepth False
ini TextureBackoffCache True
ini RenderDuplicateFrames True
ini SkipGPUReadbackMode 2
run
expect "old depth back to default" "True" "$(key HighQualityDepth "${INI}")"
expect "old backoff back to default" "False" "$(key TextureBackoffCache "${INI}")"
expect "old duplicate frames back to default" "False" "$(key RenderDuplicateFrames "${INI}")"
expect "the player's own readback mode stays" "2" "$(key SkipGPUReadbackMode "${INI}")"
# Only once: what the player sets afterwards stays.
ini TextureBackoffCache True
run
expect "migration runs once" "True" "$(key TextureBackoffCache "${INI}")"

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
# A start that died before its 10th frame leaves PPSSPP's mark on Vulkan,
# and the next start falls back to OpenGL on its own. Vulkan set in
# system.cfg clears the mark; without a setting, PPSSPP's fallback stays.
FAILED_MARK="${TMP}/conf/PSP/SYSTEM/FailedGraphicsBackends.txt"
printf 'VULKAN' >"${FAILED_MARK}"
run "psp.graphics_backend=vulkan"
expect "vulkan set clears the mark" "no" "$([ -e "${FAILED_MARK}" ] && echo yes || echo no)"
printf 'VULKAN' >"${FAILED_MARK}"
run
expect "mark kept without a setting" "yes" "$([ -e "${FAILED_MARK}" ] && echo yes || echo no)"
printf 'VULKAN' >"${FAILED_MARK}"
run "psp.graphics_backend=opengl"
expect "mark kept with opengl set" "yes" "$([ -e "${FAILED_MARK}" ] && echo yes || echo no)"
rm -f "${FAILED_MARK}"
# Panfrost but an SDL without Vulkan: OpenGL, not an abort.
printf 'no vulkan here' >"${TMP}/libSDL2.so"
run "psp.graphics_backend=vulkan"
expect "vulkan without it in SDL" "0 (OPENGL)" "$(key GraphicsBackend "${INI}")"
printf 'stuff VK_KHR_wayland_surface stuff' >"${TMP}/libSDL2.so"
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

# Upscaler: FSR first in PPSSPP's post shader chain, the player's own
# shaders after it; off takes FSR out and leaves them. Nothing set, the
# chain is the player's; none by default.
chain() { sed -n '/^\[PostShaderList\]/,/^\[/{s/^PostShader[0-9]* = //p}' "${INI}" | tr '\n' ' '; }
expect "no upscaler by default" "" "$(chain)"
run "psp.upscaler=fsr"
expect "fsr set" "FSR-EASU FSR-RCAS " "$(chain)"
expect "one chain section" "1" "$(grep -c '^\[PostShaderList\]' "${INI}")"
expect "graphics key untouched" "Off" "$(key PostShader "${INI}")"
sed -i '/^PostShader2 = /a PostShader3 = Vignette' "${INI}"
run "psp.upscaler=fsr"
expect "fsr again, own shader kept" "FSR-EASU FSR-RCAS Vignette " "$(chain)"
run
expect "no setting: chain kept" "FSR-EASU FSR-RCAS Vignette " "$(chain)"
run "psp.upscaler=off"
expect "fsr off, own shader kept" "Vignette " "$(chain)"
run "psp[\"Game.iso\"].upscaler=fsr"
expect "fsr per game" "FSR-EASU FSR-RCAS Vignette " "$(chain)"
run "psp.upscaler=off"
sed -i '/^PostShader1 = Vignette/d' "${INI}"
run "psp.upscaler=easu"
expect "easu alone" "FSR-EASU " "$(chain)"
run "psp.upscaler=off"
expect "off again" "" "$(chain)"

# NPU upscale (npu-upscale, RK3562 only). No helper, or a helper that says
# unsupported (every other device): PPSSPP starts as before, ppsspp.ini as is.
printf '#!/bin/sh\necho "$*" >"%s/ppsspp.args"\n' "${TMP}" >"${TMP}/bin/ppsspp"
run
expect "no helper: ppsspp as before" "--pause-menu-exit /roms/psp/Game.iso" "$(cat "${TMP}/ppsspp.args")"
NPU="${PKG}/../../../graphics/npu-upscale/sources/npu-upscale"
mkdir -p "${TMP}/npu"
touch "${TMP}/npu/lib.so" "${TMP}/npu/rt.so" "${TMP}/npu/espcn_x2_480x272.rknn"
sed -e "s#^RESTORE=.*#RESTORE=${TMP}/npu.restore#" \
    -e "s#^MODELS=.*#MODELS=${TMP}/npu#" -e "s#^LIB=.*#LIB=${TMP}/npu/lib.so#" -e "s#^RT=.*#RT=${TMP}/npu/rt.so#" \
    -e 's#^supported() {#supported() { [ -e "'"${TMP}"'/npu.ok" ]; return; #' \
    -e 's#^down() {#down() { echo down >>"'"${TMP}"'/npu.log"; return; #' \
    -e 's#^up() {#up() { return 0; #' \
    -e 's#^    exec "\$@"#    echo "exec ${DARKOS_NPU_SR:-none}" >>"'"${TMP}"'/npu.log"; exec "$@"#' \
    "${NPU}" >"${TMP}/bin/npu-upscale"
chmod +x "${TMP}/bin/npu-upscale"
cp "${INI}" "${TMP}/ini.before"
run
expect "unsupported: ppsspp as before" "--pause-menu-exit /roms/psp/Game.iso" "$(cat "${TMP}/ppsspp.args")"
expect "unsupported: no NPU" "" "$(cat "${TMP}/npu.log" 2>/dev/null)"
cmp -s "${INI}" "${TMP}/ini.before" || fail "unsupported: ppsspp.ini changed"
touch "${TMP}/npu.ok"
# auto: a 1x render without skipping buffer effects is upscaled x2, and
# PPSSPP's display keys come back after the game.
ini InternalResolution 1
ini SkipBufferEffects False
cp "${INI}" "${TMP}/ini.before"
run
expect "auto 1x: x2 through the NPU" "exec x2:480x272 down" "$(tr '\n' ' ' <"${TMP}/npu.log" | sed 's/ $//')"
# A config from before 1.20 has no [DisplayLayout.Landscape]: it comes back
# with PPSSPP's own values; everything else as it was.
sect() { sed -n "/^\[${1}\]/,/^\[/{/^\[/!p}" "$2"; }
expect "auto 1x: layout back to PPSSPP's defaults" "BufferFiltering = 1|DisplayStretch = False|DisplayIntegerScale = False|DisplayScale = 1.000000|DisplayOffsetX = 0.500000|DisplayOffsetY = 0.500000|DisplayAspectRatio = 1.000000" \
  "$(sect DisplayLayout.Landscape "${INI}" | tr '\n' '|' | sed 's/|$//')"
sed '/^\[DisplayLayout.Landscape\]/,$d' "${INI}" | cmp -s - "${TMP}/ini.before" || fail "auto 1x: ppsspp.ini not put back"
# auto with skip buffer effects (God of War): no NPU
rm -f "${TMP}/npu.log"
GAMEFILE="God of War.iso" run
expect "auto, skip buffer effects: no NPU" "" "$(cat "${TMP}/npu.log" 2>/dev/null)"
# auto with a post shader (FSR): no NPU
run "psp.upscaler=fsr"
expect "auto with FSR: no NPU" "" "$(cat "${TMP}/npu.log" 2>/dev/null)"
run "psp.upscaler=off"
rm -f "${TMP}/npu.log"
# off, and x2 forced on a 2x render with skip buffer effects
ini InternalResolution 2
run "psp.npu_upscale=off"
expect "off: no NPU" "" "$(cat "${TMP}/npu.log" 2>/dev/null)"
ini SkipBufferEffects True
cp "${INI}" "${TMP}/ini.before"
run "psp.npu_upscale=x2"
expect "x2 forced" "exec x2:480x272 down" "$(tr '\n' ' ' <"${TMP}/npu.log" | sed 's/ $//')"
cmp -s "${INI}" "${TMP}/ini.before" || fail "x2 forced: ppsspp.ini not put back"

[ ${FAILED} -eq 0 ] && echo "ok   start_ppsspp.sh"
exit ${FAILED}
