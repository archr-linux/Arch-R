#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the input_sense inactivity suspend: runs the real script with
# stub udevadm/evtest, a temporary system.cfg and minutes shortened to seconds.
#   bash projects/ArchR/packages/sysutils/system-utils/tests/input_sense_idle_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
FUNCTIONS="${PKG}/../../archr/profile.d/001-functions"
SCRIPT="${PKG}/sources/scripts/input_sense"
TMP=$(mktemp -d)
GAME=
cleanup() {
  [ -n "${GAME}" ] && kill "${GAME}" 2>/dev/null
  rm -rf "${TMP}"
}
trap cleanup EXIT
FAILED=0
mkdir "${TMP}/bin"

cat >"${TMP}/profile" <<PROFILE
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
log() { :; }
FAKE_SUSPEND="${TMP}/bin/suspend"
FAKE_SUSPEND_FLAG="${TMP}/suspended.flag"
IDLE_UNIT=1
PATH="${TMP}/bin:\${PATH}"
PROFILE
export INPUT_SENSE_PROFILE="${TMP}/profile"

# The first device asked about is the keys, every other one a joystick.
cat >"${TMP}/bin/udevadm" <<STUB
#!/bin/bash
if mkdir "${TMP}/udev.first" 2>/dev/null; then
  echo "E: ID_INPUT_KEY=1"
else
  echo "E: ID_INPUT_JOYSTICK=1"
fi
echo "E: DEVNAME=\${2}"
STUB
# One evtest replays the scenario ("seconds line" per row); the rest idle.
cat >"${TMP}/bin/evtest" <<STUB
#!/bin/bash
if mkdir "${TMP}/evtest.first" 2>/dev/null; then
  while read -r DELAY LINE; do
    sleep "\${DELAY}"
    echo "\${LINE}"
  done <"${TMP}/events"
fi
exec sleep 600
STUB
printf '#!/bin/sh\necho "$*" >>"%s/calls"\n' "${TMP}" >"${TMP}/bin/suspend"
printf '#!/bin/sh\nexit 0\n' >"${TMP}/bin/mkcontroller"
chmod +x "${TMP}/bin/"*

PRESS="Event: time 1.0, type 1 (EV_KEY), code 304 (BTN_SOUTH), value 1"
POWER="Event: time 1.0, type 1 (EV_KEY), code 116 (KEY_POWER), value 1"

# run SECONDS CONFIG... : input_sense for that long; prints the suspend calls.
run() {
  local LENGTH=${1}
  shift
  printf '%s\n' "$@" >"${TMP}/system.cfg"
  rm -rf "${TMP}/calls" "${TMP}/udev.first" "${TMP}/evtest.first"
  touch "${TMP}/calls"
  setsid bash "${SCRIPT}" >/dev/null 2>&1 &
  local PID=$!
  sleep "${LENGTH}"
  kill -TERM -- "-${PID}" 2>/dev/null
  wait "${PID}" 2>/dev/null
  sleep 0.2
  tr '\n' ' ' <"${TMP}/calls" | sed 's/ $//'
}
events() { printf '%s\n' "$@" >"${TMP}/events"; }
check() {
  if [ "${2}" = "${3}" ]; then
    echo "ok   ${1}"
  else
    echo "FAIL ${1}: got '${2}', want '${3}'"
    FAILED=1
  fi
}

events
check "never by default" "$(run 3 "system.loglevel=none")" ""
check "0 is never" "$(run 3 "idle.timeout=0")" ""
check "suspends once the menu limit passes" "$(run 3 "idle.timeout=2")" "power"
check "counts again after suspending" "$(run 5 "idle.timeout=2")" "power power"
check "malformed limits are never" "$(run 3 "idle.timeout=2min" "idle.timeout.game=-1")" ""

events "1 ${PRESS}" "1 ${PRESS}" "1 ${PRESS}" "1 ${PRESS}"
check "any key restarts the count" "$(run 5 "idle.timeout=2")" ""
check "then suspends after the last key" "$(run 7 "idle.timeout=2")" "power"

events
touch "${TMP}/suspended.flag"
check "already suspended: no second suspend" "$(run 3 "idle.timeout=1")" ""
rm -f "${TMP}/suspended.flag"

bash -c 'exec -a /usr/bin/runemu.sh sleep 60' &
GAME=$!
sleep 0.2
check "a game uses its own limit, never" "$(run 3 "idle.timeout=1")" ""
check "a game uses its own limit" "$(run 3 "idle.timeout=0" "idle.timeout.game=2")" "power"
kill "${GAME}"
wait "${GAME}" 2>/dev/null
GAME=
check "the game limit does not apply in the menu" "$(run 3 "idle.timeout.game=1")" ""

events "0.5 ${POWER}"
check "the power button keeps its suspend" "$(run 2)" "power"

exit ${FAILED}
