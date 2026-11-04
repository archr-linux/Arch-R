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
  SETSETTINGS_ROMS="${TMP}/roms" SETSETTINGS_APPEND="${TMP}/append.cfg" SETSETTINGS_REMAPS="${TMP}/remaps" \
  SETSETTINGS_RUN_REMAPS="${TMP}/run-remaps" \
  ARCHR_JOYPADS="${TMP}/joypads" ARCHR_INPUT_DEVICES="${TMP}/devices"
cat >"${SETSETTINGS_PROFILE}" <<PROFILE
. "${PKG}/profile.d/001-functions"
J_CONF="${TMP}/system.cfg"
J_CONF_LOCK="${TMP}/system.cfg.lock"
PATH="${SCRIPTS}:\${PATH}"
PROFILE
mkdir -p "${TMP}/ra" "${TMP}/roms/savestates" "${TMP}/joypads"
# A USB pad took js0; the built-in one sits on the host bus.
printf '%s\n' 'I: Bus=0003 Vendor=045e' 'N: Name="Xbox Wireless Controller"' 'H: Handlers=event5 js0' '' \
  'I: Bus=0019 Vendor=1234' 'N: Name="odroidgo3-joypad"' 'H: Handlers=event2 js1' >"${TMP}/devices"
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
input_overlay_opacity = "0.5"
input_player1_a_btn = "1"
config_save_on_exit = "true"'

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
# shellcheck disable=SC2317 # called through eval in check
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
check "awaiting a decision: analog d-pad, menu driver, savestate folder stay" \
  "has 'input_player1_analog_dpad_mode = \"1\"' '${A}' && has 'menu_driver = \"ozone\"' '${A}' && grep -q '^savestate_directory = ' '${A}'"
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
check "only the whole key leaves retroarch.cfg" "has 'input_overlay_opacity = \"0.5\"' '${TMP}/ra/retroarch.cfg'"
check "no sed scripts left behind" "! ls '${TMP}'/append.cfg.sed* >/dev/null 2>&1"

# PlayStation: the cores start as a digital pad and RetroArch reads the
# device type only from a remap, so a core remap plugs in a DualShock (the
# id differs per core), once; the stick stays a stick, not a d-pad.
RM="${SETSETTINGS_REMAPS}"
psx() {
  printf '%s\n' "${USER_RA}" >"${TMP}/ra/retroarch.cfg"
  : >"${TMP}/system.cfg"
  bash "${SCRIPTS}/setsettings.sh" psx "/roms/psx/Ape Escape (USA).chd" "$1" \
    --controllers=" -p1index 0 -p1guid abc " --autosave="" --snapshot="" >"${TMP}/stdout"
}
P="${RM}/PCSX-ReARMed/PCSX-ReARMed.rmp"
for core in pcsx_rearmed32 pcsx_rearmed; do
  rm -rf "${RM}"
  psx "${core}"
  check "${core}: DualShock on port 1 to 5" \
    "[ \$(grep -c '^input_libretro_device_p[1-5] = \"517\"$' '${P}') = 5 ]"
  check "${core}: stick is not a d-pad" "has 'input_player1_analog_dpad_mode = \"0\"' '${A}'"
  check "${core}: nothing dead in the append config" "! grep -q '^input_libretro_device_p' '${A}'"
done
check "no temporary file left" "[ ! -e '${P}.tmp' ]"
rm -rf "${RM}"; mkdir -p "${P%/*}"; echo 'input_libretro_device_p1 = "5' >"${P}.tmp"
psx pcsx_rearmed32
check "a stale partial write is replaced" \
  "[ \$(grep -c '^input_libretro_device_p[1-5] = \"517\"$' '${P}') = 5 ] && [ ! -e '${P}.tmp' ]"
printf '%s\n' 'input_libretro_device_p1 = "1"' 'input_player1_btn_b = "8"' >"${P}"
psx pcsx_rearmed32
check "a remap the user saved stays" "has 'input_player1_btn_b = \"8\"' '${P}' && has 'input_libretro_device_p1 = \"1\"' '${P}'"
psx swanstation
check "swanstation: its own DualShock id" \
  "[ \$(grep -c '^input_libretro_device_p[1-5] = \"261\"$' '${RM}/SwanStation/SwanStation.rmp') = 5 ]"
rm -rf "${RM}"
run
check "other systems get no remap" "[ ! -e '${RM}' ]"

# The same remap path for the other devices the append config used to set.
game() { # PLATFORM CORE [system.cfg lines...]
  local platform="$1" core="$2"
  shift 2
  printf '%s\n' "${USER_RA}" >"${TMP}/ra/retroarch.cfg"
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  bash "${SCRIPTS}/setsettings.sh" "${platform}" "/roms/${platform}/Game.bin" "${core}" \
    --controllers=" -p1index 0 -p1guid abc " --autosave="" --snapshot="" >"${TMP}/stdout" 2>/dev/null # atari800 options live under /storage
}
rm -rf "${RM}"
game atari5200 atari800
check "atari800: 5200 joystick on its 4 ports" \
  "[ \$(grep -c '^input_libretro_device_p[1-4] = \"769\"$' '${RM}/Atari800/Atari800.rmp') = 4 ]"
check "atari5200: nothing dead in the append config" "! grep -q '^input_libretro_device_p' '${A}'"
rm -rf "${RM}"
game atari5200 a5200
check "a5200 keeps its own pad" "[ ! -e '${RM}' ]"

# Netplay host only: a multitap for this run, from a copy of the user's
# remaps in a run folder; the user's folder is left as it was.
RR="${SETSETTINGS_RUN_REMAPS}"
rm -rf "${RM}" "${RR}"
mkdir -p "${RM}/Snes9x"
echo 'input_player1_btn_b = "8"' >"${RM}/Snes9x/Game.rmp"
game snes snes9x
check "snes9x without netplay: no run remaps" "[ ! -e '${RR}' ] && ! grep -q '^input_remapping_directory' '${A}'"
game snes snes9x global.netplay=1 global.netplay.mode=host
check "snes9x host: multitap on port 2 for this run" \
  "has 'input_libretro_device_p2 = \"257\"' '${RR}/Snes9x/Snes9x.rmp'"
check "snes9x host: RetroArch reads the run folder" "has 'input_remapping_directory = \"${RR}\"' '${A}'"
check "snes9x host: the user's game remap is in the run folder" "has 'input_player1_btn_b = \"8\"' '${RR}/Snes9x/Game.rmp'"
check "snes9x host: nothing written to the user's remaps" "[ ! -e '${RM}/Snes9x/Snes9x.rmp' ]"
game megadrive genesis_plus_gx global.netplay=1 global.netplay.mode=host
check "genesis_plus_gx host: 4-Way Play on port 2" \
  "has 'input_libretro_device_p2 = \"1025\"' '${RR}/Genesis Plus GX/Genesis Plus GX.rmp'"
check "genesis_plus_gx host: an older run folder is not reused" "[ ! -e '${RR}/Snes9x/Snes9x.rmp' ]"

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
printf '%s\n' "system.autohotkeys=1" >"${TMP}/system.cfg"
check "stamp names the built-in pad" "[ \"\$(cat '${TMP}/ra/.archr-hotkeys')\" = odroidgo3-joypad ]"
bash "${HK}" "${R}"
check "same pad: hotkeys stay" "has 'input_menu_toggle_btn = \"9\"' '${R}'"
echo "old-joypad" >"${TMP}/ra/.archr-hotkeys"
bash "${HK}" "${R}"
check "another built-in pad: written again" "has 'input_menu_toggle_btn = \"2\"' '${R}'"

# Migration: old factory values go, user values and other keys stay, once.
# An older installation: today's defaults plus some of the old factory lines.
{ grep -v '^migration\.' "${PKG}/config/system/configs/system.cfg"
  printf '%s\n' gba.ratio=3/2 global.bezel=thebezelproject snes.integerscale=0 \
    snes.ratio=16/9 global.ratio=core global.rewind=0; } >"${TMP}/system.cfg"
echo "nes.integerscale=1" >>"${TMP}/system.cfg"
bash "${SCRIPTS}/archr-retroarch-defaults"
C="${TMP}/system.cfg"
check "factory gba ratio removed" "! grep -q '^gba.ratio=' '${C}'"
check "factory bezel removed" "! grep -q '^global.bezel=' '${C}'"
check "factory integerscale removed" "! grep -q '^snes.integerscale=' '${C}'"
check "factory global ratio and rewind removed" "! grep -Eq '^global.(ratio|rewind)=' '${C}'"
check "user ratio kept" "has 'snes.ratio=16/9' '${C}'"
check "user integerscale kept" "has 'nes.integerscale=1' '${C}'"
check "unrelated keys kept" "has 'global.autosave=1' '${C}' && has 'system.hostname=archr' '${C}'"
check "migration marked done" "has 'migration.retroarch_defaults=1' '${C}'"
echo "gba.ratio=3/2" >>"${C}"
bash "${SCRIPTS}/archr-retroarch-defaults"
check "migration runs once" "has 'gba.ratio=3/2' '${C}'"

exit "${FAILED}"
