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
# The saver writes system.cfg as set_setting does (locked), and logs each call.
cat >"${TMP}/save" <<STUB
#!/bin/sh
exec 9>"${TMP}/save.lock"
flock 9
grep -v "^\$1=" "${TMP}/system.cfg" >"${TMP}/cfg.new"
echo "\$1=\$2" >>"${TMP}/cfg.new"
mv "${TMP}/cfg.new" "${TMP}/system.cfg"
echo "\$1=\$2" >>"${TMP}/saves"
STUB
chmod +x "${TMP}/save"
export ARCHR_LEVELS_SOCKET="${TMP}/run/archr-levels.sock"
export ARCHR_LEVELS_CFG="${TMP}/system.cfg"
export ARCHR_LEVELS_BACKLIGHT="${TMP}/backlight"
export ARCHR_LEVELS_SAVER="${TMP}/save"
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
saves() { cat "${TMP}/saves" 2>/dev/null; }

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
stop
start
check "converted once" "$(${L} brightness)" 73
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
${L} brightness up 2>/dev/null && { echo "FAIL: malformed accepted"; FAILED=1; }
for _ in 1 2 3 4 5; do ${L} brightness -2 >/dev/null; done
check "daemon steps" "$(${L} brightness)" 90
check "applied at once" "$(raw)" 202
check "not saved per step" "$(saves)" ""
sleep 2
check "saved when settled" "$(saves)" "$(printf 'audio.volume=0\ndisplay.brightness=90')"

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
