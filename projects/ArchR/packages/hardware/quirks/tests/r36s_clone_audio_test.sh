#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# The R36S Clone quirk picks the playback mux that reaches the speaker
# from the sound card the overlay enabled (Arch-R#35). On the amplified
# card the amp is fed from HPOL/HPOR, so "SPK" (the class-D) is silence.
#   bash projects/ArchR/packages/hardware/quirks/tests/r36s_clone_audio_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
QUIRK="${HERE}/../devices/R36S Clone/001-device_config"
TMP=$(mktemp -d)
trap 'rm -r "${TMP}"' EXIT
FAILED=0

# A device tree with only ${1} enabled; prints what the quirk configures.
run() {
  local dir
  dir=$(mktemp -d -p "${TMP}")
  mkdir -p "${dir}/out"
  for card in rk817-sound rk817-sound-amplified rk817-sound-simple; do
    mkdir -p "${dir}/dt/${card}"
    printf 'disabled\0' >"${dir}/dt/${card}/status"
  done
  printf 'okay\0' >"${dir}/dt/${1}/status"
  ARCHR_DT="${dir}/dt" ARCHR_PROFILE_DIR="${dir}/out" sh "${QUIRK}" || echo "quirk exited $?"
  (. "${dir}/out/001-device_config" &&
    echo "${DEVICE_PLAYBACK_PATH_SPK} ${DEVICE_PLAYBACK_PATH_HP} ${DEVICE_HEADPHONE_DEV##*/}")
}
check() {
  if [ "${2}" != "${3}" ]; then
    echo "FAIL: ${1}: got '${2}', expected '${3}'"
    FAILED=1
  fi
}

check "amplified card: speaker on the HP lines" "$(run rk817-sound-amplified)" \
  "HP HP platform-rk817-sound-amplified-event"
check "simple card: speaker on the class-D" "$(run rk817-sound-simple)" \
  "SPK HP platform-rk817-sound-simple-event"
check "base card" "$(run rk817-sound)" "SPK HP platform-rk817-sound-event"

[ ${FAILED} -eq 0 ] && echo "r36s_clone_audio_test: OK"
exit ${FAILED}
