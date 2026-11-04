#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for duckstation_card_filetitle.sh: the switch to
# PerGameFileTitle happens once, only when every title-named card is empty.
# ARCHR_REAL_CARDS may name a folder of real cards (*.mcd, *.srm) to report
# what each one is.
#   bash projects/ArchR/packages/archr/tests/duckstation_card_filetitle_test.sh

# Checks are eval'd strings: variables are read only there.
# shellcheck disable=SC2016,SC2329
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "$(dirname "${HERE}")")/emulators/standalone/duckstation-sa/scripts/duckstation_card_filetitle.sh"
T=$(mktemp -d)
FAILED=0
trap 'rm -rf "${T}"' EXIT

check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    FAILED=1
  fi
}
# A formatted card; block <n> in use when given.
card() {
  python3 -I - "$1" "${2:-0}" <<'EOF'
import sys
card = bytearray(128 * 1024)
card[0:2] = b"MC"
for n in range(1, 16):
    card[n * 128] = 0xA0
used = int(sys.argv[2])
if used:
    card[used * 128] = 0x51
    card[used * 128 + 10:used * 128 + 22] = b"BASLUS-00402"
open(sys.argv[1], "wb").write(card)
EOF
}
setup() {
  rm -rf "${T}/c"
  mkdir -p "${T}/c/cards"
  printf '[GameList]\nRecursivePaths = x\n\n[MemoryCards]\nUsePlaylistTitle = true\nDirectory = %s\nCard1Type = %s\nCard2Type = None\n\n[Console]\nRegion = Auto\n' \
    "${1:-${T}/c/cards}" "${2:-PerGameTitle}" >"${T}/c/settings.ini"
}
run() { bash "${SCRIPT}" "${T}/c/settings.ini"; }
type1() { sed -n 's/^Card1Type = //p' "${T}/c/settings.ini"; }

setup
card "${T}/c/cards/Tekken 3 (USA)_1.mcd"
card "${T}/c/cards/Shared_2.mcd" 1
run
check "every title card empty: switched" '[ "$(type1)" = PerGameFileTitle ]'
check "the rest of settings.ini is kept" \
  'grep -qx "Card2Type = None" "${T}/c/settings.ini" && grep -qx "Region = Auto" "${T}/c/settings.ini"'
check "the marker says so" 'grep -q switched "${T}/c/.archr-card-filetitle"'

setup
card "${T}/c/cards/Tekken 3 (USA)_1.mcd"
card "${T}/c/cards/Crash Bandicoot (USA)_1.mcd" 3
run
check "a card with a save: kept" '[ "$(type1)" = PerGameTitle ]'
check "and decided once" 'grep -q "Crash Bandicoot (USA)_1.mcd holds a save" "${T}/c/.archr-card-filetitle"'
rm "${T}/c/cards/Crash Bandicoot (USA)_1.mcd"
run
check "the marker stops a second run" '[ "$(type1)" = PerGameTitle ]'

setup
python3 -I -c 'import sys; open(sys.argv[1],"wb").write(b"MC" + bytes(100))' "${T}/c/cards/Short_1.mcd"
run
check "a card that is not 128 KiB: kept, asked again later" \
  '[ "$(type1)" = PerGameTitle ] && [ ! -e "${T}/c/.archr-card-filetitle" ]'

setup
card "${T}/c/cards/Deleted_1.mcd"
printf '\xa1' | dd of="${T}/c/cards/Deleted_1.mcd" bs=1 seek=128 conv=notrunc status=none
run
check "a deleted save still counts as data" '[ "$(type1)" = PerGameTitle ]'

setup "cards"
card "${T}/c/cards/Tekken 3 (USA)_1.mcd" 2
run
check "a relative folder is beside settings.ini" '[ "$(type1)" = PerGameTitle ]'

setup "${T}/c/none" Shared
run
check "another card type is left alone" \
  '[ "$(type1)" = Shared ] && grep -qx "kept Shared" "${T}/c/.archr-card-filetitle"'

setup "${T}/c/none"
run
check "no card folder: switched" '[ "$(type1)" = PerGameFileTitle ]'

if [ -n "${ARCHR_REAL_CARDS:-}" ]; then
  for real in "${ARCHR_REAL_CARDS}"/*.mcd "${ARCHR_REAL_CARDS}"/*.srm; do
    [ -e "${real}" ] || continue
    setup
    cp "${real}" "${T}/c/cards/Real_1.mcd"
    run
    echo "real: ${real##*/}: $(cat "${T}/c/.archr-card-filetitle" 2>/dev/null || echo unreadable)"
  done
fi

exit "${FAILED}"
