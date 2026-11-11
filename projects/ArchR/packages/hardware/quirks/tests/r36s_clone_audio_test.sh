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

# A device tree: each argument is card=status, status "-" for none (on),
# "stub" for a node with a status but no compatible (what an overlay
# leaves when it disables a card the base does not have). Prints what the
# quirk configures, then what it logged.
run() {
  local dir arg card status
  dir=$(mktemp -d -p "${TMP}")
  mkdir -p "${dir}/out" "${dir}/dt"
  for arg in "$@"; do
    card=${arg%%=*} status=${arg#*=}
    mkdir -p "${dir}/dt/${card}"
    if [ "${status}" = stub ]; then
      printf 'disabled\0' >"${dir}/dt/${card}/status"
      continue
    fi
    printf 'simple-audio-card\0' >"${dir}/dt/${card}/compatible"
    [ "${status}" = - ] || printf '%s\0' "${status}" >"${dir}/dt/${card}/status"
  done
  ARCHR_DT="${dir}/dt" ARCHR_PROFILE_DIR="${dir}/out" sh "${QUIRK}" 2>"${dir}/log" || echo "quirk exited $?"
  (. "${dir}/out/001-device_config" &&
    echo "${DEVICE_PLAYBACK_PATH_SPK} ${DEVICE_PLAYBACK_PATH_HP} ${DEVICE_HEADPHONE_DEV##*/} ${DEVICE_HEADPHONE_INSERTED} [${DEVICE_SPEAKER_SWITCH}]")
  [ -s "${dir}/log" ] && echo "log: $(cat "${dir}/log")"
}
check() {
  if [ "${2}" != "${3}" ]; then
    echo "FAIL: ${1}: got '${2}', expected '${3}'"
    FAILED=1
  fi
}

AMP="HP HP platform-rk817-sound-amplified-event 0 []"
SIMPLE="SPK HP platform-rk817-sound-simple-event 0 []"
BASE="SPK HP platform-rk817-sound-event 0 []"

check "amplified card: speaker on the HP lines" \
  "$(run rk817-sound=stub rk817-sound-amplified=okay rk817-sound-simple=disabled)" "${AMP}"
check "simple card: speaker on the class-D" \
  "$(run rk817-sound=stub rk817-sound-amplified=disabled rk817-sound-simple=okay)" "${SIMPLE}"
check "base card" \
  "$(run rk817-sound=okay rk817-sound-amplified=disabled rk817-sound-simple=disabled)" "${BASE}"
check "no status means on" \
  "$(run rk817-sound=stub rk817-sound-amplified=- rk817-sound-simple=disabled)" "${AMP}"
check "\"ok\" means on" \
  "$(run rk817-sound-amplified=disabled rk817-sound-simple=ok)" "${SIMPLE}"
check "a disabled stub is not a card" \
  "$(run rk817-sound=stub rk817-sound-simple=okay)" "${SIMPLE}"
check "two cards on: the amplified one, logged" \
  "$(run rk817-sound=okay rk817-sound-amplified=okay)" \
  "$(printf '%s\nlog: %s' "${AMP}" "R36S Clone audio: sound cards on: rk817-sound-amplified rk817-sound; using rk817-sound-amplified")"
check "no card on: SPK, logged" \
  "$(run rk817-sound=stub rk817-sound-amplified=disabled)" \
  "$(printf '%s\nlog: %s' "${BASE}" "R36S Clone audio: no rk817 sound card on; speaker path left at SPK")"

[ ${FAILED} -eq 0 ] && echo "r36s_clone_audio_test: OK"
exit ${FAILED}
