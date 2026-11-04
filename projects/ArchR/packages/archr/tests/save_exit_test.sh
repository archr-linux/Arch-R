#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for "save and exit" and the battery guard:
#   archr-game-save-exit   closes a stand-in emulator, keeps the records
#   archr-battery-guard    warns, counts down, saves and powers off
#   bash projects/ArchR/packages/archr/tests/save_exit_test.sh

# shellcheck disable=SC2016 # stubs and their arguments expand when they run
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="$(dirname "${HERE}")/sources/scripts"
FUNCTIONS="$(dirname "${HERE}")/profile.d/001-functions"
FAILED=0
TMP=$(mktemp -d)
EMU=
# shellcheck disable=SC2329,SC2016 # cleanup runs on exit; stubs keep their $1
cleanup() {
  pkill -f "${TMP}/bin/" 2>/dev/null
  rm -rf "${TMP}"
}
trap cleanup EXIT

check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILED=1; fi
}

export CURRENT_GAME="${TMP}/run/current-game" RESUME_DIR="${TMP}/config"
export SWITCHER="${TMP}/run/switcher" SAVING="${TMP}/run/saving"
export STATES_DIR="${TMP}/states" MUPEN_STATES="${TMP}/n64" KILL_DATA="${TMP}/kill"
export RETROARCH_RUN_CFG="${TMP}/retroarch.cfg" MUPEN_CFG="${TMP}/mupen64plus.cfg"
export CORES_DIR="${TMP}/cores"
mkdir -p "${CORES_DIR}"
echo 'savestate = "true"' >"${CORES_DIR}/snes9x_libretro.info"
echo 'savestate = "false"' >"${CORES_DIR}/scummvm_libretro.info"
export KEYPRESS="${TMP}/bin/keypress" GRIM="${TMP}/bin/grim" OSD="${TMP}/bin/osd"
export TICK=0.05 STATE_WAIT=20 CLOSE_WAIT=40 LOCK_WAIT=20
mkdir -p "${TMP}/run" "${TMP}/bin" "${STATES_DIR}/snes" "${MUPEN_STATES}"
SAVE_EXIT="${SCRIPTS}/archr-game-save-exit"
printf '#!/bin/sh\nfor a; do f=$a; done\necho picture >"$f"\n' >"${GRIM}"
printf '#!/bin/sh\necho "$*" >>"%s/osd"\n' "${TMP}" >"${OSD}"
# The mupen64plus keys: the emulator writes the state of the slot chosen.
cat >"${KEYPRESS}" <<STUB
#!/bin/sh
echo "\$*" >>"${TMP}/keys"
# Each call on its own line; F5 saves to the slot just chosen.
[ "\$2" = F5 ] && [ ! -e "${TMP}/no-state" ] && echo state >"${MUPEN_STATES}/Mario (U)-635A42C5.st\$1"
exit 0
STUB
echo 'CurrentStateSlot = 2' >"${MUPEN_CFG}"
autosave() { printf 'savestate_auto_save = "%s"\n' "$1" >"${RETROARCH_RUN_CFG}"; }

# A stand-in emulator named NAME under a stand-in runemu.sh: on TERM it
# runs ON_TERM and quits, as RetroArch writes its automatic state.
emulator() {
  local name="$1" on_term="$2"
  printf '#!/bin/bash\ntrap %q TERM\nwhile :; do sleep 0.05; done\n' "${on_term}; exit 0" >"${TMP}/bin/${name}"
  chmod +x "${TMP}/bin/${name}"
  bash -c "\"${TMP}/bin/${name}\"; exit 0" &
  EMU=$!
  echo "${name}" >"${KILL_DATA}"
  sleep 0.2
}
game() {
  printf '%s\n%s\n%s\n%s\n%s\n' "$1" "${EMU}" "$2" "$3" "$4" >"${CURRENT_GAME}"
}
running() { kill -0 "${EMU}" 2>/dev/null && echo running || echo closed; }
stop() { kill -9 "${EMU}" 2>/dev/null; wait "${EMU}" 2>/dev/null; EMU=; }
chmod +x "${TMP}/bin/"*

"${SAVE_EXIT}" switch >/dev/null 2>&1
check "no game: exit 1" "$?" "1"
"${SAVE_EXIT}" nonsense >/dev/null 2>&1
check "a wrong reason: exit 2" "$?" "2"
"${SAVE_EXIT}" shutdown >/dev/null 2>&1
check "no shutdown reason (no caller)" "$?" "2"

ROM="/roms/snes/Chrono Trigger (USA).sfc"
AUTO="${STATES_DIR}/snes/Chrono Trigger (USA).state.auto"
autosave true
emulator fakearch "echo state >\"${AUTO}\""
game "${ROM}" snes retroarch snes9x
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "the game closed" "$(running)" "closed"
stop
LINE=$(cat "${RESUME_DIR}/resume-last")
check "RetroArch: the fresh automatic state" "$(cut -f6 <<<"${LINE}")" "${AUTO}"
check "reason, system, emulator, core" "$(cut -f2-5 <<<"${LINE}")" "switch	snes	retroarch	snes9x"
check "the picture" "$(cut -f7 <<<"${LINE}")" "${RESUME_DIR}/pictures/snes/Chrono Trigger (USA).png"
check "the ROM" "$(cut -f8 <<<"${LINE}")" "${ROM}"
check "the switcher is asked for" "$([ -e "${SWITCHER}" ] && echo yes)" "yes"
check "the saving mark is gone" "$([ -e "${SAVING}" ] && echo left || echo gone)" "gone"

# A core without states (ScummVM, EasyRPG): the game stays open.
emulator fakearch ":"
game "/roms/scummvm/Game.scummvm" scummvm retroarch scummvm
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "a core without states: the game stays open" "$?|$(running)" "3|running"
stop
rm -f "${SWITCHER}"

# No automatic state for this run (netplay, hardcore): the switcher keeps
# the game open and says so; the battery closes it anyway.
rm -f "${SWITCHER}" "${TMP}/osd"
autosave false
emulator fakearch ":"
game "${ROM}" snes retroarch snes9x
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "no automatic state: exit 3" "$?" "3"
check "no automatic state: the game stays open" "$(running)" "running"
check "no automatic state: the card says so" "$(cat "${TMP}/osd")" "send nostate"
check "no automatic state: no switcher" "$([ -e "${SWITCHER}" ] && echo yes || echo no)" "no"
printf 'savestate_auto_save = "true"\ncheevos_hardcore_mode_enable = "1"\n' >"${RETROARCH_RUN_CFG}"
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "hardcore achievements: the game stays open" "$?|$(running)" "3|running"
"${SAVE_EXIT}" battery >/dev/null 2>&1
check "the battery closes it anyway" "$(running)" "closed"
stop
check "an old state is no state" "$(cut -f6 "${RESUME_DIR}/resume-last")" ""
check "battery does not open the switcher" "$([ -e "${SWITCHER}" ] && echo yes || echo no)" "no"
check "one line per game" "$(wc -l <"${RESUME_DIR}/resume.tsv")" "1"

# RetroArch killed before its state was whole: no state recorded.
autosave true
printf '#!/bin/bash\ntrap "echo half >\\"%s\\"" TERM\nwhile :; do echo more >>"%s"; sleep 0.02; done\n' "${AUTO}" "${AUTO}" >"${TMP}/bin/fakearch"
bash -c "\"${TMP}/bin/fakearch\"; exit 0" &
EMU=$!
sleep 0.2
game "${ROM}" snes retroarch snes9x
CLOSE_WAIT=10 "${SAVE_EXIT}" battery >/dev/null 2>&1
check "a state still being written when killed is no state" "$(cut -f6 "${RESUME_DIR}/resume-last")" ""
stop

# mupen64plus: slot 9, F5, back to its slot, then the signal.
N64=/roms/n64/Mario.z64
emulator mupen64plus ":"
game "${N64}" n64 mupen64plus mupen64plus
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "mupen64plus: slot 9 and save, then slot 2 again, apart" "$(tr '\n' '|' <"${TMP}/keys")" "9 F5|2|"
check "mupen64plus: closed" "$(running)" "closed"
stop
check "mupen64plus: the state in slot 9" "$(cut -f6 "${RESUME_DIR}/resume-last")" "${MUPEN_STATES}/Mario (U)-635A42C5.st9"
check "newest first" "$(cut -f8 "${RESUME_DIR}/resume.tsv" | tr '\n' '|')" "${N64}|${ROM}|"
# The state never came: the switcher keeps the game open.
touch "${TMP}/no-state"
rm -f "${MUPEN_STATES}"/*.st9 "${TMP}/osd"
emulator mupen64plus ":"
game "${N64}" n64 mupen64plus mupen64plus
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "mupen64plus without a state: open" "$?|$(running)|$(cat "${TMP}/osd")" "3|running|send nostate"
stop
rm -f "${TMP}/no-state"

# An emulator without a state from outside: the switcher leaves it; the
# battery closes it, and one that ignores the signal is killed.
printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 0.05; done\n' >"${TMP}/bin/stubborn"
chmod +x "${TMP}/bin/stubborn"
bash -c "\"${TMP}/bin/stubborn\"; exit 0" &
EMU=$!
sleep 0.2
echo "-9 stubborn" >"${KILL_DATA}"
game /roms/nds/Game.nds nds drastic drastic
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "drastic: the switcher keeps it open" "$?|$(running)" "3|running"
"${SAVE_EXIT}" suspend >/dev/null 2>&1
wait "${EMU}" 2>/dev/null
check "a stubborn emulator is killed" "$(running)" "closed"
EMU=
check "no state for the others" "$(cut -f4,6 "${RESUME_DIR}/resume-last")" "drastic	"

# A run already going: a second tap leaves; the battery waits for it.
emulator fakearch "echo state >\"${AUTO}\""
game "${ROM}" snes retroarch snes9x
exec 8>"${SAVING}.lock"
flock 8
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "a second tap while saving does nothing" "$?|$(running)" "0|running"
(sleep 1; flock -u 8) &
START=${SECONDS}
"${SAVE_EXIT}" battery >/dev/null 2>&1
check "the battery waits for the run going on, then closes" "$(running)|$((SECONDS - START >= 1))" "closed|1"
exec 8>&-
stop

# A picture taken already (the battery's, before its card) is the one kept.
echo before-the-card >"${TMP}/shot.png"
emulator fakearch "echo state >\"${AUTO}\""
game "${ROM}" snes retroarch snes9x
PICTURE_FROM="${TMP}/shot.png" "${SAVE_EXIT}" battery >/dev/null 2>&1
check "the picture from before the card" "$(cat "${RESUME_DIR}/pictures/snes/Chrono Trigger (USA).png")" "before-the-card"
stop

# runemu.sh, as a game starts: its record and the last mark go.
"${SAVE_EXIT}" --forget "${ROM}"
check "forget drops the line" "$(cut -f8 "${RESUME_DIR}/resume.tsv" | tr '\n' '|')" "/roms/nds/Game.nds|${N64}|"
"${SAVE_EXIT}" --forget /roms/nds/Game.nds
check "forget drops the last mark of that game" "$([ -e "${RESUME_DIR}/resume-last" ] && echo kept || echo gone)" "gone"
"${SAVE_EXIT}" --forget /roms/other.sfc
check "forget of another game keeps the lines" "$(wc -l <"${RESUME_DIR}/resume.tsv")" "1"

# The battery guard, with readings, the screen and the power off stubbed.
BAT="${TMP}/battery"
mkdir -p "${BAT}"
cat >"${TMP}/profile" <<PROFILE
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
PROFILE
printf '#!/bin/sh\necho "$*" >>"%s/osd"\n' "${TMP}" >"${TMP}/bin/osd"
# The save gets the picture taken before the card.
printf '#!/bin/sh\necho "save $* $(cat "$PICTURE_FROM" 2>/dev/null)" >>"%s/power"\n' "${TMP}" >"${TMP}/bin/save"
printf '#!/bin/sh\necho off >>"%s/power"\n' "${TMP}" >"${TMP}/bin/off"
chmod +x "${TMP}/bin/"*
guard() {
  rm -f "${TMP}/osd" "${TMP}/power"
  touch "${TMP}/osd" "${TMP}/power"
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  BATTERY_GUARD_PROFILE="${TMP}/profile" BATTERY="${BAT}" OSD="${TMP}/bin/osd" \
    SAVE_EXIT="${TMP}/bin/save" POWEROFF="${TMP}/bin/off" GRIM="${TMP}/bin/grim" \
    INTERVAL="${INTERVAL:-0}" COUNTDOWN="${COUNTDOWN:-2}" ROUNDS="${ROUNDS:-3}" \
    bash "${SCRIPTS}/archr-battery-guard" >/dev/null 2>&1
}
battery() { echo "$1" >"${BAT}/capacity"; echo "$2" >"${BAT}/status"; }

battery 50 Discharging
guard
check "plenty of battery: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
battery 9 Discharging
guard
check "low: one warning" "$(cat "${TMP}/osd")" "send battery-low 9"
check "low: no power off" "$(cat "${TMP}/power")" ""
battery 3 Discharging
guard
check "critical, no game: countdown" "$(tr '\n' '|' <"${TMP}/osd")" "send battery-low 3|send battery 3 2 2 menu|send battery 3 1 2 menu|"
check "critical, no game: power off only" "$(tr '\n' '|' <"${TMP}/power")" "off|"
emulator fakegame ":"
game "${ROM}" snes retroarch snes9x
guard
pkill -f "${TMP}/bin/fakegame"; EMU=
check "critical with a game: save with the picture from before the card, then power off" \
  "$(tr '\n' '|' <"${TMP}/power")" "save battery picture|off|"
battery 3 Charging
guard
check "a charger: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
battery 3 "Not charging"
guard
check "a charger, full battery (Not charging): nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
# One reading under the limit, the next above it: the gauge wavered.
battery 3 Discharging
(sleep 0.5; battery 40 Discharging) &
INTERVAL=1 ROUNDS=3 guard
check "a single low reading: no power off" "$(cat "${TMP}/power")" ""
# The charger comes in the middle of the countdown, as "Not charging".
battery 3 Discharging
(sleep 1.5; battery 3 "Not charging") &
COUNTDOWN=4 guard
check "a charger during the countdown cancels it" "$(cat "${TMP}/power")" ""
# The level rose during the countdown.
battery 3 Discharging
(sleep 1.5; battery 5 Discharging) &
COUNTDOWN=4 guard
check "a level that rose during the countdown cancels it" "$(cat "${TMP}/power")" ""
battery 3 Discharging
guard "power.battery.critical=0" "power.battery.low=0"
check "both off: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
guard "power.battery.critical=2"
check "under its own level only" "$(cat "${TMP}/power")" ""

exit ${FAILED}
