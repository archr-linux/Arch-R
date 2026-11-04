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
AUDIO=
cleanup() {
  [ -n "${DAEMON}" ] && kill "${DAEMON}" 2>/dev/null
  [ -n "${AUDIO}" ] && kill ${AUDIO} 2>/dev/null
  [ -n "${OSD}" ] && kill -CONT "${OSD}" 2>/dev/null
  [ -n "${OSD}" ] && kill "${OSD}" 2>/dev/null
  wait 2>/dev/null
  [ -n "${PW:-}" ] && [ -d "${PW}" ] && rm -r "${PW}"
  rm -rf "${TMP}"
}
trap cleanup EXIT
FAILED=0

# Skipped only without the PulseAudio headers; any other build failure fails.
if ! printf '#include <pulse/pulseaudio.h>\n' | ${CC:-cc} -E -x c - >/dev/null 2>&1; then
  echo "SKIP: pulse/pulseaudio.h not found"
  exit 0
fi
if ! ${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -o "${TMP}/archr-levels" "${SOURCE}" -lm; then
  echo "FAIL: archr-levels does not build"
  exit 1
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
# Relative socket names also work under long TMPDIR paths (sun_path is short).
cd "${TMP}" || exit 1
export ARCHR_LEVELS_SOCKET="run/archr-levels.sock"
export ARCHR_LEVELS_CFG="${TMP}/system.cfg"
export ARCHR_LEVELS_BACKLIGHT="${TMP}/backlight"
export ARCHR_LEVELS_FUNCTIONS="${TMP}/functions"
export XDG_RUNTIME_DIR="run"
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
import selectors, socket, sys
listeners = selectors.DefaultSelector()
for path, log in zip(sys.argv[1::2], sys.argv[2::2]):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    s.bind(path)
    listeners.register(s, selectors.EVENT_READ, open(log, "a", buffering=1))
while True:
    for key, _ in listeners.select():
        key.data.write(key.fileobj.recv(64).decode() + "\n")
' "run/archr-osd.sock" "${TMP}/osd" \
  "run/archr-launcher-levels.sock" "${TMP}/launcher" &
OSD=$!
for _ in $(seq 50); do [ -S "${TMP}/run/archr-launcher-levels.sock" ] && break; sleep 0.1; done

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
( for _ in $(seq 8); do sleep 0.2; ${L} renew; done ) &
RENEWER=$!
sleep 0.3
check "hold delay" "$(${L} volume)" 12
sleep 1.0
${L} release
wait "${RENEWER}"
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

# A release can be lost (the caller died): a hold that is not renewed
# ends 400 ms after it started or after the last renewal, near where it was.
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
sleep 0.8
LOST=$(${L} volume)
if [ "${LOST}" -gt 4 ]; then
  echo "FAIL: a hold never renewed reached ${LOST}"
  FAILED=1
fi
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
for _ in $(seq 25); do sleep 0.2; ${L} renew; done
check "renewed for 5 s: goes on to the top" "$(${L} volume)" 100
${L} volume 0 >/dev/null
${L} volume hold up >/dev/null
for _ in 1 2 3 4; do sleep 0.2; ${L} renew; done
sleep 0.5
STOPPED=$(${L} volume)
sleep 0.5
check "stops 400 ms after the last renewal" "$(${L} volume)" "${STOPPED}"
# 0.8 s of renewals plus the 400 ms lease: 1.2 s of hold, about 30.
if [ "${STOPPED}" -gt 35 ]; then
  echo "FAIL: 0.8 s of renewals reached ${STOPPED}"
  FAILED=1
fi

# A hold stops at the end of the range by itself.
${L} brightness 96 >/dev/null
${L} brightness hold up >/dev/null
for _ in 1 2 3; do sleep 0.2; ${L} renew; done
check "hold stops at 100" "$(${L} brightness)" 100

# Settled levels follow system.cfg edits (a reset, a restore).
sleep 2
printf 'audio.volume=33\ndisplay.brightness=50\nlevels.perceptual=1\n' >"${TMP}/system.cfg"
check "follows the file" "$(${L} volume)" 33

# Sequence-aware clients opt in; legacy commands and the installed OSD keep
# their old format. The same state version travels in replies and notices.
read -r VALUE SEQ < <(${L} volume seq)
check "sequenced read: value" "${VALUE}" 33
if ! [[ ${SEQ} =~ ^[0-9]+$ ]]; then
  echo "FAIL: missing sequence '${SEQ}'"
  FAILED=1
else
  read -r VALUE SAME < <(${L} volume seq)
  check "read keeps the state version" "${SAME}" "${SEQ}"
  read -r VALUE NEXT < <(${L} volume +2 osd seq)
  check "sequenced step" "${VALUE}" 35
  if ! [[ ${NEXT} =~ ^[0-9]+$ ]] || [ "${NEXT}" -le "${SEQ}" ]; then
    echo "FAIL: step sequence did not advance '${SEQ}' -> '${NEXT}'"
    FAILED=1
  fi
  for _ in $(seq 50); do grep -q "^volume 35 ${NEXT}$" "${TMP}/launcher" 2>/dev/null && break; sleep 0.02; done
  check "launcher gets the response sequence" "$(tail -n1 "${TMP}/launcher")" "volume 35 ${NEXT}"
  check "installed OSD still gets two fields" "$(tail -n1 "${TMP}/osd")" "volume 35"
  read -r VALUE HELD_SEQ < <(${L} volume hold up osd seq)
  check "sequenced hold" "${VALUE}" 37
  if ! [[ ${HELD_SEQ} =~ ^[0-9]+$ ]] || [ "${HELD_SEQ}" -le "${NEXT}" ]; then
    echo "FAIL: hold sequence did not advance"
    FAILED=1
  fi
  sleep 0.38
  ${L} release
  read -r VALUE LAST < <(${L} volume seq)
  if ! [[ ${LAST} =~ ^[0-9]+$ ]] || [ "${LAST}" -le "${HELD_SEQ}" ]; then
    echo "FAIL: hold tick sequence did not advance"
    FAILED=1
  fi
  read -r VALUE SAME < <(${L} volume seq)
  check "release read keeps the last version" "${SAME}" "${LAST}"
  stop
  start
  read -r VALUE RESTARTED < <(${L} volume seq)
  if ! [[ ${RESTARTED} =~ ^[0-9]+$ ]] || [ "${RESTARTED}" -le "${LAST}" ]; then
    echo "FAIL: sequence went backwards after daemon restart"
    FAILED=1
  fi
fi

# The launcher also hears changes made without requesting a pill.
PILL=$(tail -n1 "${TMP}/osd")
read -r VALUE BRIGHT_SEQ < <(${L} brightness 44 seq)
check "sequenced brightness" "${VALUE}" 44
for _ in $(seq 50); do grep -q "^brightness 44 ${BRIGHT_SEQ}$" "${TMP}/launcher" && break; sleep 0.02; done
check "notice without OSD" "$(tail -n1 "${TMP}/launcher")" "brightness 44 ${BRIGHT_SEQ}"
check "no extra pill" "$(tail -n1 "${TMP}/osd")" "${PILL}"

# Full or absent listeners cannot block the command daemon.
kill -STOP "${OSD}"
for _ in $(seq 30); do
  ${L} volume +1 osd >/dev/null || { echo "FAIL: full notice queue blocked a command"; FAILED=1; break; }
done
kill -CONT "${OSD}"
kill "${OSD}"
wait "${OSD}" 2>/dev/null
OSD=
${L} brightness +1 osd >/dev/null || { echo "FAIL: absent listeners blocked a command"; FAILED=1; }

stop
[ -S "${ARCHR_LEVELS_SOCKET}" ] && { echo "FAIL: socket left behind"; FAILED=1; }

# The volume reaches the default sink whenever there is one (#39): the
# daemon starts before the audio server, the card's sink appears after the
# boot's restore, the server restarts, the default sink changes. A private
# PipeWire stands for the console's, with no session manager (no hardware
# touched): the test sets the default sink through the "default" metadata,
# as WirePlumber does. No command is sent after the first level: the
# daemon has to follow on its own.
if ! command -v pipewire >/dev/null || ! command -v pipewire-pulse >/dev/null ||
  ! command -v pactl >/dev/null || ! command -v pw-metadata >/dev/null; then
  if [ "${ARCHR_LEVELS_NO_PIPEWIRE:-}" = 1 ]; then
    echo "SKIP (ARCHR_LEVELS_NO_PIPEWIRE=1): sink tests"
  else
    echo "FAIL: sink tests need pipewire, pipewire-pulse, pactl and pw-metadata (ARCHR_LEVELS_NO_PIPEWIRE=1 skips them)"
    FAILED=1
  fi
else
  # Socket paths are short (sun_path): a directory of its own under /tmp.
  PW=$(mktemp -d /tmp/alv.XXXXXX)
  mkdir -p "${PW}/cfg/pipewire/pipewire.conf.d"
  printf 'context.objects = [ { factory = metadata args = { metadata.name = default } } ]\n' \
    >"${PW}/cfg/pipewire/pipewire.conf.d/archr-levels-test.conf"
  pw() { env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="${PW}" PIPEWIRE_RUNTIME_DIR="${PW}" \
    PULSE_RUNTIME_PATH="${PW}/pulse" XDG_CONFIG_HOME="${PW}/cfg" "$@"; }
  PIPEWIRE=
  PULSE=
  start_pulse() {
    pw pipewire-pulse >>"${PW}/pipewire-pulse.log" 2>&1 &
    PULSE=$!
    AUDIO="${PIPEWIRE} ${PULSE}"
    for _ in $(seq 50); do pactl info >/dev/null 2>&1 && break; sleep 0.1; done
  }
  stop_pulse() {
    kill "${PULSE}"
    wait "${PULSE}" 2>/dev/null
    AUDIO="${PIPEWIRE}"
  }
  # A sink at the server's own 100 %, made the default.
  new_sink() {
    pactl load-module module-null-sink sink_name="${1}" >/dev/null
    for _ in $(seq 30); do pactl get-sink-volume "${1}" >/dev/null 2>&1 && break; sleep 0.1; done
    pw timeout 5 pw-metadata -n default 0 default.audio.sink "{ \"name\": \"${1}\" }" >/dev/null
  }
  # Both channels: "-35.00 dB -35.00 dB".
  sink_db() { LC_ALL=C pactl get-sink-volume "${1}" 2>/dev/null | head -n1 | grep -o -- '-*[0-9.]* dB' | tr '\n' ' ' | sed 's/ $//'; }
  sink_is() {
    for _ in $(seq 50); do [ "$(sink_db "${2}")" = "${3}" ] && break; sleep 0.1; done
    check "${1}" "$(sink_db "${2}")" "${3}"
  }
  export PULSE_SERVER="unix:${PW}/pulse/native"

  # The daemon is up before the audio server, as at boot.
  start
  check "level with no audio server" "$(${L} volume 30)" 30
  pw pipewire >"${PW}/pipewire.log" 2>&1 &
  PIPEWIRE=$!
  AUDIO="${PIPEWIRE}"
  for _ in $(seq 50); do [ -S "${PW}/pipewire-0" ] && break; sleep 0.1; done
  start_pulse
  new_sink card
  sink_is "the server comes up later: the level reaches the sink" card "-35.00 dB -35.00 dB"
  ${L} volume 81 >/dev/null
  sink_is "steps reach it" card "-9.50 dB -9.50 dB"

  # The audio server restarts: its sinks come back at 100 %.
  stop_pulse
  start_pulse
  new_sink card
  sink_is "the server restarts: the level comes back" card "-9.50 dB -9.50 dB"

  # Another sink becomes the default (headset, HDMI).
  new_sink other
  sink_is "a new default sink gets the level" other "-9.50 dB -9.50 dB"

  # A sink goes and comes back (a profile switch, a card probed again).
  pactl unload-module module-null-sink
  new_sink card
  sink_is "a sink that comes back gets the level" card "-9.50 dB -9.50 dB"
  stop
  kill ${AUDIO} 2>/dev/null
  wait ${AUDIO} 2>/dev/null
  AUDIO=
  rm -r "${PW}"
fi

[ ${FAILED} -eq 0 ] && echo "archr_levels_test: OK"
exit ${FAILED}
