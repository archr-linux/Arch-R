#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the screenshot shortcut (also while RetroArch runs) and its single switch: archr-screenshot has
# no switch of its own (hotkey.screenshot.enabled is input_sense's), and
# post-update folds the old archr.screenshot.enabled into it.
#   bash projects/ArchR/packages/archr/tests/screenshot_key_test.sh

# shellcheck disable=SC2016 # the stand-ins expand their variables when they run
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
SHOT="${PKG}/../apps/archr-screenshot/sources/archr-screenshot"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

grep -q 'archr\.screenshot\.enabled' "${SHOT}" && fail "the script still reads its own switch"
bash -n "${SHOT}" || fail "archr-screenshot syntax"

# RetroArch gets its capture like any other emulator: with retroarch running
# (a stand-in pgrep says so) the script still captures, into the same folder,
# named after the game as RetroArch names its own files.
grep -q 'pgrep' "${SHOT}" && fail "the script still looks for retroarch"
mkdir -p "${TMP}/bin" "${TMP}/shots"
printf '#!/bin/sh\necho "$*" >>"%s/grim.args"\n[ -e "%s/grim-fails" ] || for f; do :; done; [ -e "%s/grim-fails" ] || echo png >"$f"\n' \
  "${TMP}" "${TMP}" "${TMP}" >"${TMP}/bin/grim"
printf '#!/bin/sh\necho "$SWAY_TREE"\n' >"${TMP}/bin/swaymsg"
printf '#!/bin/sh\nexit 0\n' >"${TMP}/bin/pgrep"
chmod +x "${TMP}/bin/"*
: >"${TMP}/profile"
printf '/roms/snes/Super Game: (USA).sfc\n%s\n' "$$" >"${TMP}/current-game"
shot() {
  rm -f "${TMP}/shots/"* "${TMP}/grim.args"
  PATH="${TMP}/bin:${PATH}" ARCHR_SCREENSHOT_PROFILE="${TMP}/profile" ARCHR_SCREENSHOT_DIR="${TMP}/shots" \
    ARCHR_CURRENT_GAME="${TMP}/current-game" SWAY_TREE="$1" bash "${SHOT}"
}
FOCUSED='{"type":"con","focused":true,"rect":{"x":0,"y":0,"width":640,"height":480}}'
shot "${FOCUSED}"; rc=$?
expect "capture with retroarch running: exit" 0 "${rc}"
[[ "$(cd "${TMP}/shots" && echo *)" =~ ^Super\ Game_\ \(USA\)-[0-9]{6}-[0-9]{6}\.png$ ]] || fail "name is not <rom>-AAMMDD-HHMMSS.png: $(ls "${TMP}/shots")"
grep -q -- '-g 0,0 640x480' "${TMP}/grim.args" || fail "grim not given the focused window"
shot '{"type":"con","focused":false,"rect":{"x":0,"y":0,"width":1,"height":1}}'; rc=$?
expect "no focused window: whole output, exit" 0 "${rc}"
grep -q -- '-g' "${TMP}/grim.args" && fail "no focus should capture the whole output"
touch "${TMP}/grim-fails"; shot "${FOCUSED}"; rc=$?
expect "grim fails: exit 1" 1 "${rc}"
[ -z "$(ls "${TMP}/shots")" ] || fail "a failed capture left a file"
rm -f "${TMP}/grim-fails"

# Run the migration block against a scratch system.cfg.
sed -n '/^# screenshot-key-migration$/,/^# end screenshot-key-migration$/p' \
  "${PKG}/sources/post-update" | sed "s#/storage/.config/system/configs/system.cfg#${TMP}/system.cfg#g" >"${TMP}/mig.sh"
[ -s "${TMP}/mig.sh" ] || fail "migration block not found"

run() { printf '%s' "$1" >"${TMP}/system.cfg"; bash "${TMP}/mig.sh"; cat "${TMP}/system.cfg"; }

expect "old on, hotkey off -> on" $'a=1\nhotkey.screenshot.enabled=1' \
  "$(run $'a=1\narchr.screenshot.enabled=1\nhotkey.screenshot.enabled=0\n')"
expect "old on, no hotkey key -> on" $'hotkey.screenshot.enabled=1' \
  "$(run $'archr.screenshot.enabled=1\n')"
expect "old off, hotkey untouched" $'hotkey.screenshot.enabled=0' \
  "$(run $'archr.screenshot.enabled=0\nhotkey.screenshot.enabled=0\n')"
expect "no old key, nothing changes" $'a=1' "$(run $'a=1\n')"

[ ${FAILED} -eq 0 ] && echo "ok   screenshot key"
exit ${FAILED}
