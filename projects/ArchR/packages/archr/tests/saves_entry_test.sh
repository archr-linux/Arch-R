#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for starting a game from a save state (the launcher's Saves
# screen):
#   runemu.sh --entryslot=N|auto  RetroArch -e N, or the automatic state
#   runemu.sh --entrystate=FILE   exported for the standalone start script
#   bash projects/ArchR/packages/archr/tests/saves_entry_test.sh

# Variables set here are read by the code taken from the scripts.
# shellcheck disable=SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
PACKAGES=$(dirname "${PKG}")
RUNEMU="${PKG}/sources/scripts/runemu.sh"
MUPEN="${PACKAGES}/emulators/standalone/mupen64plus-arch/mupen64plus-arch-core/scripts/start_mupen64plus.sh"
FAILED=0
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}

# The parse loop and the validation after it, as runemu.sh runs them.
run_parse() {
  ARGV=("$@")
  ROMNAME="$1"
  GOVERNOR_OVERRIDE="" ENTRYSLOT="" ENTRYSTATE=""
  eval "$(sed -n '/^for ((i = 1;/,/^done/p' "${RUNEMU}")"
  eval "$(sed -n '/^\[\[ "${ENTRYSLOT}" =~/,/^export ARCHR_ENTRY_STATE/p' "${RUNEMU}")"
  echo "${ENTRYSLOT}|${ENTRYSTATE}"
}
state="${TMP}/Super Mario 64 (USA)-635A42C5.st1"
: >"${state}"
check "a slot" '[ "$(run_parse /roms/snes/m.sfc -Psnes --entryslot=3)" = "3|" ]'
check "slot 0" '[ "$(run_parse /roms/snes/m.sfc -Psnes --entryslot=0)" = "0|" ]'
check "the automatic state" '[ "$(run_parse /roms/snes/m.sfc -Psnes --entryslot=auto)" = "auto|" ]'
for bad in abc 1000 -1 '3; reboot' '$(reboot)' '' '3 4'; do
  check "refused slot: ${bad}" '[ "$(run_parse /roms/snes/m.sfc -Psnes "--entryslot=${bad}")" = "|" ]'
done
check "a state file" '[ "$(run_parse /roms/n64/m.z64 -Pn64 "--entrystate=${state}")" = "|${state}" ]'
check "a missing state file" '[ "$(run_parse /roms/n64/m.z64 -Pn64 "--entrystate=${TMP}/none.st1")" = "|" ]'
check "a relative state file" '[ "$(cd "${TMP}" && run_parse /roms/n64/m.z64 -Pn64 "--entrystate=${state##*/}")" = "|" ]'
check "a ROM path that looks like one is not" '[ "$(run_parse "/roms/snes/--entryslot=3.sfc" -Psnes)" = "|" ]'
check "nothing by default" '[ "$(run_parse /roms/snes/m.sfc -Psnes --core=snes9x)" = "|" ]'

# RetroArch: -e N goes on the command line before the content, the slot
# becomes the save slot; "auto" turns autosave on for the run.
retroarch() {
  ENTRYSLOT="$1" AUTOSAVE="" SNAPSHOT=""
  eval "$(sed -n '/^    ENTRYARGS=""/,/^    esac/p' "${RUNEMU}")"
  echo "${ENTRYARGS}|${AUTOSAVE}|${SNAPSHOT}"
}
check "slot 3 loads with -e" '[ "$(retroarch 3)" = "-e 3||3" ]'
check "auto loads with autosave" '[ "$(retroarch auto)" = "|1|" ]'
check "no entry, no change" '[ "$(retroarch "")" = "||" ]'
check "-e sits before the content" \
  'grep -q "^    RUNTHIS=.*--appendconfig \${RETROARCH_APPEND_CONFIG} \${ENTRYARGS} \"\${ROMNAME}\"'"'"'$" "${RUNEMU}"'
check "the state file reaches mupen64plus" \
  'grep -q "ENTRY=(--savestate \"\${ARCHR_ENTRY_STATE}\")" "${MUPEN}" && grep -q "\"\${ENTRY\[@\]}\" \"\${TMP}/\${ROM}\"$" "${MUPEN}"'

for script in "${RUNEMU}" "${MUPEN}"; do
  bash -n "${script}" && echo "ok   ${script##*/} parses" || { echo "FAIL ${script##*/} syntax"; FAILED=1; }
done
exit ${FAILED}
