#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# headphone_sense moves the playback mux on jack events and records where
# the sound goes in audio.device, only once the mixer took the change: a
# refused amixer leaves audio.device as it was and says why. Runs the
# script with stub amixer/evtest and a stub profile.
#   bash projects/ArchR/packages/sysutils/system-utils/tests/headphone_sense_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/headphone_sense"
TMP=$(mktemp -d)
trap 'rm -r "${TMP}"' EXIT
FAILED=0

mkdir -p "${TMP}/bin"
# amixer: logs its arguments; refuses when ${TMP}/refuse names the value.
cat >"${TMP}/bin/amixer" <<EOF
#!/bin/sh
echo "amixer \$*" >>"${TMP}/calls"
for v; do :; done
[ -f "${TMP}/refuse" ] && [ "\$(cat "${TMP}/refuse")" = "\${v}" ] && { echo "amixer: Invalid value" >&2; exit 1; }
exit 0
EOF
# evtest: --query answers from ${TMP}/plugged (0 = bit set, i.e. the
# inverted switch says headphones); streaming replays ${TMP}/events.
cat >"${TMP}/bin/evtest" <<EOF
#!/bin/sh
if [ "\${1}" = --query ]; then exit "\$(cat "${TMP}/plugged")"; fi
cat "${TMP}/events"
EOF
chmod +x "${TMP}/bin/amixer" "${TMP}/bin/evtest"
touch "${TMP}/jack"
cat >"${TMP}/profile" <<EOF
PATH="${TMP}/bin:\${PATH}"
DEVICE_PLAYBACK_PATH="Playback Mux"
DEVICE_PLAYBACK_PATH_SPK="HP"
DEVICE_PLAYBACK_PATH_HP="HP"
DEVICE_HEADPHONE_DEV="${TMP}/jack"
set_setting() { echo "set \$1=\$2" >>"${TMP}/calls"; }
volume() { echo "volume \$*" >>"${TMP}/calls"; }
EOF

ON='Event: time 1.0, type 5 (EV_SW), code 2 (SW_HEADPHONE_INSERT), value 0'
OFF='Event: time 2.0, type 5 (EV_SW), code 2 (SW_HEADPHONE_INSERT), value 1'

# $1: SPK path, $2: HP path, $3: query exit code, $4: value amixer refuses.
run() {
  : >"${TMP}/calls"
  printf '%s\n%s\n' "${ON}" "${OFF}" >"${TMP}/events"
  echo "${3}" >"${TMP}/plugged"
  rm -f "${TMP}/refuse"
  [ -n "${4}" ] && echo "${4}" >"${TMP}/refuse"
  sed -i "s/^DEVICE_PLAYBACK_PATH_SPK=.*/DEVICE_PLAYBACK_PATH_SPK=\"${1}\"/; s/^DEVICE_PLAYBACK_PATH_HP=.*/DEVICE_PLAYBACK_PATH_HP=\"${2}\"/" "${TMP}/profile"
  ARCHR_PROFILE="${TMP}/profile" bash "${SCRIPT}" 2>"${TMP}/err"
  cat "${TMP}/calls"
}
check() {
  if [ "${2}" != "${3}" ]; then
    printf 'FAIL: %s:\n--- got\n%s\n--- expected\n%s\n' "${1}" "${2}" "${3}"
    FAILED=1
  fi
}
cset() { echo "amixer -c 0 cset name=Playback Mux ${1}"; }

# Unplugged at boot, then plugged and unplugged: every move recorded.
check "all accepted" "$(run SPK HP 10 '')" "$(printf '%s\n' \
  "$(cset SPK)" "set audio.device=speakers" "volume restore" \
  "$(cset HP)" "set audio.device=headphone" \
  "$(cset SPK)" "set audio.device=speakers")"

# The mixer refuses the speaker position: nothing recorded for it, at
# boot or on unplug, and the error is logged; headphones still recorded.
check "speaker refused" "$(run BAD HP 10 BAD)" "$(printf '%s\n' \
  "$(cset BAD)" "volume restore" \
  "$(cset HP)" "set audio.device=headphone" \
  "$(cset BAD)")"
grep -q "could not set 'Playback Mux' to 'BAD' for speakers" "${TMP}/err" ||
  { echo "FAIL: refusal not logged: $(cat "${TMP}/err")"; FAILED=1; }

# Plugged at boot and the headphone position refused.
check "boot on headphones refused" "$(run SPK BAD 0 BAD)" "$(printf '%s\n' \
  "$(cset BAD)" "volume restore" \
  "$(cset BAD)" \
  "$(cset SPK)" "set audio.device=speakers")"

# Amplified R36S Clone: speaker on the headphone lines, gated by a pin
# switch, jack the right way round (1 = headphones in). The mux stays on
# HP; the gate goes off for headphones and back on for the speaker.
cat >>"${TMP}/profile" <<EOF
DEVICE_SPEAKER_SWITCH="Internal Speakers Switch"
DEVICE_HEADPHONE_INSERTED="1"
EOF
gate() { echo "amixer -c 0 cset name=Internal Speakers Switch ${1}"; }
# Here value 1 comes first (in), then 0 (out).
ON='Event: time 1.0, type 5 (EV_SW), code 2 (SW_HEADPHONE_INSERT), value 1'
OFF='Event: time 2.0, type 5 (EV_SW), code 2 (SW_HEADPHONE_INSERT), value 0'

# Unplugged at boot (bit clear), then in and out.
check "amp: speaker gate follows the jack" "$(run HP HP 0 '')" "$(printf '%s\n' \
  "$(cset HP)" "$(gate on)" "set audio.device=speakers" "volume restore" \
  "$(cset HP)" "$(gate off)" "set audio.device=headphone" \
  "$(cset HP)" "$(gate on)" "set audio.device=speakers")"

# Plugged at boot (bit set): starts on headphones, speaker gated off.
check "amp: boot with headphones in" "$(run HP HP 10 '' | head -3)" "$(printf '%s\n' \
  "$(cset HP)" "$(gate off)" "set audio.device=headphone")"

# The gate refused: audio.device not recorded, the reason logged.
check "amp: gate refused" "$(run HP HP 0 off | sed -n 4,6p)" "$(printf '%s\n' \
  "volume restore" "$(cset HP)" "$(gate off)")"
grep -q "could not set 'Internal Speakers Switch' to 'off' for headphone" "${TMP}/err" ||
  { echo "FAIL: gate refusal not logged: $(cat "${TMP}/err")"; FAILED=1; }

[ ${FAILED} -eq 0 ] && echo "headphone_sense_test: OK"
exit ${FAILED}
