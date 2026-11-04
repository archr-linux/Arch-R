#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
# Host-only integration test. All persistent paths are rewritten into TMP;
# real zip/unzip exercise the archive format, including old-style archives.
# The suite runs once with Info-ZIP unzip and once with BusyBox unzip, the
# one on the device (BUSYBOX=/path/to/busybox, or busybox from PATH).
#   bash projects/ArchR/packages/archr/tests/backuptool_test.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
if [ -z "${BACKUPTOOL_TEST_MODE:-}" ]; then
  BACKUPTOOL_TEST_MODE=infozip bash "$0"
  BUSYBOX=${BUSYBOX:-$(command -v busybox || true)}
  if [ -z "${BUSYBOX}" ]; then
    echo 'FAIL BusyBox not found: set BUSYBOX=/path/to/busybox'
    exit 1
  fi
  BACKUPTOOL_TEST_MODE=busybox BUSYBOX="${BUSYBOX}" bash "$0"
  exit 0
fi
MODE=${BACKUPTOOL_TEST_MODE}
echo "== unzip: ${MODE}"
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap '[ -n "${KEEPTMP:-}" ] || rm -rf "${TMP}"' EXIT
ROOT="${TMP}/root"
mkdir -p "${ROOT}/storage" "${TMP}/bin" "${TMP}/unzip"
SCRIPT="${TMP}/backuptool"
sed -e 's|^\. /etc/profile$|OS_NAME=ArchR; DEBUG=false|' \
    -e "s|/storage|${ROOT}/storage|g" \
    -e "s|'storage/|'${ROOT#/}/storage/|g" \
    -e "s|'var/lib/|'${ROOT#/}/var/lib/|g" \
    -e "s|SYSTEM_CFG=\"storage/|SYSTEM_CFG=\"${ROOT#/}/storage/|g" \
    "${HERE}/../sources/scripts/backuptool" >"${SCRIPT}"
export TMPDIR="${TMP}"
RUNPATH="${PATH}"
if [ "${MODE}" = busybox ]; then
  printf '#!/bin/sh\nexec "%s" unzip "$@"\n' "${BUSYBOX}" >"${TMP}/unzip/unzip"
  chmod +x "${TMP}/unzip/unzip"
  RUNPATH="${TMP}/unzip:${PATH}"
fi
# The script sees the unzip under test; the checks here always use Info-ZIP.
EXTRA=""
run() { PATH="${EXTRA:+${EXTRA}:}${RUNPATH}" bash "${SCRIPT}" "$@"; }
# fd 3 is the terminal: callers redirect the script's output into logs.
exec 3>&1
fails() { if run "$@"; then echo "FAIL accepted: $*" >&3; exit 1; fi; }
ZIP="${ROOT}/storage/roms/backup/ArchR_BACKUP.zip"
R="${ROOT#/}"
put() { mkdir -p "${ROOT}/${1%/*}"; printf '%s\n' "$1" >"${ROOT}/$1"; }
check() { if "$@"; then echo "ok   $*"; else echo "FAIL $*"; exit 1; fi; }
matches() { [[ "$1" =~ $2 ]]; }
lists() { unzip -Z1 "$1" | grep -q -- "$2"; }
FILES=(
  storage/roms/snes/'Game with spaces.srm' storage/roms/gb/Game.rtc
  storage/roms/snes/'Pokémon Ação.srm'
  storage/roms/gba/Game.sav storage/roms/nds/Game.dsv storage/roms/nds/Other.sav
  storage/roms/n64/Game.eep storage/roms/n64/Game.sra storage/roms/n64/Game.fla
  storage/roms/n64/Game.mpk storage/roms/n64/Game.st0 storage/roms/n64/Game.st9
  storage/roms/n64dd/Game.ram
  storage/roms/psx/Game_1.mcd storage/roms/psx/duckstation/memcards/shared_card_1.mcd
  storage/roms/psx/Mednafen.0.mcr storage/roms/saturn/Game.bkr
  storage/roms/saturn/Game.bcr storage/roms/nes/Game.sav.3
  storage/roms/ngp/Game.flash storage/roms/saturn/Game.smpc
  storage/roms/saturn/Game.seep storage/roms/pcfx/Game.fxb storage/roms/pce/Game.mg0
  storage/roms/fds/Game.mednafen.fds storage/roms/gba/Game.mednafen.type
  storage/roms/arcade/fbneo/Game.fs storage/roms/bios/fbneo/Game.hi
  storage/roms/arcade/fbneo/shared.memcard storage/roms/arcade/mame/Game.nvram
  storage/roms/c64/Game.vsf storage/.config/hatari/hatari.sav
  storage/roms/bios/dc/vmu_save_A1.bin storage/roms/bios/dc/Game.zip.eeprom
  storage/roms/bios/dc/Game.zip.nvmem storage/roms/bios/dc/dc_flash.bin
  storage/roms/bios/dc/dc_nvmem.bin
  storage/roms/bios/dsi_nand.bin
  storage/roms/bios/GC/MemoryCardA.USA.raw storage/roms/bios/GC/MemoryCardB.EUR.raw
  storage/roms/bios/GC/USA/01-GALE-SuperSmashBros.gci
  storage/roms/dreamcast/data/vmu_save_B1.bin
  storage/roms/bios/yabasanshiro/backup.bin
  storage/roms/psp/ULUS12345DATA00/PARAM.SFO
  storage/roms/psp/ULUS12345DATA00/DATA.BIN storage/roms/psp/ULUS12345DATA00/ICON0.PNG
  storage/roms/psp/SAVEDATA/ULUS00001/ARBITRARY.DAT
  storage/roms/psp/PSP/SAVEDATA/ULUS00002/PARAM.SFO
  storage/roms/psp/PPSSPP_STATE/Game.ppst
  storage/roms/openbor/Saves/Game.dat storage/roms/pico-8/cdata/Game.p8d
  storage/.lexaloffle/pico-8/cdata/Other.p8d
  storage/.local/share/scummvm/saves/Game.001
  storage/.config/amiberry/savestates/Game.uss storage/.config/amiberry/nvram/Game.nvr
  storage/.config/hatari/auto.sav storage/.config/touchHLE/touchHLE_sandbox/id/Documents/save
  storage/.config/game/configs/hypseus/ram/Game.ram
  storage/.config/dolphin-emu/Wii/title/00010000/52534245/data/banner.bin
  storage/.cache/bluetooth/AA:BB:CC:DD:EE:FF/info
  storage/roms/gzdoom/save0.zds
  storage/roms/savestates/snes/Game.state.auto
  storage/roms/savestates/snes/Game.state1.png
  storage/roms/savestates/nds/Game_0.dss storage/roms/savestates/nds/Game.ml1
  storage/roms/savestates/psp/ppsspp-sa/Game.ppst
  storage/roms/savestates/psx/Game_resume.sav
  storage/roms/savestates/saturn/yabasanshiro/Game.yss
  storage/roms/snes/UPPER.SRM
)
# BIOS and firmware images next to the save images stay out: no generic *.bin.
ROMS=(storage/roms/snes/Game.sfc storage/roms/nds/Game.nds storage/roms/psp/Game.iso
  storage/roms/psx/Game.bin storage/roms/atarist/Game.st storage/roms/atarist/Game.stx
  storage/roms/fds/Game.fds
  storage/roms/bios/dc/dc_boot.bin storage/roms/pico-8/Game.p8.png
  storage/roms/bios/bios7.bin storage/roms/bios/dsi_bios7.bin
  storage/roms/bios/dsi_firmware.bin storage/roms/bios/firmware.bin
  storage/roms/bios/GC/USA/IPL.bin storage/.config/dolphin-emu/Wii/title/00010001/app.bin
  storage/roms/psp/Extracted/PSP_GAME/PARAM.SFO storage/roms/snes/gamelist.xml
  storage/roms/psp/ULUS77777/Disc.iso storage/roms/psp/ULUS88888/PSP_GAME/PARAM.SFO)
put storage/.config/system/configs/system.cfg
printf 'wifi.ssid=private\nwifi.key=secret\nsystem.language=pt_BR\n' >"${ROOT}/storage/.config/system/configs/system.cfg"
put storage/.config/retroarch/retroarch.cfg
put storage/.cache/iwd/private.psk
for f in "${FILES[@]}" "${ROMS[@]}"; do put "${f}"; done
# Incompressible and tiny files: Info-ZIP would store both when it can seek.
head -c 65536 /dev/urandom >"${ROOT}/storage/roms/gba/Random.sav"
printf x >"${ROOT}/storage/roms/gba/Tiny.sav"
put storage/roms/backup/old.srm
put storage/roms/backup/ARCHIVED_ArchR_BACKUP-old.zip
mkdir -p "${ROOT}/storage/.config/drastic"
ln -s "${ROOT}/storage/roms/nds" "${ROOT}/storage/.config/drastic/backup"
run backup >"${TMP}/backup.log" 2>&1
for f in "${FILES[@]}"; do
  [ "$(unzip -p "${ZIP}" "${R}/${f}")" = "$f" ] || { echo "FAIL missing save: $f"; exit 1; }
done
echo "ok   every save, state and save image is archived with its original path"
unzip -Z1 "${ZIP}" >"${TMP}/entries"
for f in "${ROMS[@]}"; do
  if grep -Fxq "${R}/${f}" "${TMP}/entries"; then echo "FAIL ROM or BIOS included: $f"; exit 1; fi
done
echo "ok   ROMs, BIOS and firmware images stay out"
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
check test "$(grep -c 'private.psk' "${TMP}/entries" || true)" = 0
check test "$(unzip -p "${ZIP}" "${R}/storage/.config/system/configs/system.cfg")" = 'system.language=pt_BR'
check grep -q 'KiB required' "${TMP}/backup.log"

# 4. Every non-empty entry is deflated, and a sha256 manifest covers them all.
check test "$(unzip -v "${ZIP}" | awk '$2 == "Stored" && $1 > 0' | wc -l)" = 0
check cmp <(unzip -p "${ZIP}" "${R}/storage/roms/gba/Random.sav") "${ROOT}/storage/roms/gba/Random.sav"
unzip -p "${ZIP}" "${R}/storage/.cache/backuptool.sha256" >"${TMP}/manifest"
check test "$(wc -l <"${TMP}/manifest")" = "$(( $(wc -l <"${TMP}/entries") - 1 ))"
check grep -Fq "  ${R}/storage/roms/bios/dsi_nand.bin" "${TMP}/manifest"
mkdir "${TMP}/x" && (cd "${TMP}/x" && unzip -q "${ZIP}" && sha256sum -c --quiet "${R}/storage/.cache/backuptool.sha256")
echo "ok   manifest matches the archived files"
rm -rf "${TMP}/x"

for f in "${FILES[@]}"; do rm "${ROOT}/${f}"; done
run restore >"${TMP}/restore.log" 2>&1
for f in "${FILES[@]}"; do check test "$(cat "${ROOT}/${f}")" = "$f"; done
check cmp "${ROOT}/storage/roms/gba/Random.sav" <(unzip -p "${ZIP}" "${R}/storage/roms/gba/Random.sav")
check grep -q '^wifi.key=secret$' "${ROOT}/storage/.config/system/configs/system.cfg"
check grep -q '^system.language=pt_BR$' "${ROOT}/storage/.config/system/configs/system.cfg"
check test ! -e "${ROOT}/storage/.cache/backuptool.sha256"
check test "$(find "${ROOT}/storage/.cache" -maxdepth 1 -name 'backuptool-restore.*' | wc -l)" = 0

# 1. Restore keeps newer saves, puts the backup's copy beside them, and logs it.
SAVE="${ROOT}/storage/roms/gba/Game.sav"
NAND="${ROOT}/storage/roms/bios/dsi_nand.bin"
OLDSAVE="${ROOT}/storage/roms/gb/Game.rtc"
SAME="${ROOT}/storage/roms/n64/Game.eep"
CFG="${ROOT}/storage/.config/retroarch/retroarch.cfg"
printf 'played after the backup\n' >"${SAVE}"
printf 'new DSiWare save\n' >"${NAND}"
printf 'older than the backup\n' >"${OLDSAVE}"
touch -d '2001-01-01' "${OLDSAVE}"
touch -d '+1 hour' "${SAVE}" "${NAND}" "${SAME}"
printf 'changed setting\n' >"${CFG}"
touch -d '+1 hour' "${CFG}"
run restore >"${TMP}/conflict.log" 2>&1
check test "$(cat "${SAVE}")" = 'played after the backup'
check test "$(cat "${NAND}")" = 'new DSiWare save'
check test "$(cat "${SAVE}".backup-*)" = storage/roms/gba/Game.sav
check test "$(cat "${NAND}".backup-*)" = storage/roms/bios/dsi_nand.bin
check test "$(cat "${OLDSAVE}")" = storage/roms/gb/Game.rtc
check test "$(find "${ROOT}/storage/roms/n64" -name 'Game.eep.backup-*' | wc -l)" = 0
check test "$(cat "${CFG}")" = storage/.config/retroarch/retroarch.cfg
check grep -q 'kept 2 newer saves' "${TMP}/conflict.log"
REPORTS=("${ROOT}"/storage/roms/backup/ArchR_RESTORE-*.log)
check test "${#REPORTS[@]}" = 1
check grep -Fq "Kept newer save ${SAVE}" "${REPORTS[0]}"
# 5. Names carry seconds: a second report in the same minute is a new file.
check matches "${REPORTS[0]}" '_RESTORE-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9]+)?\.log$'
COPIES=("${SAVE}".backup-*)
check matches "${COPIES[0]}" '\.backup-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9]+)?$'
run restore >"${TMP}/conflict2.log" 2>&1
check test "$(find "${ROOT}/storage/roms/backup" -name 'ArchR_RESTORE-*.log' | wc -l)" = 2
check test "$(find "${ROOT}/storage/roms/gba" -name 'Game.sav.backup-*' | wc -l)" = 2
find "${ROOT}/storage" -name '*.backup-*' -delete
rm -f "${ROOT}"/storage/roms/backup/ArchR_RESTORE-*.log
echo storage/roms/gba/Game.sav >"${SAVE}"
echo storage/roms/bios/dsi_nand.bin >"${NAND}"

# Snapshot of everything restore could touch, to prove refusals touch nothing.
# Directory times are left out: staging lives in, and leaves, /storage/.cache.
snapshot() {
  (cd "${ROOT}/storage" && find . \( -path ./roms/backup -o -path ./.cache/backuptool.lock \) -prune \
    -o -type d -printf '%p d\n' -o -printf '%p %y %s %T@ %l\n' | LC_ALL=C sort) >"$1"
}
GOOD="${TMP}/good.zip"
cp "${ZIP}" "${GOOD}"
untouched() {
  snapshot "${TMP}/after"
  check cmp "${TMP}/before" "${TMP}/after"
  check test "$(find "${ROOT}/storage/.cache" -maxdepth 1 -name 'backuptool-restore.*' | wc -l)" = 0
}
printf 'current\n' >"${SAVE}"
touch -d '2001-01-01' "${SAVE}"
snapshot "${TMP}/before"

# 1/4. A corrupt deflated entry fails extraction: nothing is replaced.
OFFSET=$(LC_ALL=C grep -abo 'gba/Random.sav' "${ZIP}" | head -n1 | cut -d: -f1)
printf '\377\377\377\377\377\377\377\377' | dd of="${ZIP}" bs=1 seek=$((OFFSET + 4000)) conv=notrunc 2>/dev/null
fails restore >"${TMP}/corrupt.log" 2>&1
untouched
cp "${GOOD}" "${ZIP}"

# 4. A STORED entry with bad bytes passes BusyBox's CRC; the sha256 does not.
mkdir -p "${TMP}/stored/${R}/storage/roms/gba" "${TMP}/stored/${R}/storage/.cache"
printf 'GOOD SAVE DATA\n' >"${TMP}/stored/${R}/storage/roms/gba/Game.sav"
(cd "${TMP}/stored" && sha256sum "${R}/storage/roms/gba/Game.sav" >"${R}/storage/.cache/backuptool.sha256" &&
  zip -q -0 "${ZIP}.new" "${R}/storage/roms/gba/Game.sav" "${R}/storage/.cache/backuptool.sha256")
mv "${ZIP}.new" "${ZIP}"
LC_ALL=C sed -i 's/GOOD SAVE DATA/EVIL SAVE DATA/' "${ZIP}"
fails restore >"${TMP}/stored.log" 2>&1
# Info-ZIP catches the CRC itself; BusyBox extracts it and the sha256 catches it.
if [ "${MODE}" = busybox ]; then
  check grep -q 'checksum mismatch' "${TMP}/stored.log"
else
  check grep -Eq 'checksum mismatch|extract cleanly' "${TMP}/stored.log"
fi
untouched
# A manifest that leaves a member out is refused too.
(cd "${TMP}/stored" && : >"${R}/storage/.cache/backuptool.sha256" &&
  zip -q "${ZIP}.new" "${R}/storage/roms/gba/Game.sav" "${R}/storage/.cache/backuptool.sha256")
mv "${ZIP}.new" "${ZIP}"
fails restore >"${TMP}/partial-manifest.log" 2>&1
untouched

# 2. Confinement. Each archive is refused whole, before anything is written.
# Archive $1/$2... (symlinks kept), plus a good member that must not be
# restored either. Names are patched afterwards where zip would not write them.
evil() {
  local tree="$1"; shift
  rm -f "${ZIP}"
  (cd "${tree}" && zip -q -y "${ZIP}" "$@")
  (cd "${TMP}/stored" && zip -q "${ZIP}" "${R}/storage/roms/gba/Game.sav")
}
mkdir -p "${TMP}/evil/${R}/etc" "${TMP}/evil/QZ/${R}/storage/roms" "${TMP}/outside"
# Outside storage/.
printf 'evil\n' >"${TMP}/evil/${R}/etc/passwd"
evil "${TMP}/evil" "${R}/etc/passwd"
fails restore >"${TMP}/outside.log" 2>&1
check grep -q 'outside' "${TMP}/outside.log"
check test ! -e "${ROOT}/etc/passwd"
untouched
# Absolute name: "QZ/tmp/..." becomes "///tmp/...".
printf 'evil\n' >"${TMP}/evil/QZ/${R}/storage/roms/abs.srm"
evil "${TMP}/evil" "QZ/${R}/storage/roms/abs.srm"
LC_ALL=C sed -i "s|QZ/${R}/storage/roms/abs.srm|///${R}/storage/roms/abs.srm|g" "${ZIP}"
check lists "${ZIP}" '^///'
fails restore >"${TMP}/absolute.log" 2>&1
check grep -q 'unsafe member name' "${TMP}/absolute.log"
check test ! -e "${ROOT}/storage/roms/abs.srm"
untouched
# Dot-dot: "storage/QQ/QQ/QQ/QQ/escaped" becomes "storage/../../../../escaped".
mkdir -p "${TMP}/evil/${R}/storage/QQ/QQ/QQ/QQ"
printf 'evil\n' >"${TMP}/evil/${R}/storage/QQ/QQ/QQ/QQ/escaped"
evil "${TMP}/evil" "${R}/storage/QQ/QQ/QQ/QQ/escaped"
LC_ALL=C sed -i 's|QQ/QQ/QQ/QQ/escaped|../../../../escaped|g' "${ZIP}"
check lists "${ZIP}" '/\.\./\.\./'
fails restore >"${TMP}/dotdot.log" 2>&1
check grep -q 'unsafe member name' "${TMP}/dotdot.log"
check test "$(find "${TMP}" -name escaped -not -path "${TMP}/evil/*" | wc -l)" = 0
untouched
# A symlink member used as the directory of a later member.
ln -s "${TMP}/outside" "${TMP}/evil/${R}/storage/link"
mkdir -p "${TMP}/evil2/${R}/storage/link"
printf 'evil\n' >"${TMP}/evil2/${R}/storage/link/planted"
evil "${TMP}/evil" "${R}/storage/link"
(cd "${TMP}/evil2" && zip -q "${ZIP}" "${R}/storage/link/planted")
fails restore >"${TMP}/symlink-member.log" 2>&1
check grep -q 'written through' "${TMP}/symlink-member.log"
check test ! -e "${TMP}/outside/planted"
untouched
# A symlink member alone is refused after extraction into the stage.
evil "${TMP}/evil" "${R}/storage/link"
fails restore >"${TMP}/symlink-alone.log" 2>&1
check grep -q 'links or special files' "${TMP}/symlink-alone.log"
untouched
# A symlink already on the device, above a member's destination.
ln -s "${TMP}/outside" "${ROOT}/storage/.config/sneaky"
snapshot "${TMP}/before"
mkdir -p "${TMP}/evil3/${R}/storage/.config/sneaky"
printf 'evil\n' >"${TMP}/evil3/${R}/storage/.config/sneaky/planted"
evil "${TMP}/evil3" "${R}/storage/.config/sneaky/planted"
fails restore >"${TMP}/ancestor.log" 2>&1
check grep -q 'Unsafe destination' "${TMP}/ancestor.log"
check test ! -e "${TMP}/outside/planted"
untouched
rm "${ROOT}/storage/.config/sneaky"
check test "$(cat "${SAVE}")" = current
cp "${GOOD}" "${ZIP}"

# Wi-Fi still needs explicit consent for both collection and restoration.
run backup --with-wifi >"${TMP}/wifi.log" 2>&1
check test "$(unzip -p "${ZIP}" "${R}/storage/.cache/iwd/private.psk")" = storage/.cache/iwd/private.psk
printf 'current network\n' >"${ROOT}/storage/.cache/iwd/private.psk"
run restore >"${TMP}/restore-no-wifi.log" 2>&1
check test "$(cat "${ROOT}/storage/.cache/iwd/private.psk")" = 'current network'
run restore --with-wifi >"${TMP}/restore-wifi.log" 2>&1
check test "$(cat "${ROOT}/storage/.cache/iwd/private.psk")" = storage/.cache/iwd/private.psk
# No format marker: archives from the old zip -r implementation still restore,
# including Bluetooth pairings stored through the /var/lib/bluetooth link.
rm "${ZIP}"
put storage/.config/retroarch/legacy.cfg
mkdir -p "${TMP}/legacy/${R}/var/lib/bluetooth/11:22:33:44:55:66"
printf 'paired\n' >"${TMP}/legacy/${R}/var/lib/bluetooth/11:22:33:44:55:66/info"
zip -q "${ZIP}" "${ROOT}/storage/.config/retroarch/legacy.cfg"
(cd "${TMP}/legacy" && zip -q -r "${ZIP}" "${R}/var/lib/bluetooth")
rm "${ROOT}/storage/.config/retroarch/legacy.cfg"
run restore >"${TMP}/legacy.log" 2>&1
check test -f "${ROOT}/storage/.config/retroarch/legacy.cfg"
check test "$(cat "${ROOT}/storage/.cache/bluetooth/11:22:33:44:55:66/info")" = paired
check test ! -e "${ROOT}/var/lib/bluetooth"
# Both failed preflight and a mid-write failure preserve the previous archive.
cp "${ZIP}" "${TMP}/previous.zip"
# 5. Kernel-owned locks release when the owner dies; the file can stay on disk.
exec 8>"${ROOT}/storage/.cache/backuptool.lock"
flock -n 8
fails backup >"${TMP}/locked.log" 2>&1
check grep -q 'already running' "${TMP}/locked.log"
fails restore >"${TMP}/locked-restore.log" 2>&1
check grep -q 'already running' "${TMP}/locked-restore.log"
flock -u 8
exec 8>&-
check cmp "${ZIP}" "${TMP}/previous.zip"
# A lock that cannot be taken at all is an error, not a running backup.
cat >"${TMP}/bin/flock" <<'EOF'
#!/bin/sh
echo 'flock: 9: Bad file descriptor' >&2
exit 1
EOF
chmod +x "${TMP}/bin/flock"
EXTRA="${TMP}/bin" fails backup >"${TMP}/lockerr.log" 2>&1
check grep -q 'cannot take the backup lock: flock: 9: Bad file descriptor' "${TMP}/lockerr.log"
check test "$(grep -c 'already running' "${TMP}/lockerr.log" || true)" = 0
rm "${TMP}/bin/flock"
cat >"${TMP}/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfake 1024 1024 0 100%% /\n'
EOF
chmod +x "${TMP}/bin/df"
EXTRA="${TMP}/bin" fails backup >"${TMP}/full.log" 2>&1
check cmp "${ZIP}" "${TMP}/previous.zip"
check grep -qi 'space' "${TMP}/full.log"
# The ZIP and its verification copy coexist.
truncate -s 4194304 "${ROOT}/storage/roms/snes/Large.srm"
sed -i 's/fake 1024 1024 0/fake 10000 4000 6000/' "${TMP}/bin/df"
EXTRA="${TMP}/bin" fails backup >"${TMP}/peak-space.log" 2>&1
check cmp "${ZIP}" "${TMP}/previous.zip"
rm "${ROOT}/storage/roms/snes/Large.srm" "${TMP}/bin/df"
cat >"${TMP}/bin/zip" <<'EOF'
#!/bin/sh
printf partial
exit 14
EOF
chmod +x "${TMP}/bin/zip"
EXTRA="${TMP}/bin" fails backup >"${TMP}/failure.log" 2>&1
check cmp "${ZIP}" "${TMP}/previous.zip"
check test "$(find "${ROOT}/storage/roms/backup" -name '.backuptool*' -o -name '.backup.*' | wc -l)" = 0
rm "${TMP}/bin/zip"
# A second successful backup archives, rather than includes, the old ZIP.
run backup >"${TMP}/second.log" 2>&1
check test "$(find "${ROOT}/storage/roms/backup" -name 'ARCHIVED_ArchR_BACKUP-*.zip' | wc -l)" -ge 2
unzip -Z1 "${ZIP}" >"${TMP}/entries"
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
# Even custom locations containing the backup's parent cannot collect it,
# and files outside /storage are skipped rather than made unrestorable.
mkdir -p "${ROOT}/elsewhere" && echo x >"${ROOT}/elsewhere/file"
printf 'LOCATIONS=("%s/storage/roms" "%s/storage/roms/backup/old.srm" "%s/storage/.cache/iwd/"* "%s/elsewhere/file")\n' \
  "${ROOT}" "${ROOT}" "${ROOT}" "${ROOT}" >"${ROOT}/storage/.config/backuptool.conf"
run backup >"${TMP}/custom.log" 2>&1
unzip -Z1 "${ZIP}" >"${TMP}/entries"
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
check test "$(grep -c 'private.psk' "${TMP}/entries" || true)" = 0
check test "$(grep -c 'elsewhere' "${TMP}/entries" || true)" = 0
check grep -q 'Skipped.*elsewhere/file' "${TMP}/custom.log"
check bash -n "${SCRIPT}"
echo "ok   backuptool integration tests (${MODE})"
