#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# archr-savesync between two scratch consoles (A and B) and one shared folder:
# first upload, download on the other, a change travelling back, a conflict
# and both ways of resolving it, states only when asked, nothing deleted.
# Needs rclone and python3 (a console has both):
#   bash tests/savesync_test.sh [path/to/archr-savesync]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=${1:-${HERE}/../sources/scripts/archr-savesync}
command -v rclone >/dev/null || { echo "skip savesync: no rclone"; exit 0; }
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }
export ARCHR_SAVESYNC_REMOTE="${TMP}/pc/SaveSync" ARCHR_SAVESYNC_LOCK="${TMP}/lock"
mkdir -p "${TMP}/pc/SaveSync"
for c in A B; do
  mkdir -p "${TMP}/${c}/storage/.config/system/configs" "${TMP}/${c}/storage/roms/gba" \
    "${TMP}/${c}/storage/roms/savestates/gba" "${TMP}/${c}/storage/roms/bios"
  printf 'savesync.enabled=1\nsavesync.on_exit=1\n' >"${TMP}/${c}/storage/.config/system/configs/system.cfg"
done
on() { ARCHR_SAVESYNC_ROOT="${TMP}/$1" python3 -I "${TOOL}" "${@:2}"; }
# field PATH...: the values at dotted paths of the JSON on stdin, space
# separated; a path starting with # gives the length.
field() {
  python3 -I -c '
import json, sys
v = json.load(sys.stdin)
def at(path):
    n = path.startswith("#")
    x = v
    for p in path.lstrip("#").split("."):
        x = x[int(p)] if isinstance(x, list) else x[p]
    return len(x) if n else x
print(" ".join(str(at(p)) for p in sys.argv[1:]))' "$@"
}
age() { touch -d "@$(( $(date +%s) - $2 ))" "$1"; }
SAVE=storage/roms/gba/Emerald.srm

# A's save goes up; the BIOS and a state stay home (states are off).
printf 'a1' >"${TMP}/A/${SAVE}"; age "${TMP}/A/${SAVE}" 300
printf 'bios' >"${TMP}/A/storage/roms/bios/gba_bios.sav"
printf 'st' >"${TMP}/A/storage/roms/savestates/gba/Emerald.state"
r=$(on A sync)
expect "first upload" "1" "$(echo "$r" | field up)"
expect "uploaded" "a1" "$(cat "${TMP}/pc/SaveSync/saves/gba/Emerald.srm")"
[ -e "${TMP}/pc/SaveSync/saves/bios" ] && fail "bios folder synced"
[ -e "${TMP}/pc/SaveSync/savestates" ] && fail "states synced while off"
expect "status last" "True" "$(on A status | field last.ok)"

# B gets it; a second sync of either moves nothing.
r=$(on B sync)
expect "download" "1" "$(echo "$r" | field down)"
expect "downloaded" "a1" "$(cat "${TMP}/B/${SAVE}")"
expect "quiet A" "0 0" "$(on A sync | field up down)"
expect "quiet B" "0 0" "$(on B sync | field up down)"

# B plays: the change travels to A, whose old copy is kept aside.
printf 'b2' >"${TMP}/B/${SAVE}"; age "${TMP}/B/${SAVE}" 100
expect "b up" "1" "$(on B sync --system gba --exit | field up)"
expect "a down" "1" "$(on A sync | field down)"
expect "a has b2" "b2" "$(cat "${TMP}/A/${SAVE}")"
expect "a kept a1" "a1" "$(cat "${TMP}/A/storage/.config/archr/savesync/anterior/saves/gba/Emerald.srm")"

# Both play before syncing: B first, then A finds a conflict and keeps its own.
printf 'b3' >"${TMP}/B/${SAVE}"; age "${TMP}/B/${SAVE}" 50
printf 'a3' >"${TMP}/A/${SAVE}"; age "${TMP}/A/${SAVE}" 40
on B sync >/dev/null
r=$(on A sync)
expect "conflict seen" "1" "$(echo "$r" | field conflicts)"
expect "nothing overwritten" "a3 b3" "$(cat "${TMP}/A/${SAVE}") $(cat "${TMP}/pc/SaveSync/saves/gba/Emerald.srm")"
expect "listed" "saves/gba/Emerald.srm" "$(on A status | field conflicts.0.key)"
expect "still a conflict" "1" "$(on A sync | field conflicts)"
on A resolve saves/gba/Emerald.srm local >/dev/null
expect "kept local" "a3" "$(cat "${TMP}/pc/SaveSync/saves/gba/Emerald.srm")"
expect "pc copy aside" "b3" "$(cat "${TMP}/pc/SaveSync/conflitos/saves/gba/Emerald"-*.srm)"
expect "no conflicts" "0" "$(on A status | field '#conflicts')"
expect "b follows" "a3" "$(on B sync >/dev/null; cat "${TMP}/B/${SAVE}")"

# Again, and this time A takes the PC's copy; its own goes aside.
rm -rf "${TMP}/pc/SaveSync/conflitos"
printf 'b4' >"${TMP}/B/${SAVE}"; age "${TMP}/B/${SAVE}" 20
printf 'a4' >"${TMP}/A/${SAVE}"; age "${TMP}/A/${SAVE}" 10
on B sync >/dev/null; on A sync >/dev/null
on A resolve saves/gba/Emerald.srm remote >/dev/null
expect "took remote" "b4" "$(cat "${TMP}/A/${SAVE}")"
expect "local aside" "a4" "$(cat "${TMP}/pc/SaveSync/conflitos/saves/gba/Emerald"-*.srm)"
expect "settled" "0 0 0" "$(on A sync | field up down conflicts)"

# The same bytes on both sides with no history agree without a conflict.
printf 'same' >"${TMP}/A/storage/roms/gba/Ruby.srm"
mkdir -p "${TMP}/pc/SaveSync/saves/gba"; printf 'same' >"${TMP}/pc/SaveSync/saves/gba/Ruby.srm"
expect "agree" "0" "$(on A sync | field conflicts)"

# States travel once asked; a deleted local save comes back, never deleted.
echo 'savesync.states=1' >>"${TMP}/A/storage/.config/system/configs/system.cfg"
on A sync >/dev/null
expect "state up" "st" "$(cat "${TMP}/pc/SaveSync/savestates/gba/Emerald.state")"
rm "${TMP}/A/storage/roms/gba/Ruby.srm"
on A sync >/dev/null
expect "restored" "same" "$(cat "${TMP}/A/storage/roms/gba/Ruby.srm")"
expect "pc kept" "same" "$(cat "${TMP}/pc/SaveSync/saves/gba/Ruby.srm")"

# Off, or off after games: nothing runs.
sed -i 's/^savesync.on_exit=1/savesync.on_exit=0/' "${TMP}/B/storage/.config/system/configs/system.cfg"
expect "exit off" "disabled" "$(on B sync --exit | field error)"
sed -i 's/^savesync.enabled=1/savesync.enabled=0/' "${TMP}/B/storage/.config/system/configs/system.cfg"
expect "disabled" "disabled" "$(on B sync | field error)"

# A share with no address is named, and the last sync says so.
unset ARCHR_SAVESYNC_REMOTE
expect "no address" "not_configured" "$(on A sync | field error)"
expect "last error" "not_configured" "$(on A status | field last.error)"
echo 'savesync.smb.address=PC' >>"${TMP}/A/storage/.config/system/configs/system.cfg"
expect "bad address" "bad_address" "$(on A test | field error)"

[ ${FAILED} -eq 0 ] && echo "ok   archr-savesync"
exit ${FAILED}
