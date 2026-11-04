#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for input_sense hotplug: a device that goes away and comes back
# is watched again, and the script never exits (it used to be killed by a
# udev rule on every add/remove and restarted by systemd).
#   bash projects/ArchR/packages/sysutils/system-utils/tests/input_sense_hotplug_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
FUNCTIONS="${PKG}/../../archr/profile.d/001-functions"
SCRIPT="${PKG}/sources/scripts/input_sense"
TMP=$(mktemp -d)
PID=
cleanup() {
  [ -n "${PID}" ] && kill -TERM -- "-${PID}" 2>/dev/null
  rm -rf "${TMP}"
}
trap cleanup EXIT
FAILED=0
mkdir "${TMP}/bin" "${TMP}/input" "${TMP}/scripts"

cat >"${TMP}/profile" <<PROFILE
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
log() { :; }
INPUT_DIR="${TMP}/input"
HOTPLUG_SCAN=0.2
PATH="${TMP}/bin:\${PATH}"
PROFILE
export INPUT_SENSE_PROFILE="${TMP}/profile"
touch "${TMP}/system.cfg"

# event0 is the keys, any other node a joystick; <node>.pending: not
# described by udev yet.
cat >"${TMP}/bin/udevadm" <<'STUB'
#!/bin/bash
[ -e "${2}" ] || exit 1
# A node udev has not processed yet has no ID_INPUT properties.
[ -e "${2}.pending" ] && { echo "E: DEVNAME=${2}"; exit 0; }
echo "E: ID_INPUT=1"
case ${2} in */event0) echo "E: ID_INPUT_KEY=1" ;; *) echo "E: ID_INPUT_JOYSTICK=1" ;; esac
echo "E: DEVNAME=${2}"
STUB
# evtest: logs each start; scripts/<node> is replayed once, then it
# reads until the node goes away ("error reading", as the kernel says).
cat >"${TMP}/bin/evtest" <<STUB
#!/bin/bash
echo "start \${1##*/}" >>"${TMP}/calls"
S="${TMP}/scripts/\${1##*/}"
[ -f "\${S}" ] && cat "\${S}" && rm -f "\${S}"
while [ -e "\${1}" ]; do sleep 0.1; done
echo "error reading: No such device"
exit 1
STUB
printf '#!/bin/sh\necho "mkcontroller" >>"%s/calls"\n' "${TMP}" >"${TMP}/bin/mkcontroller"
printf '#!/bin/sh\necho "$*" >>"%s/calls"\n' "${TMP}" >"${TMP}/bin/archr-levels"
chmod +x "${TMP}/bin/"*

check() {
  if [ "${2}" = "${3}" ]; then
    echo "ok   ${1}"
  else
    echo "FAIL ${1}: got '${2}', want '${3}'"
    FAILED=1
  fi
}
calls() { grep -c "^${1}\$" "${TMP}/calls" 2>/dev/null; }
alive() { kill -0 "${PID}" 2>/dev/null && echo yes || echo no; }
VOLUP="Event: time 1.0, type 1 (EV_KEY), code 115 (KEY_VOLUMEUP), value"

touch "${TMP}/input/event0" "${TMP}/input/event1"
setsid bash "${SCRIPT}" >/dev/null 2>&1 &
PID=$!
sleep 1.5
check "both devices watched" "$(calls 'start event0') $(calls 'start event1')" "1 1"

# The pad goes away: its evtest ends and is not restarted; the script lives.
rm "${TMP}/input/event1"
sleep 1
check "gone: not reopened" "$(calls 'start event1')" 1
check "the script keeps running" "$(alive)" yes

# It comes back, then a new one appears: both are watched, its keys work.
printf '%s 1\n%s 0\n' "${VOLUP}" "${VOLUP}" >"${TMP}/scripts/event1"
touch "${TMP}/input/event1"
sleep 1
touch "${TMP}/input/event2.pending" "${TMP}/input/event2"
sleep 0.6
check "undescribed: not yet" "$(calls 'start event2')" 0
rm "${TMP}/input/event2.pending"
sleep 0.6
check "back: reopened" "$(calls 'start event1')" 2
check "new device watched" "$(calls 'start event2')" 1
check "its keys work" "$(calls 'volume hold up osd')" 1
check "controllers remapped on each change" "$(calls mkcontroller)" 4
check "keys never reopened" "$(calls 'start event0')" 1
check "still running" "$(alive)" yes

exit ${FAILED}
