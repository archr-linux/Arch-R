#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the RetroArch settings path: setsettings.sh writes a key to
# the append config only when system.cfg sets it, never touches the user's
# own values in retroarch.cfg, and passes --set-shader only for a chosen
# shader; archr-retroarch-hotkeys writes once (or forced); and
# archr-retroarch-defaults drops only the old factory values, once.
#   bash projects/ArchR/packages/archr/tests/setsettings_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
SCRIPTS="${PKG}/sources/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

export SETSETTINGS_PROFILE="${TMP}/profile" SETSETTINGS_RETROARCH="${TMP}/ra" \
  SETSETTINGS_ROMS="${TMP}/roms" SETSETTINGS_APPEND="${TMP}/append.cfg" \
  ARCHR_JOYPADS="${TMP}/joypads" ARCHR_INPUT_DEVICES="${TMP}/devices"
cat >"${SETSETTINGS_PROFILE}" <<PROFILE
. "${PKG}/profile.d/001-functions"
J_CONF="${TMP}/system.cfg"
J_CONF_LOCK="${TMP}/system.cfg.lock"
PATH="${SCRIPTS}:\${PATH}"
PROFILE
mkdir -p "${TMP}/ra" "${TMP}/roms/savestates" "${TMP}/joypads"
printf 'I: Bus=0019\nN: Name="odroidgo3-joypad"\nH: Handlers=event2 js0\n' >"${TMP}/devices"
cat >"${TMP}/joypads/odroidgo3-joypad.cfg" <<'PAD'
input_device = "odroidgo3-joypad"
input_select_btn = "12"
input_start_btn = "13"
input_x_btn = "2"
input_y_btn = "3"
input_l_btn = "4"
input_r_btn = "5"
input_l2_btn = "6"
input_r2_btn = "7"
PAD
USER_RA='video_scale_integer = "true"
video_scale_integer_overscale = "true"
aspect_ratio_index = "23"
custom_viewport_y = "12"
video_shader_enable = "true"
input_overlay_enable = "true"
input_player1_a_btn = "1"
config_save_on_exit = "true"'

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
has() { grep -qxF "$1" "$2"; }
run() {
  printf '%s\n' "${USER_RA}" >"${TMP}/ra/retroarch.cfg"
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  bash "${SCRIPTS}/setsettings.sh" gba "/roms/gba/Game (USA).gba" mgba \
    --controllers="" --autosave="" --snapshot="" >"${TMP}/stdout"
}

# The shipped defaults: nothing the launcher exposes reaches RetroArch.
mapfile -t DEFAULTS <"${PKG}/config/system/configs/system.cfg"
run "${DEFAULTS[@]}"
A="${TMP}/append.cfg"
for key in video_scale_integer video_scale_integer_overscale aspect_ratio_index \
           video_smooth video_shader_enable video_shader input_overlay_enable \
           input_overlay fps_show audio_latency video_rotation video_ctx_scaling \
           rewind_enable run_ahead_enabled savestate_auto_index video_filter \
           config_save_on_exit; do
  check "defaults leave ${key} to RetroArch" "! grep -q '^${key} = ' '${A}'"
done
check "no empty value in the append config" "! grep -q '= \"\"' '${A}'"
check "no bogus 'false' key" "! grep -q '^false = ' '${A}'"
check "no --set-shader" "! grep -q -- --set-shader '${TMP}/stdout'"
check "autosave default still applies" "has 'savestate_auto_load = \"true\"' '${A}'"
check "achievements off stays explicit" "has 'cheevos_enable = \"false\"' '${A}'"
while IFS= read -r line; do
  check "retroarch.cfg keeps: ${line}" "has '${line}' '${TMP}/ra/retroarch.cfg'"
done <<<"${USER_RA}"

# What the user chose in the launcher (or system.cfg) is passed on.
run "global.autosave=1" "gba.ratio=3/2" "gba.integerscale=1" "gba.smooth=0" \
    "gba.shaderset=crt/zfast.glslp" "global.audiolatency=64" "gba.rewind=1" \
    "global.retroachievements=0"
check "chosen ratio" "has 'aspect_ratio_index = \"7\"' '${A}'"
check "chosen integer scale" "has 'video_scale_integer = \"1\"' '${A}'"
check "chosen smoothing" "has 'video_smooth = \"0\"' '${A}'"
check "chosen shader" "has 'video_shader = \"crt/zfast.glslp\"' '${A}'"
check "chosen shader on the command line" "grep -q -- '--set-shader /tmp/shaders/crt/zfast.glslp' '${TMP}/stdout'"
check "chosen latency" "has 'audio_latency = \"64\"' '${A}'"
check "chosen rewind" "has 'rewind_enable = \"true\"' '${A}'"
check "overscale still RetroArch's" "! grep -q '^video_scale_integer_overscale' '${A}'"
run "gba.shaderset=none" "gba.overlayset=none"
check "shader none" "has 'video_shader_enable = \"false\"' '${A}' && ! grep -q -- --set-shader '${TMP}/stdout'"
check "overlay none blanks it" "has 'input_overlay = \"\"' '${A}' && has 'input_overlay_enable = \"false\"' '${A}'"

# Hotkeys: once, then RetroArch's own changes stay; --force rewrites.
HK="${SCRIPTS}/archr-retroarch-hotkeys"
R="${TMP}/ra/retroarch.cfg"
rm -f "${TMP}/ra/.archr-hotkeys"
run "system.autohotkeys=1"
check "first game writes the hotkeys" "has 'input_menu_toggle_btn = \"2\"' '${R}' && has 'input_toggle_fast_forward_btn = \"7\"' '${R}'"
check "stamp written" "[ -e '${TMP}/ra/.archr-hotkeys' ]"
sed -i 's/^input_menu_toggle_btn = .*/input_menu_toggle_btn = "9"/' "${R}"
cp "${R}" "${TMP}/saved.cfg"
printf '%s\n' "system.autohotkeys=1" >"${TMP}/system.cfg"
bash "${SCRIPTS}/setsettings.sh" gba x.gba mgba >/dev/null
check "a hotkey changed in RetroArch stays" "has 'input_menu_toggle_btn = \"9\"' '${R}'"
check "player binds are no longer deleted" "has 'input_player1_a_btn = \"1\"' '${R}'"
bash "${HK}" --force "${R}"
check "--force restores the hotkeys" "has 'input_menu_toggle_btn = \"2\"' '${R}'"
check "--force keeps one line per key" "[ \$(grep -c '^input_menu_toggle_btn' '${R}') = 1 ]"
printf '%s\n' "system.autohotkeys=0" >"${TMP}/system.cfg"
sed -i 's/^input_menu_toggle_btn = .*/input_menu_toggle_btn = "9"/' "${R}"
bash "${HK}" --force "${R}"
check "autohotkeys=0 writes nothing" "has 'input_menu_toggle_btn = \"9\"' '${R}'"

# Migration: old factory values go, user values and other keys stay, once.
git -C "${PKG}" show "$(git -C "${PKG}" merge-base HEAD main 2>/dev/null || echo HEAD):./config/system/configs/system.cfg" \
  >"${TMP}/old.cfg" 2>/dev/null || cp "${PKG}/config/system/configs/system.cfg" "${TMP}/old.cfg"
grep -v '^migration\.' "${TMP}/old.cfg" >"${TMP}/system.cfg"
sed -i 's/^snes\.ratio=4\/3$/snes.ratio=16\/9/; s/^gba\.ratio=3\/2$/gba.ratio=3\/2/' "${TMP}/system.cfg"
echo "nes.integerscale=1" >>"${TMP}/system.cfg"
bash "${SCRIPTS}/archr-retroarch-defaults"
C="${TMP}/system.cfg"
check "factory gba ratio removed" "! grep -q '^gba.ratio=' '${C}'"
check "factory bezel removed" "! grep -q '^global.bezel=' '${C}'"
check "factory integerscale removed" "! grep -q '^snes.integerscale=' '${C}'"
check "user ratio kept" "has 'snes.ratio=16/9' '${C}'"
check "user integerscale kept" "has 'nes.integerscale=1' '${C}'"
check "unrelated keys kept" "has 'global.autosave=1' '${C}' && has 'system.hostname=archr' '${C}'"
check "migration marked done" "has 'migration.retroarch_defaults=1' '${C}'"
echo "gba.ratio=3/2" >>"${C}"
bash "${SCRIPTS}/archr-retroarch-defaults"
check "migration runs once" "has 'gba.ratio=3/2' '${C}'"
if [ -s "${TMP}/old.cfg" ] && grep -q '^gba.ratio=3/2' "${TMP}/old.cfg"; then :; else
  echo "FAIL old defaults not found"; FAILED=1; fi

exit "${FAILED}"
