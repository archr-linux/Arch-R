#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for runemu.sh disc_from_archive: a flycast disc kept in a .zip
# or .7z is extracted once and handed over under the archive's name. Most
# archives already name the disc after themselves (Hero.zip holding
# Hero.chd), which mv onto itself used to fail, handing flycast the
# archive again. Real archives, made with the 7za given (the toolchain's
# by default).
#   bash projects/ArchR/packages/archr/tests/runemu_disc_archive_test.sh [7za]

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
RUNEMU="${PKG}/sources/scripts/runemu.sh"
SEVENZIP=${1:-$(cd "${PKG}/../../../.." && pwd)/build.ArchR-RK3326.aarch64/toolchain/bin/7za}
if [ ! -x "${SEVENZIP}" ]; then
  echo "SKIP no 7za at ${SEVENZIP}"
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
if bash -n "${RUNEMU}"; then echo "ok   bash -n"; else echo "FAIL bash -n"; FAILED=1; fi

eval "$(sed -n '/^disc_card() {/,/^}/p; /^disc_from_archive() {/,/^}/p' "${RUNEMU}")"
log() { :; }

# check <name> <archive> <expected game file, relative to the cache, or ROM>
check() {
  local rom=$2 want=$3 got
  PLATFORM=atomiswave ROMNAME=$rom BASEROMNAME=${rom##*/} GAME_FILE=$rom DISC_CACHE=${TMP}/cache
  disc_from_archive
  got=${GAME_FILE#"${TMP}"/cache/}
  [ "${GAME_FILE}" = "${rom}" ] && got=ROM
  if [ "${got}" = "${want}" ] && { [ "${want}" = ROM ] || [ -s "${GAME_FILE}" ]; }; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "     got:      ${got}"
    echo "     expected: ${want}"
    FAILED=1
  fi
}
pack() { (cd "$2" && "${SEVENZIP}" a -bd -y "$1" . >/dev/null); }

S=${TMP}/src
mkdir -p "${S}/a" "${S}/b" "${S}/c/Hero2" "${S}/d/sub" "${S}/e"
echo disc >"${S}/a/Hero.chd" && pack "${TMP}/Hero.zip" "${S}/a"
echo disc >"${S}/b/Other.chd" && pack "${TMP}/Game.zip" "${S}/b"
printf '1\n1 0 4 2352 track01.bin 0\n' >"${S}/c/Hero2/Hero2.gdi"
echo track >"${S}/c/Hero2/track01.bin" && pack "${TMP}/Hero2.7z" "${S}/c"
echo disc >"${S}/d/sub/Disc.cdi" && pack "${TMP}/Sub.7z" "${S}/d"
echo rom >"${S}/e/game.bin" && pack "${TMP}/Cart.zip" "${S}/e"
echo junk >"${TMP}/Broken.zip"

check "disc named after the archive"          "${TMP}/Hero.zip"    disc/Hero.chd
check "the same disc again, from the cache"   "${TMP}/Hero.zip"    disc/Hero.chd
check "disc with another name gets renamed"   "${TMP}/Game.zip"    disc/Game.chd
check "named disc in a folder of its name"    "${TMP}/Hero2.7z"    disc/Hero2/Hero2.gdi
if [ -s "${TMP}/cache/disc/Hero2/track01.bin" ]; then
  echo "ok   the gdi keeps its tracks beside it"
else
  echo "FAIL the gdi keeps its tracks beside it"; FAILED=1
fi
check "disc with another name in a folder"    "${TMP}/Sub.7z"      disc/sub/Sub.cdi
check "a cartridge zip is handed over as is"  "${TMP}/Cart.zip"    ROM
check "a broken archive is handed over as is" "${TMP}/Broken.zip"  ROM

exit "${FAILED}"
