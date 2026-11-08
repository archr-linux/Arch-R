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
# The card's runtime dir must come from the script, not this shell.
unset XDG_RUNTIME_DIR
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
printf '#!/bin/sh\necho "$*" >>"%s/osd"\necho "${XDG_RUNTIME_DIR}" >"%s/osd-dir"\n' "${TMP}" "${TMP}" >"${OSD}"
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
check "the card reaches the session's overlay" "$(cat "${TMP}/osd-dir")" "/var/run/0-runtime-dir"
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

# DuckStation: SIGINT (TERM would close it without saving), its resume
# state by serial; without SaveStateOnExit the switcher leaves it open.
export DUCK_CFG="${TMP}/duckstation.ini"
echo 'SaveStateOnExit = true' >"${DUCK_CFG}"
mkdir -p "${STATES_DIR}/psx"
cat >"${TMP}/bin/duckstation-sa" <<STUB
#!/usr/bin/python3
import signal, sys, time
def save(*_):
    open("${STATES_DIR}/psx/SCUS-94426_resume.sav", "w").write("state")
    sys.exit(0)
signal.signal(signal.SIGINT, save)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while True:
    time.sleep(0.05)
STUB
chmod +x "${TMP}/bin/duckstation-sa"
duck() {
  "${TMP}/bin/duckstation-sa" &
  EMU=$!
  echo "-9 AppRun.wrapped" >"${KILL_DATA}"
  sleep 0.3
  game "/roms/psx/CTR.chd" psx duckstation duckstation-sa
}
duck
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "duckstation: closed by SIGINT" "$?|$(running)" "0|closed"
check "duckstation: its resume state" "$(cut -f6 "${RESUME_DIR}/resume-last")" "${STATES_DIR}/psx/SCUS-94426_resume.sav"
stop
echo 'SaveStateOnExit = false' >"${DUCK_CFG}"
duck
"${SAVE_EXIT}" switch >/dev/null 2>&1
check "duckstation without SaveStateOnExit: open" "$?|$(running)" "3|running"
stop
rm -f "${SWITCHER}"

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
check "forget drops the line" "$(cut -f8 "${RESUME_DIR}/resume.tsv" | tr '\n' '|')" "/roms/nds/Game.nds|/roms/psx/CTR.chd|${N64}|"
"${SAVE_EXIT}" --forget /roms/nds/Game.nds
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
# The save gets the picture taken before the card.
printf '#!/bin/sh\necho "save $* $(cat "$PICTURE_FROM" 2>/dev/null)" >>"%s/power"\n' "${TMP}" >"${TMP}/bin/save"
printf '#!/bin/sh\necho off >>"%s/power"\n' "${TMP}" >"${TMP}/bin/off"
# The wait between readings: the clock moves on by the interval, and the
# next line of the sequence ("file value", or "-" for no change) is applied.
cat >"${TMP}/bin/tick" <<TICK
#!/bin/bash
read -r up _ <"${TMP}/uptime"; up=\${up%%.*}
echo "\$((up + \$1)) 0" >"${TMP}/uptime"
[ -s "${TMP}/seq" ] || exit 0
read -r file value <"${TMP}/seq"
sed -i 1d "${TMP}/seq"
[ "\${file}" = - ] || echo "\${value}" >"${BAT}/\${file}"
TICK
chmod +x "${TMP}/bin/"*
guard() {
  rm -f "${TMP}/osd" "${TMP}/power"
  touch "${TMP}/osd" "${TMP}/power"
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  echo "1000.00 0" >"${TMP}/uptime"
  BATTERY_GUARD_PROFILE="${TMP}/profile" BATTERY="${BAT}" OSD="${TMP}/bin/osd" \
    SAVE_EXIT="${TMP}/bin/save" POWEROFF="${TMP}/bin/off" GRIM="${TMP}/bin/grim" \
    SLEEP="${TMP}/bin/tick" UPTIME="${TMP}/uptime" CUT_WINDOW="${CUT_WINDOW:-60}" \
    INTERVAL="${INTERVAL:-10}" COUNTDOWN="${COUNTDOWN:-2}" ROUNDS="${ROUNDS:-7}" \
    bash "${SCRIPTS}/archr-battery-guard" >"${TMP}/log" 2>&1
  rm -f "${TMP}/seq"
}
# The readings after the first, one line per wait (see tick).
seq() { printf '%s\n' "$@" >"${TMP}/seq"; }
battery() { echo "$1" >"${BAT}/capacity"; echo "$2" >"${BAT}/status"; }
# Volts, in microvolts as the kernel says them, and the design minimum.
volts() { echo "$1" >"${BAT}/voltage_avg"; echo "${2-3500000}" >"${BAT}/voltage_min_design"; }
# A pack that is low (under the design minimum - 100 mV): the percentage
# counts, held for a minute (7 readings, 10 s apart).
volts 3380000

battery 50 Discharging
guard
check "plenty of battery: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
battery 9 Discharging
guard
check "low: one warning" "$(cat "${TMP}/osd")" "send battery-low 9"
check "low: no power off" "$(cat "${TMP}/power")" ""
battery 3 Discharging
guard
check "critical, no game: countdown, no low warning" "$(tr '\n' '|' <"${TMP}/osd")" "send battery 3 2 2 menu|send battery 3 1 2 menu|"
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
# Readings under the limit, then one above it: the gauge wavered, the count
# starts over.
battery 3 Discharging
seq - - - - "capacity 40" "capacity 3"
ROUNDS=11 guard
check "3% x5, 40%, 3% x5: no power off" "$(cat "${TMP}/power")" ""
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
# A gauge stuck at 0% on a pack that is not empty (issue 50): the voltage
# says so, and the device must not power off nor warn.
battery 0 Discharging
volts 3850000
guard
check "0% at 3.85 V: the gauge is wrong, nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
battery 3 Discharging
volts 3410000
ROUNDS=10 guard
check "3% at 3.41 V, over the design minimum - 100 mV: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
volts 3400000
ROUNDS=10 guard
check "3% at 3.40 V (at the threshold): nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
volts 3390000
guard
check "3% at 3.39 V: the pack is low, power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
battery 9 Discharging
volts 3900000
guard
check "9% at 3.90 V: no warning either" "$(cat "${TMP}/osd")" ""
volts 3600000
guard
check "9% at 3.60 V: the warning" "$(cat "${TMP}/osd")" "send battery-low 9"
# The voltage recovers during the countdown.
battery 3 Discharging
volts 3380000
(sleep 1.5; volts 3800000) &
COUNTDOWN=4 guard
check "a voltage that recovers during the countdown cancels it" "$(cat "${TMP}/power")" ""
# ... or while the game is saved, just before the power off.
printf '#!/bin/sh\necho "save $*" >>"%s/power"\necho 3800000 >"%s/voltage_avg"\n' "${TMP}" "${BAT}" >"${TMP}/bin/save"
emulator fakegame ":"
game "${ROM}" snes retroarch snes9x
volts 3380000
guard
pkill -f "${TMP}/bin/fakegame"; EMU=
check "a voltage that recovers during the save: saved, but no power off" "$(tr '\n' '|' <"${TMP}/power")" "save battery|"
# ... or the gauge, back over the critical level after the save.
printf '#!/bin/sh\necho "save $*" >>"%s/power"\necho 40 >"%s/capacity"\n' "${TMP}" "${BAT}" >"${TMP}/bin/save"
emulator fakegame ":"
game "${ROM}" snes retroarch snes9x
battery 2 Discharging
volts 3380000
guard
pkill -f "${TMP}/bin/fakegame"; EMU=
check "a level back over the critical one after the save: saved, but no power off" "$(tr '\n' '|' <"${TMP}/power")" "save battery|"
printf '#!/bin/sh\necho "save $*" >>"%s/power"\necho 3 >"%s/capacity"\n' "${TMP}" "${BAT}" >"${TMP}/bin/save"
emulator fakegame ":"
game "${ROM}" snes retroarch snes9x
battery 2 Discharging
guard
pkill -f "${TMP}/bin/fakegame"; EMU=
check "a level still at the critical one after the save: power off" "$(tr '\n' '|' <"${TMP}/power")" "save battery|off|"
printf '#!/bin/sh\necho "save $* $(cat "$PICTURE_FROM" 2>/dev/null)" >>"%s/power"\n' "${TMP}" >"${TMP}/bin/save"

# A pack at 40% that sags under load (Wi-Fi, CPU) to 3.49 V, under the
# design minimum: it is not empty (the R36S of 2026-11-07 powered off here).
battery 40 Discharging
volts 3490000
ROUNDS=3 guard
check "40% at 3.49 V under load for 3 readings: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
ROUNDS=10 guard
check "40% at 3.49 V under load for 10 readings: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
# The gauge at 0% on a charged pack (issue 50), for a long time: nothing.
battery 0 Discharging
volts 3900000
ROUNDS=10 guard
check "0% at 3.90 V for 10 readings: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
# ... nor on a half pack that sags under load (over the design minimum - 100 mV).
volts 3490000
ROUNDS=10 guard
check "0% at 3.49 V under load for 10 readings: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
# The critical level counts with the voltage low for a minute.
battery 2 Discharging
volts 3390000
ROUNDS=7 guard
check "2% at 3.39 V for 60 s (7 readings): power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
check "2% at 3.39 V: the card says 2%" "$(tr '\n' '|' <"${TMP}/osd")" "send battery 2 2 2 menu|send battery 2 1 2 menu|"
check "2% at 3.39 V: the log says the percentage, the threshold and the readings" "$(cat "${TMP}/log")" \
  "archr-battery-guard: battery at 2% and under 3400000 uV for 60 s, 7 readings (3390000 3390000 3390000 3390000 3390000 3390000 3390000 uV) (now 3390000 uV), powering off"
ROUNDS=6 guard
check "2% at 3.39 V for 50 s (6 readings): nothing" "$(cat "${TMP}/power")" ""
seq - - - - "voltage_avg 3410000" "voltage_avg 3390000"
ROUNDS=7 guard
check "2% at 3.39 V x5, then 3.41 V, then 3.39 V: nothing" "$(cat "${TMP}/power")" ""
volts 3390000
seq - - - - "voltage_avg 3410000" "voltage_avg 3390000"
ROUNDS=11 guard
check "2% at 3.39 V x5, 3.41 V, 3.39 V x5: the count starts over, nothing" "$(cat "${TMP}/power")" ""

# The voltage cuts by itself, whatever the percentage says: under the design
# minimum - 150 mV (3.35 V here) for a minute.
battery 40 Discharging
volts 3300000
ROUNDS=7 guard
check "40% at 3.30 V for 60 s (7 readings): power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
check "the cut's card says the pack is empty (0%)" "$(tr '\n' '|' <"${TMP}/osd")" "send battery 0 2 2 menu|send battery 0 1 2 menu|"
check "the cut's log says the threshold and the readings" "$(cat "${TMP}/log")" \
  "archr-battery-guard: battery voltage under 3350000 uV for 60 s, 7 readings (3300000 3300000 3300000 3300000 3300000 3300000 3300000 uV; gauge at 40%) (now 3300000 uV), powering off"
ROUNDS=6 guard
check "40% at 3.30 V for 50 s (6 readings): nothing" "$(cat "${TMP}/power")" ""
battery 80 Discharging
volts 3340000
ROUNDS=7 guard
check "80% at 3.34 V for 60 s: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
volts 3350000
ROUNDS=10 guard
check "80% at 3.35 V (at the threshold) for 10 readings: nothing" "$(cat "${TMP}/power")" ""
volts 3360000
ROUNDS=10 guard
check "80% at 3.36 V for 10 readings: nothing" "$(cat "${TMP}/power")" ""
# The window is time and readings: 5 readings 15 s apart hold for 60 s.
volts 3340000
INTERVAL=15 ROUNDS=5 guard
check "80% at 3.34 V, 5 readings over 60 s: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
INTERVAL=15 ROUNDS=4 guard
check "80% at 3.34 V, 4 readings over 45 s: nothing" "$(cat "${TMP}/power")" ""
INTERVAL=30 ROUNDS=4 guard
check "80% at 3.34 V, 4 readings over 90 s: nothing" "$(cat "${TMP}/power")" ""
# ... with no window, 5 readings still.
CUT_WINDOW=0 ROUNDS=4 guard
check "4 readings under the cut, no window: nothing" "$(cat "${TMP}/power")" ""
CUT_WINDOW=0 ROUNDS=5 guard
check "5 readings under the cut, no window: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
# Discarded readings do not complete the window by themselves.
seq "voltage_avg 2500000" - - - - - "voltage_avg 3340000"
ROUNDS=8 guard
check "3.34 V, 6 invalid readings over 60 s, 3.34 V: nothing" "$(cat "${TMP}/power")" ""
battery 2 Discharging
volts 3390000
seq "voltage_avg 2500000" - - - - - "voltage_avg 3390000"
ROUNDS=8 guard
check "2% at 3.39 V, 6 invalid readings over 60 s, 3.39 V: nothing" "$(cat "${TMP}/power")" ""
battery 80 Discharging
volts 3300000
battery 80 Charging
ROUNDS=8 guard
check "the cut with a charger: nothing" "$(cat "${TMP}/power")" ""
# Load spikes do not add up: 5 readings under, one over, 5 under.
battery 40 Discharging
volts 3300000
seq - - - - "voltage_avg 3400000" "voltage_avg 3300000"
ROUNDS=11 guard
check "the cut: 3.30 V x5, 3.40 V, 3.30 V x5: the count starts over, nothing" "$(cat "${TMP}/power")" ""
# A discarded reading neither counts nor starts the count over.
volts 3300000
seq - - "voltage_avg 2500000" "voltage_avg 3300000"
ROUNDS=7 guard
check "the cut: 3.30 V x3, an invalid reading, 3.30 V x3: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
# ... with the level unreadable too.
rm -f "${BAT}/capacity"
volts 3300000
seq - - "voltage_avg 2500000" "voltage_avg 3300000"
ROUNDS=7 guard
check "no level: 3.30 V x3, an invalid reading, 3.30 V x3: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
battery 40 Discharging
volts 3300000
(sleep 1.5; volts 3700000) &
COUNTDOWN=4 guard
check "the cut: a voltage that recovers during the countdown cancels it" "$(cat "${TMP}/power")" ""
# A real deep discharge (2.7-3.0 V) is not an invalid reading: it carries on.
battery 35 Discharging
volts 3300000
(sleep 1.5; volts 2950000) &
COUNTDOWN=4 ROUNDS=7 guard
check "35% at 3.30 V, then 2.95 V during the countdown: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
volts 3300000
(sleep 1.5; volts 2500000) &
COUNTDOWN=4 ROUNDS=7 guard
check "... a reading under 2.7 V during the countdown is dropped: still power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
volts 2950000
ROUNDS=7 guard
check "2.95 V from the start: the cut" "$(tr '\n' '|' <"${TMP}/power")" "off|"
volts 3300000
ROUNDS=8 guard "power.battery.critical=0"
check "the cut follows the critical setting (0: off)" "$(cat "${TMP}/power")" ""

# Voltages that cannot be right are thrown away.
battery 3 Discharging
for bad in 2600000 4600000 abc ""; do
  volts "${bad}"
  ROUNDS=4 guard
  check "an invalid voltage (${bad}): nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
done
rm -f "${BAT}/voltage_avg"
ROUNDS=4 guard
check "no voltage file: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""

# A design minimum that cannot be right is taken as 3.4 V (the cut at 3.25 V).
battery 80 Discharging
for min in 2000000 4200000 abc ""; do
  volts 3240000 "${min}"
  ROUNDS=7 guard
  check "design minimum '${min}', 3.24 V (under 3.25): power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
  volts 3260000 "${min}"
  ROUNDS=7 guard
  check "design minimum '${min}', 3.26 V (over 3.25): nothing" "$(cat "${TMP}/power")" ""
done
# A design minimum in range is used as it is: 3.3 V, the cut at 3.15 V.
volts 3160000 3300000
ROUNDS=8 guard
check "design minimum 3.3 V, 3.16 V: nothing" "$(cat "${TMP}/power")" ""
volts 3140000 3300000
ROUNDS=7 guard
check "design minimum 3.3 V, 3.14 V: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
rm -f "${BAT}/voltage_min_design"
echo 3240000 >"${BAT}/voltage_avg"
ROUNDS=7 guard
check "no design minimum, 3.24 V: power off" "$(tr '\n' '|' <"${TMP}/power")" "off|"
volts 3380000
battery 3 Discharging
guard "power.battery.critical=0" "power.battery.low=0"
check "both off: nothing" "$(cat "${TMP}/osd" "${TMP}/power")" ""
guard "power.battery.critical=2"
check "under its own level only" "$(cat "${TMP}/power")" ""

exit ${FAILED}
