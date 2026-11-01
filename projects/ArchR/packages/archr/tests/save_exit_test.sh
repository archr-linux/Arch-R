#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for "save and exit" and the battery guard:
#   archr-game-save-exit   closes a stand-in emulator, keeps the records
#   archr-battery-guard    warns, counts down, saves and powers off
#   bash projects/ArchR/packages/archr/tests/save_exit_test.sh

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
export KEYPRESS="${TMP}/bin/keypress" GRIM="${TMP}/bin/grim" TICK=0.05 STATE_WAIT=20 CLOSE_WAIT=40
mkdir -p "${TMP}/run" "${TMP}/bin" "${STATES_DIR}/snes" "${MUPEN_STATES}"
SAVE_EXIT="${SCRIPTS}/archr-game-save-exit"
printf '#!/bin/sh\necho picture >"$1"\n' >"${GRIM}"
# The mupen64plus key: the emulator writes its state file.
printf '#!/bin/sh\necho "$*" >>"%s/keys"\n: >"%s/Mario (U)-635A42C5.st0"\n' "${TMP}" "${MUPEN_STATES}" >"${KEYPRESS}"

# A stand-in emulator named NAME under a stand-in runemu.sh: on TERM it
# runs ON_TERM and quits, as RetroArch writes its automatic state.
emulator() {
  local name="$1" on_term="$2"
  printf '#!/bin/bash\ntrap %q TERM\nwhile :; do sleep 0.05; done\n' "${on_term}; exit 0" >"${TMP}/bin/${name}"
  chmod +x "${TMP}/bin/${name}"
  bash -c "\"${TMP}/bin/${name}\"; exit 0" &
  EMU=$!
  sleep 0.2
}
game() {
  printf '%s\n%s\n%s\n%s\n%s\n' "$1" "${EMU}" "$2" "$3" "$4" >"${CURRENT_GAME}"
}
chmod +x "${TMP}/bin/"*

"${SAVE_EXIT}" switch >/dev/null 2>&1
check "no game: exit 1" "$?" "1"
"${SAVE_EXIT}" nonsense >/dev/null 2>&1
check "a wrong reason: exit 2" "$?" "2"

ROM="/roms/snes/Chrono Trigger (USA).sfc"
emulator fakearch ": >\"${STATES_DIR}/snes/Chrono Trigger (USA).state.auto\""
game "${ROM}" snes retroarch snes9x
echo "fakearch" >"${KILL_DATA}"
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "the game closed" "$(kill -0 "${EMU}" 2>/dev/null && echo running || echo closed)" "closed"
EMU=
LINE=$(cat "${RESUME_DIR}/resume-last")
check "RetroArch: the fresh automatic state" "$(cut -f6 <<<"${LINE}")" "${STATES_DIR}/snes/Chrono Trigger (USA).state.auto"
check "reason, system, emulator, core" "$(cut -f2-5 <<<"${LINE}")" "switch	snes	retroarch	snes9x"
check "the picture" "$(cut -f7 <<<"${LINE}")" "${RESUME_DIR}/pictures/snes/Chrono Trigger (USA).png"
check "the ROM" "$(cut -f8 <<<"${LINE}")" "${ROM}"
check "the switcher is asked for" "$([ -e "${SWITCHER}" ] && echo yes)" "yes"
check "the saving mark is gone" "$([ -e "${SAVING}" ] && echo left || echo gone)" "gone"

# An old state does not count: the emulator wrote nothing this time.
rm -f "${SWITCHER}"
emulator fakearch ":"
game "${ROM}" snes retroarch snes9x
"${SAVE_EXIT}" battery >/dev/null 2>&1
EMU=
check "an old state is no state" "$(cut -f6 "${RESUME_DIR}/resume-last")" ""
check "battery does not open the switcher" "$([ -e "${SWITCHER}" ] && echo yes || echo no)" "no"
check "one line per game" "$(wc -l <"${RESUME_DIR}/resume.tsv")" "1"

# mupen64plus: the save key first, then the signal.
N64=/roms/n64/Mario.z64
emulator mupen64plus ":"
echo "-9 mupen64plus" >"${KILL_DATA}"
game "${N64}" n64 mupen64plus mupen64plus
"${SAVE_EXIT}" shutdown >/dev/null 2>&1
EMU=
check "mupen64plus: F5" "$(cat "${TMP}/keys")" "F5"
check "mupen64plus: the state it wrote" "$(cut -f6 "${RESUME_DIR}/resume-last")" "${MUPEN_STATES}/Mario (U)-635A42C5.st0"
check "newest first" "$(cut -f8 "${RESUME_DIR}/resume.tsv" | tr '\n' '|')" "${N64}|${ROM}|"

# An emulator that ignores the signal is killed, the record still written.
printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 0.05; done\n' >"${TMP}/bin/stubborn"
chmod +x "${TMP}/bin/stubborn"
bash -c "\"${TMP}/bin/stubborn\"; exit 0" &
EMU=$!
sleep 0.2
echo "-9 stubborn" >"${KILL_DATA}"
game /roms/nds/Game.nds nds drastic drastic
"${SAVE_EXIT}" switch >/dev/null 2>&1
wait "${EMU}" 2>/dev/null
check "a stubborn emulator is killed" "$(kill -0 "${EMU}" 2>/dev/null && echo running || echo closed)" "closed"
EMU=
check "no state for the others" "$(cut -f4,6 "${RESUME_DIR}/resume-last")" "drastic	"

# runemu.sh, as a game starts: its record and the last mark go.
"${SAVE_EXIT}" --forget /roms/nds/Game.nds
check "forget drops the line" "$(cut -f8 "${RESUME_DIR}/resume.tsv" | tr '\n' '|')" "${N64}|${ROM}|"
check "forget drops the last mark of that game" "$([ -e "${RESUME_DIR}/resume-last" ] && echo kept || echo gone)" "gone"
"${SAVE_EXIT}" --forget /roms/other.sfc
check "forget of another game keeps the lines" "$(wc -l <"${RESUME_DIR}/resume.tsv")" "2"

# The battery guard, with readings, the screen and the power off stubbed.
BAT="${TMP}/battery"
mkdir -p "${BAT}"
cat >"${TMP}/profile" <<PROFILE
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
PROFILE
printf '#!/bin/sh\necho "$*" >>"%s/osd"\n' "${TMP}" >"${TMP}/bin/osd"
printf '#!/bin/sh\necho "save $*" >>"%s/power"\n' "${TMP}" >"${TMP}/bin/save"
printf '#!/bin/sh\necho off >>"%s/power"\n' "${TMP}" >"${TMP}/bin/off"
chmod +x "${TMP}/bin/"*
guard() {
  rm -f "${TMP}/osd" "${TMP}/power"
  touch "${TMP}/osd" "${TMP}/power"
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  BATTERY_GUARD_PROFILE="${TMP}/profile" BATTERY="${BAT}" OSD="${TMP}/bin/osd" \
    SAVE_EXIT="${TMP}/bin/save" POWEROFF="${TMP}/bin/off" INTERVAL=0 COUNTDOWN=2 ROUNDS=3 \
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
check "critical with a game: save, then power off" "$(tr '\n' '|' <"${TMP}/power")" "save battery|off|"
battery 3 Charging
guard
check "a charger: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
battery 3 Discharging
guard "power.battery.critical=0" "power.battery.low=0"
check "both off: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
guard "power.battery.critical=2"
check "under its own level only" "$(cat "${TMP}/power")" ""

exit ${FAILED}
