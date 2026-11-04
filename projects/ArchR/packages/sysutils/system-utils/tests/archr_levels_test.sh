#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-levels: builds it with the host compiler (libpulse
# headers needed) and drives it against a fake backlight, a temporary
# system.cfg, a stub saver and a datagram socket standing for archr-osd.
# PulseAudio is unreachable on purpose: volume levels are still tracked.
#   bash projects/ArchR/packages/sysutils/system-utils/tests/archr_levels_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SOURCE="$(dirname "${HERE}")/sources/levels/archr-levels.c"
TMP=$(mktemp -d)
DAEMON=
OSD=
cleanup() {
  [ -n "${DAEMON}" ] && kill "${DAEMON}" 2>/dev/null
  [ -n "${OSD}" ] && kill "${OSD}" 2>/dev/null
  wait 2>/dev/null
  rm -rf "${TMP}"
}
trap cleanup EXIT
FAILED=0

if ! ${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -o "${TMP}/archr-levels" "${SOURCE}" -lm; then
  echo "SKIP: cannot build archr-levels (compiler or PulseAudio headers missing)"
  exit 0
fi

mkdir -p "${TMP}/backlight/panel" "${TMP}/run"
echo 255 >"${TMP}/backlight/panel/max_brightness"
echo 0 >"${TMP}/backlight/panel/brightness"
printf 'audio.volume=40\ndisplay.brightness=50\n' >"${TMP}/system.cfg"
# The real writer (001-functions' rewrite_config) on a temporary system.cfg;
# each successful write is logged, and "${TMP}/fail" makes writes fail.
cat >"${TMP}/functions" <<PROFILE
. "${HERE}/../../../archr/profile.d/001-functions"
J_CONF="${TMP}/system.cfg"
J_CONF_LOCK="${TMP}/system.cfg.lock"
eval "real_\$(declare -f rewrite_config)"
rewrite_config() {
  [ -e "${TMP}/fail" ] && return 1
  real_rewrite_config "\$@" && printf '%s\n' "\${pairs[@]}" >>"${TMP}/saves"
}
PROFILE
export ARCHR_LEVELS_SOCKET="${TMP}/run/archr-levels.sock"
export ARCHR_LEVELS_CFG="${TMP}/system.cfg"
export ARCHR_LEVELS_BACKLIGHT="${TMP}/backlight"
export ARCHR_LEVELS_FUNCTIONS="${TMP}/functions"
export XDG_RUNTIME_DIR="${TMP}/run"
export PULSE_SERVER="unix:${TMP}/no-pulse"
L="${TMP}/archr-levels"

check() {
  if [ "${2}" != "${3}" ]; then
    echo "FAIL: ${1}: got '${2}', expected '${3}'"
    FAILED=1
  fi
}
raw() { cat "${TMP}/backlight/panel/brightness"; }
saves() { sort "${TMP}/saves" 2>/dev/null; }

start() {
  "${L}" &
  DAEMON=$!
  for _ in $(seq 50); do [ -S "${ARCHR_LEVELS_SOCKET}" ] && break; sleep 0.1; done
}
stop() {
  kill "${DAEMON}"
  wait "${DAEMON}" 2>/dev/null
  DAEMON=
}

# Commands need the daemon: without it they fail clearly, touching nothing.
ERR=$(${L} brightness +2 2>&1 >/dev/null)
check "no daemon: refused" "$?" 1
case ${ERR} in *"not running"*) ;; *) echo "FAIL: unclear error '${ERR}'"; FAILED=1 ;; esac
check "no daemon: nothing saved" "$(saves)" ""

python3 -I -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(sys.argv[1])
with open(sys.argv[2], "a", buffering=1) as out:
    while True:
        out.write(s.recv(64).decode() + "\n")
' "${TMP}/run/archr-osd.sock" "${TMP}/osd" &
OSD=$!
for _ in $(seq 50); do [ -S "${TMP}/run/archr-osd.sock" ] && break; sleep 0.1; done

# Levels saved with the old linear/cubic scales are converted once:
# 50 % of the backlight and PulseAudio's 40 % look and sound the same.
start
check "migrated brightness" "$(${L} brightness)" 73
check "migrated volume" "$(${L} volume)" 52
check "migration saves" "$(saves)" "$(printf 'audio.volume=52\ndisplay.brightness=73\nlevels.perceptual=1')"
# The boot scripts only ask for a restore: the screen stays where 50 % was.
check "restore keeps the converted level" "$(${L} brightness restore; raw)" "$(printf '73\n129')"
stop
start
check "converted once" "$(${L} brightness)" 73
stop
check "marked once" "$(grep -c '^levels.perceptual=' "${TMP}/system.cfg")" 1

# An interrupted conversion: the write fails (or the daemon dies first).
# The file stays whole and old, and the next start converts it once.
rm -f "${TMP}/saves"
printf 'audio.volume=40\ndisplay.brightness=50\nother=1\n' >"${TMP}/system.cfg"
touch "${TMP}/fail"
start 2>/dev/null
check "unwritten conversion is used" "$(${L} brightness)" 73
check "old file intact" "$(cat "${TMP}/system.cfg")" "$(printf 'audio.volume=40\ndisplay.brightness=50\nother=1')"
kill -9 "${DAEMON}"
wait "${DAEMON}" 2>/dev/null
rm -f "${ARCHR_LEVELS_SOCKET}"
start
check "not converted twice" "$(${L} brightness) $(${L} volume)" "73 52"
rm -f "${TMP}/fail"
sleep 2
check "written by a later settle" "$(sort "${TMP}/system.cfg")" "$(printf 'audio.volume=52\ndisplay.brightness=73\nlevels.perceptual=1\nother=1')"
stop
rm -f "${TMP}/saves"
printf 'audio.volume=40\ndisplay.brightness=50\nlevels.perceptual=1\n' >"${TMP}/system.cfg"
start

# Steps are applied at once but saved only once they settle.
check "step" "$(${L} brightness +2)" 52
check "gamma curve" "$(raw)" 64
check "legible minimum" "$(${L} brightness 0; raw)" "$(printf '5\n13')"
check "full" "$(${L} brightness 100; raw)" "$(printf '100\n255')"
check "volume floor" "$(${L} volume -500)" 0
check "huge level" "$(${L} volume 9223372036854775807)" 100
check "huge step" "$(${L} volume +9223372036854775807)" 100
check "huge negative step" "$(${L} volume -9223372036854775807)" 0
${L} brightness up 2>/dev/null && { echo "FAIL: malformed accepted"; FAILED=1; }
${L} brightness3 2>/dev/null && { echo "FAIL: a third panel accepted"; FAILED=1; }
for _ in 1 2 3 4 5; do ${L} brightness -2 >/dev/null; done
check "daemon steps" "$(${L} brightness)" 90
check "applied at once" "$(raw)" 202
check "not saved per step" "$(saves)" ""
sleep 2
check "saved when settled" "$(saves)" "$(printf 'audio.volume=0\ndisplay.brightness=90')"

# A level counts as saved only once the write succeeds: a failed one is
# tried again at the next settle.
rm -f "${TMP}/saves"
touch "${TMP}/fail"
${L} brightness 80 >/dev/null
sleep 2
check "failed write: nothing saved" "$(saves)" ""
rm -f "${TMP}/fail"
sleep 2
check "failed write: retried" "$(saves)" "display.brightness=80"
check "failed write: file" "$(grep '^display.brightness=' "${TMP}/system.cfg")" "display.brightness=80"
${L} brightness 90 >/dev/null
sleep 2

# A hold: one tap, then 25 %/s, faster after 950 ms; release stops it.
rm -f "${TMP}/saves"
: >"${TMP}/osd"
${L} volume 10 >/dev/null
check "hold tap" "$(${L} volume hold up osd)" 12
sleep 0.3
check "hold delay" "$(${L} volume)" 12
sleep 1.0
${L} release
HELD=$(${L} volume)
if [ "${HELD}" -lt 30 ] || [ "${HELD}" -gt 50 ]; then
  echo "FAIL: 1.3 s hold reached ${HELD}, expected 30-50"
  FAILED=1
fi
sleep 0.2
check "release stops" "$(${L} volume)" "${HELD}"
OSD_LINES=$(grep -c '^volume ' "${TMP}/osd")
if [ "${OSD_LINES}" -lt 20 ]; then
  echo "FAIL: ${OSD_LINES} pill updates during the hold, expected one per tick"
  FAILED=1
fi
check "pill shows the last level" "$(tail -n1 "${TMP}/osd")" "volume ${HELD}"
sleep 2
check "hold saved once" "$(saves)" "audio.volume=${HELD}"

# A release can be lost (input_sense restarting): a hold that hears
# nothing stops after 2 s, short of the top; renewals (key repeats) keep it
# going and it stops 400 ms after the last one.
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
sleep 2.3
LOST=$(${L} volume)
sleep 0.6
check "lost release: stopped" "$(${L} volume)" "${LOST}"
if [ "${LOST}" -ge 95 ]; then
  echo "FAIL: a hold without release reached ${LOST}"
  FAILED=1
fi
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 0.2; ${L} renew; done
check "renewed past the cap" "$(${L} volume)" 100
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
for _ in 1 2 3 4; do sleep 0.2; ${L} renew; done
sleep 0.5
STOPPED=$(${L} volume)
sleep 0.5
check "stops 400 ms after the last renewal" "$(${L} volume)" "${STOPPED}"

# A hold stops at the end of the range by itself.
${L} brightness 96 >/dev/null
${L} brightness hold up >/dev/null
sleep 0.6
check "hold stops at 100" "$(${L} brightness)" 100

# Settled levels follow system.cfg edits (a reset, a restore).
sleep 2
printf 'audio.volume=33\ndisplay.brightness=50\nlevels.perceptual=1\n' >"${TMP}/system.cfg"
check "follows the file" "$(${L} volume)" 33

stop
[ -S "${ARCHR_LEVELS_SOCKET}" ] && { echo "FAIL: socket left behind"; FAILED=1; }

[ ${FAILED} -eq 0 ] && echo "archr_levels_test: OK"
exit ${FAILED}
