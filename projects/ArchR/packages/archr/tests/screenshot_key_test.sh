#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the screenshot shortcut's single switch: archr-screenshot has
# no switch of its own (hotkey.screenshot.enabled is input_sense's), and
# post-update folds the old archr.screenshot.enabled into it.
#   bash projects/ArchR/packages/archr/tests/screenshot_key_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
SHOT="${PKG}/../apps/archr-screenshot/sources/archr-screenshot"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

grep -q 'archr\.screenshot\.enabled' "${SHOT}" && fail "the script still reads its own switch"
bash -n "${SHOT}" || fail "archr-screenshot syntax"

# Run the migration block against a scratch system.cfg.
sed -n '/^# screenshot-key-migration$/,/^# end screenshot-key-migration$/p' \
  "${PKG}/sources/post-update" | sed "s#/storage/.config/system/configs/system.cfg#${TMP}/system.cfg#g" >"${TMP}/mig.sh"
[ -s "${TMP}/mig.sh" ] || fail "migration block not found"

run() { printf '%s' "$1" >"${TMP}/system.cfg"; bash "${TMP}/mig.sh"; cat "${TMP}/system.cfg"; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

expect "old on, hotkey off -> on" $'a=1\nhotkey.screenshot.enabled=1' \
  "$(run $'a=1\narchr.screenshot.enabled=1\nhotkey.screenshot.enabled=0\n')"
expect "old on, no hotkey key -> on" $'hotkey.screenshot.enabled=1' \
  "$(run $'archr.screenshot.enabled=1\n')"
expect "old off, hotkey untouched" $'hotkey.screenshot.enabled=0' \
  "$(run $'archr.screenshot.enabled=0\nhotkey.screenshot.enabled=0\n')"
expect "no old key, nothing changes" $'a=1' "$(run $'a=1\n')"

[ ${FAILED} -eq 0 ] && echo "ok   screenshot key"
exit ${FAILED}
