#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for starting a game from a save state (the launcher's Saves
# screen) and for the screenshot shortcut's file name:
#   runemu.sh --entryslot=N|auto  RetroArch -e N, or the automatic state
#   runemu.sh --entrystate=FILE   exported for the standalone start script
#   archr-screenshot              <rom>-AAMMDD-HHMMSS.png while a game runs
#   bash projects/ArchR/packages/archr/tests/saves_entry_test.sh

# Variables set here are read by the code taken from the scripts.
# shellcheck disable=SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
PACKAGES=$(dirname "${PKG}")
RUNEMU="${PKG}/sources/scripts/runemu.sh"
SHOT="${PACKAGES}/apps/archr-screenshot/sources/archr-screenshot"
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

# The running game is recorded for the screenshot shortcut and forgotten
# when runemu.sh quits.
check "the game and the PID are recorded" 'grep -q "printf '"'"'%s\\\\n%s\\\\n'"'"' \"\${ROMNAME}\" \"\$\$\" >\"\${CURRENT_GAME}\"" "${RUNEMU}"'
check "and forgotten on quit" \
  '[ "$(sed -n "/^function quit() {/,/^}/p" "${RUNEMU}" | grep -c "rm -f \"\${CURRENT_GAME}\"")" = 1 ]'

# archr-screenshot: the file name.
eval "$(sed -n '/^CURRENT_GAME=/p;/^screenshot_name() {/,/^}/p' "${SHOT}")"
name() {
  if [ -n "$1" ]; then printf '%s\n%s\n' "$1" "${2-$$}" >"${TMP}/current"; else rm -f "${TMP}/current"; fi
  ARCHR_CURRENT_GAME="${TMP}/current"
  CURRENT_GAME="${ARCHR_CURRENT_GAME}"
  screenshot_name
}
check "the game's name, as RetroArch names it" \
  '[[ "$(name "/storage/roms/snes/Super Mario World (USA).sfc")" =~ ^Super\ Mario\ World\ \(USA\)-[0-9]{6}-[0-9]{6}\.png$ ]]'
check "a zipped ROM" '[[ "$(name "/storage/roms/snes/F-Zero.zip")" =~ ^F-Zero-[0-9]{6}-[0-9]{6}\.png$ ]]'
check "only the last extension goes" '[[ "$(name "/storage/roms/psx/Game v1.1.chd")" =~ ^Game\ v1\.1-[0-9]{6}-[0-9]{6}\.png$ ]]'
check "characters exFAT refuses" '[[ "$(name "/storage/roms/x/a:b?c*d\"e<f>g|h\\i.bin")" =~ ^a_b_c_d_e_f_g_h_i-[0-9]{6}-[0-9]{6}\.png$ ]]'
check "a game whose runemu.sh is gone: the date" '[[ "$(name "/storage/roms/snes/F-Zero.sfc" 999999999)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.png$ ]]'
check "a record without a PID: the date" '[[ "$(name "/storage/roms/snes/F-Zero.sfc" "")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.png$ ]]'
check "no game: the date" '[[ "$(name "")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.png$ ]]'

for script in "${RUNEMU}" "${SHOT}" "${MUPEN}"; do
  bash -n "${script}" && echo "ok   ${script##*/} parses" || { echo "FAIL ${script##*/} syntax"; FAILED=1; }
done
exit ${FAILED}
