#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the BIOS page's data: archr-systems --json (verdict per
# system, file states, only systems with games) and archr-bios-livres
# install (copies a free BIOS, never replaces a file, installs the package
# through pacman when it is missing). Everything under a temporary root.
#   bash projects/ArchR/packages/archr/tests/bios_page_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SYSTEMS="${HERE}/../sources/scripts/archr-systems"
LIVRES="${HERE}/../sources/scripts/archr-bios-livres"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "     got:      $2"
    echo "     expected: $3"
    FAILED=1
  fi
}
if bash -n "${LIVRES}"; then echo "ok   bash -n"; else echo "FAIL bash -n"; FAILED=1; fi

R="${TMP}/root"
mkdir -p "${R}/usr/share/archr" "${R}/storage/roms/bios" "${TMP}/bin"
cat >"${R}/usr/share/archr/systems.cfg" <<'XML'
<systemList>
  <system><name>psx</name><fullname>PlayStation</fullname><path>/storage/roms/psx</path></system>
  <system><name>gba</name><fullname>Game Boy Advance</fullname><path>/storage/roms/gba</path></system>
  <system><name>msx</name><fullname>MSX</fullname><path>/storage/roms/msx</path></system>
  <system><name>pcenginecd</name><fullname>PC Engine CD</fullname><path>/storage/roms/pcenginecd</path></system>
  <system><name>segacd</name><fullname>Sega CD</fullname><path>/storage/roms/segacd</path></system>
  <system><name>fds</name><fullname>Famicom Disk System</fullname><path>/storage/roms/fds</path></system>
</systemList>
XML
for s in psx gba msx pcenginecd segacd; do
  mkdir -p "${R}/storage/roms/${s}/images"
  touch "${R}/storage/roms/${s}/game.bin"
done
mkdir -p "${R}/storage/roms/fds/images" # media only: no games
echo "not the real one" >"${R}/storage/roms/bios/syscard3.pce"
echo "not the real one" >"${R}/storage/roms/bios/scph1001.bin"

json() { ARCHR_SYSTEMS_ROOT="${R}" python3 "${SYSTEMS}" --json "$@"; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(str($1) for s in d['systems']))"; }
check "systems with games only" "$(json | field "s['id']")" "psx gba msx segacd pcenginecd"
check "all systems" "$(json --all | field "s['id']")" "psx gba msx segacd pcenginecd fds"
check "verdicts" "$(json | field "s['verdict']")" "bad builtin missing missing bad"
check "names come from the catalog" "$(json | field "s['name']" | cut -d' ' -f1-3)" "PlayStation Game Boy"
check "present first, md5 shown" \
  "$(json | python3 -c "import json,sys; f=json.load(sys.stdin)['systems'][0]['files'][0]; print(f['file'], f['state'], f['md5'])")" \
  "scph1001.bin bad dc2b9bf8da62ec93e868cfd29f0d067d"

# The free BIOS: the package is installed through pacman when missing.
SRC="${R}/usr/share/archr/bios-livres"
{
  echo '#!/bin/sh'
  echo "echo \"\$*\" >'${TMP}/pacman'"
  echo "mkdir -p '${SRC}/cbios'"
  echo "printf OPENBIOS >'${SRC}/openbios.bin'"
  echo "for f in cbios_main_msx1 cbios_main_msx2 cbios_main_msx2+ cbios_sub; do echo \"\$f\" >'${SRC}/cbios/'\"\$f\".rom; done"
} >"${TMP}/bin/pacman"
chmod +x "${TMP}/bin/pacman"
livres() { PATH="${TMP}/bin:${PATH}" ARCHR_BIOS_ROOT="${R}" bash "${LIVRES}" "$@"; }
check "psx install" "$(livres install psx | tr '\n' ' ')" "COPIED=1 KEPT=0 "
check "through pacman" "$(cat "${TMP}/pacman")" "-Sy --needed --noconfirm archr-bios-livres"
check "openbios in roms/bios" "$(cat "${R}/storage/roms/bios/openbios.bin")" "OPENBIOS"
check "psx shows it installed" "$(json | field "s['free_installed']" | cut -d' ' -f1)" "True"
echo "the console's own" >"${R}/storage/roms/bios/MSX.ROM"
echo "the console's own" >"${R}/storage/roms/bios/MSX2PEXT.ROM"
check "msx keeps the console's files and their pairs" "$(livres install msx | tr '\n' ' ')" "COPIED=2 KEPT=3 "
check "half a pair is never completed" "$([ -e "${R}/storage/roms/bios/MSX2P.ROM" ] && echo copied || echo kept)" "kept"
check "MSX.ROM untouched" "$(cat "${R}/storage/roms/bios/MSX.ROM")" "the console's own"
check "MSX2EXT is the sub ROM" "$(cat "${R}/storage/roms/bios/MSX2EXT.ROM")" "cbios_sub"
check "no partial files" "$(find "${R}/storage/roms/bios" -name '*.part' | wc -l)" "0"
livres install snes 2>/dev/null
check "unknown system" "$?" "2"
rm -rf "${SRC}"
printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/pacman"
livres install psx >/dev/null 2>&1
check "no package, no install" "$?" "1"
exit ${FAILED}
