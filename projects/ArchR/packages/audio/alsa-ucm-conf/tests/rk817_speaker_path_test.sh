#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# The rk817 UCM profile picks the Playback Mux position of the speaker
# per board. Where the speaker hangs off the headphone lines it must be
# "HP": "SPK" there is the unwired class-D, and every time the UCM
# enables the speaker (a profile switch, a sink created again, headphones
# unplugged) it would silence it.
#
# Unpacks the packaged alsa-ucm-conf, applies the RK3326 patches, and asks
# alsaucm (host alsa-lib, a virtual card, a fake sysfs) what the shipped
# speaker-path.conf decides for each device tree model. A sound card with
# the rk817 controls cannot be faked on the host, so HiFi.conf itself is
# checked statically: it includes that file after the default and its
# Speaker sequence writes the variable.
#   bash projects/ArchR/packages/audio/alsa-ucm-conf/tests/rk817_speaker_path_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG="$(dirname "${HERE}")"
ROOT="$(cd "${PKG}/../../../../.." && pwd)"
QUIRKS="${PKG}/../../hardware/quirks/devices"
. <(grep -E '^PKG_VERSION=' "${PKG}/package.mk")
TARBALL="${ARCHR_SOURCES:-${ROOT}/sources}/alsa-ucm-conf/alsa-ucm-conf-${PKG_VERSION}.tar.bz2"
TMP=$(mktemp -d)
trap 'rm -r "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

command -v alsaucm >/dev/null || { echo "FAIL: alsaucm (alsa-utils) is needed"; exit 1; }
[ -f "${TARBALL}" ] || { echo "FAIL: ${TARBALL} missing (scripts/get alsa-ucm-conf)"; exit 1; }

tar xjf "${TARBALL}" -C "${TMP}" || { echo "FAIL: cannot unpack ${TARBALL}"; exit 1; }
SRC="${TMP}/alsa-ucm-conf-${PKG_VERSION}"
for p in "${PKG}"/patches/RK3326/*.patch; do
  patch -d "${SRC}" -p1 -s <"${p}" || fail "${p##*/} does not apply"
done
UCM="${SRC}/ucm2"
RK="${UCM}/Rockchip/rk817-sound"

# The virtual card defines the same default as HiFi.conf, includes the
# shipped decision file and shows the result as a Speaker value.
mkdir -p "${UCM}/conf.virt.d" "${UCM}/archr-test"
cat >"${UCM}/conf.virt.d/archr-rk817-test.conf" <<'EOF'
Syntax 4
Define.pbk_mux "SPK"
Include.archr_speaker_path.File "/Rockchip/rk817-sound/speaker-path.conf"
SectionUseCase."HiFi" {
	File "/archr-test/HiFi.conf"
	Comment "speaker path test"
}
EOF
cat >"${UCM}/archr-test/HiFi.conf" <<'EOF'
SectionDevice."Speaker" {
	Value {
		ArchrSpeakerMux "${var:pbk_mux}"
	}
}
EOF

mux_for() {
  local sys="${TMP}/sys-${RANDOM}"
  mkdir -p "${sys}/firmware/devicetree/base"
  [ -n "${1}" ] && printf '%s\0' "${1}" >"${sys}/firmware/devicetree/base/model"
  ALSA_CONFIG_UCM2="${UCM}" SYSFS_PATH="${sys}" timeout 10 \
    alsaucm -c archr-rk817-test set _verb HiFi get ArchrSpeakerMux/Speaker 2>&1 |
    sed -n 's/^ *ArchrSpeakerMux\/Speaker=//p'
}

# Every rk817 quirk states where its speaker is; the UCM must agree.
checked=0
for cfg in "${QUIRKS}"/*/001-device_config; do
  model=$(basename "$(dirname "${cfg}")")
  want=$(sed -n 's/^DEVICE_PLAYBACK_PATH_SPK="\(HP\|SPK\)"$/\1/p' "${cfg}")
  [ -n "${want}" ] || continue
  got=$(mux_for "${model}")
  [ "${got}" = "${want}" ] || fail "${model}: UCM speaker mux '${got}', quirk says '${want}'"
  checked=$((checked + 1))
done
[ "${checked}" -ge 10 ] || fail "only ${checked} quirks compared"

# Exact names only: a longer model is another board.
got=$(mux_for "Game Console R36S Soysauce")
[ "${got}" = "SPK" ] || fail "Soysauce: '${got}', expected SPK (its codec routes SPK to the external amp)"
got=$(mux_for "R36S Clone")
[ "${got}" = "SPK" ] || fail "R36S Clone: '${got}', expected the default (its card has the Internal Speakers Switch)"
got=$(mux_for "")
[ "${got}" = "SPK" ] || fail "no device tree model: '${got}', expected SPK"

# HiFi.conf: the include comes after the default and before the cards
# with an Internal Speakers Switch, and the speaker writes the variable.
first_define=$(grep -n '^Define.pbk_mux "SPK"' "${RK}/HiFi.conf" | cut -d: -f1)
include=$(grep -n '^Include.archr_speaker_path.File "/Rockchip/rk817-sound/speaker-path.conf"' "${RK}/HiFi.conf" | cut -d: -f1)
switch_if=$(grep -n "Internal Speakers Switch" "${RK}/HiFi.conf" | head -n1 | cut -d: -f1)
if [ -z "${first_define}" ] || [ -z "${include}" ] || [ -z "${switch_if}" ] ||
  [ "${include}" -le "${first_define}" ] || [ "${include}" -ge "${switch_if}" ]; then
  fail "HiFi.conf does not include speaker-path.conf between the default and the switch block"
fi
sed -n '/^SectionDevice."Speaker" {/,/^}/p' "${RK}/HiFi.conf" |
  grep -q "cset \"name='Playback Mux' \${var:pbk_mux}\"" ||
  fail "the Speaker EnableSequence no longer writes \${var:pbk_mux}"

[ ${FAILED} -eq 0 ] && echo "rk817_speaker_path_test: OK (${checked} quirks)"
exit ${FAILED}
