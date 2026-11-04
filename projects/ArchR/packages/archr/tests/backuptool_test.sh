#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
# Host-only integration test. All persistent paths are rewritten into TMP;
# real zip/unzip exercise the archive format, including old-style archives.
#   bash projects/ArchR/packages/archr/tests/backuptool_test.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/root"
mkdir -p "${ROOT}/storage" "${TMP}/bin"
SCRIPT="${TMP}/backuptool"
sed -e 's|^\. /etc/profile$|OS_NAME=ArchR; DEBUG=false|' \
    -e "s|/storage|${ROOT}/storage|g" \
    -e "s|/var/lib/bluetooth|${ROOT}/var/lib/bluetooth|g" \
    -e "s|/var/lib/iwd|${ROOT}/var/lib/iwd|g" \
    -e "s|'storage/|'${ROOT#/}/storage/|g" \
    -e "s|'var/lib/|'${ROOT#/}/var/lib/|g" \
    -e "s|SYSTEM_CFG=\"storage/|SYSTEM_CFG=\"${ROOT#/}/storage/|g" \
    "${HERE}/../sources/scripts/backuptool" >"${SCRIPT}"
export TMPDIR="${TMP}"
ZIP="${ROOT}/storage/roms/backup/ArchR_BACKUP.zip"
put() { mkdir -p "${ROOT}/${1%/*}"; printf '%s\n' "$1" >"${ROOT}/$1"; }
check() { if "$@"; then echo "ok   $*"; else echo "FAIL $*"; exit 1; fi; }
FILES=(
  storage/roms/snes/'Game with spaces.srm' storage/roms/gb/Game.rtc
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
put storage/roms/backup/old.srm
put storage/roms/backup/ARCHIVED_ArchR_BACKUP-old.zip
mkdir -p "${ROOT}/storage/.config/drastic"
ln -s "${ROOT}/storage/roms/nds" "${ROOT}/storage/.config/drastic/backup"
bash "${SCRIPT}" backup >"${TMP}/backup.log" 2>&1
for f in "${FILES[@]}"; do
  [ "$(unzip -p "${ZIP}" "${ROOT#/}/${f}")" = "$f" ] || { echo "FAIL missing save: $f"; exit 1; }
done
echo "ok   every save and state is archived with its original path"
unzip -Z1 "${ZIP}" >"${TMP}/entries"
for f in "${ROMS[@]}"; do
  if grep -Fxq "${ROOT#/}/${f}" "${TMP}/entries"; then echo "FAIL ROM included: $f"; exit 1; fi
done
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
check test "$(grep -c 'private.psk' "${TMP}/entries" || true)" = 0
check test "$(unzip -p "${ZIP}" "${ROOT#/}/storage/.config/system/configs/system.cfg")" = 'system.language=pt_BR'
for f in "${FILES[@]}"; do rm "${ROOT}/${f}"; done
bash "${SCRIPT}" restore >"${TMP}/restore.log" 2>&1
for f in "${FILES[@]}"; do check test "$(cat "${ROOT}/${f}")" = "$f"; done
check grep -q '^wifi.key=secret$' "${ROOT}/storage/.config/system/configs/system.cfg"
check grep -q 'KiB required' "${TMP}/backup.log"
# Wi-Fi still needs explicit consent for both collection and restoration.
bash "${SCRIPT}" backup --with-wifi >"${TMP}/wifi.log" 2>&1
check test "$(unzip -p "${ZIP}" "${ROOT#/}/storage/.cache/iwd/private.psk")" = storage/.cache/iwd/private.psk
printf 'current network\n' >"${ROOT}/storage/.cache/iwd/private.psk"
bash "${SCRIPT}" restore >"${TMP}/restore-no-wifi.log" 2>&1
check test "$(cat "${ROOT}/storage/.cache/iwd/private.psk")" = 'current network'
bash "${SCRIPT}" restore --with-wifi >"${TMP}/restore-wifi.log" 2>&1
check test "$(cat "${ROOT}/storage/.cache/iwd/private.psk")" = storage/.cache/iwd/private.psk
# No format marker: archives from the old zip -r implementation still restore.
rm "${ZIP}"
put storage/.config/retroarch/legacy.cfg
zip -q "${ZIP}" "${ROOT}/storage/.config/retroarch/legacy.cfg"
rm "${ROOT}/storage/.config/retroarch/legacy.cfg"
bash "${SCRIPT}" restore >"${TMP}/legacy.log" 2>&1
check test -f "${ROOT}/storage/.config/retroarch/legacy.cfg"
# Both failed preflight and a mid-write failure preserve the previous archive.
cp "${ZIP}" "${TMP}/previous.zip"
# Kernel-owned locks release when the owner dies; the file can stay on disk.
exec 8>"${ROOT}/storage/.cache/backuptool.lock"
flock -n 8
if bash "${SCRIPT}" backup >"${TMP}/locked.log" 2>&1; then echo 'FAIL ignored concurrent backup lock'; exit 1; fi
flock -u 8
exec 8>&-
check cmp "${ZIP}" "${TMP}/previous.zip"
cat >"${TMP}/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfake 1024 1024 0 100%% /\n'
EOF
chmod +x "${TMP}/bin/df"
if PATH="${TMP}/bin:${PATH}" bash "${SCRIPT}" backup >"${TMP}/full.log" 2>&1; then echo 'FAIL accepted full destination'; exit 1; fi
check cmp "${ZIP}" "${TMP}/previous.zip"
check grep -qi 'space' "${TMP}/full.log"
# Info-ZIP updates can hold the old ZIP and a new copy simultaneously.
truncate -s 4194304 "${ROOT}/storage/roms/snes/Large.srm"
sed -i 's/fake 1024 1024 0/fake 10000 4000 6000/' "${TMP}/bin/df"
if PATH="${TMP}/bin:${PATH}" bash "${SCRIPT}" backup >"${TMP}/peak-space.log" 2>&1; then echo 'FAIL ignored peak ZIP rewrite space'; exit 1; fi
check cmp "${ZIP}" "${TMP}/previous.zip"
rm "${ROOT}/storage/roms/snes/Large.srm" "${TMP}/bin/df"
cat >"${TMP}/bin/zip" <<'EOF'
#!/bin/sh
for arg do case "$arg" in */backup.zip) printf partial >"$arg";; esac; done
exit 14
EOF
chmod +x "${TMP}/bin/zip"
if PATH="${TMP}/bin:${PATH}" bash "${SCRIPT}" backup >"${TMP}/failure.log" 2>&1; then echo 'FAIL accepted zip failure'; exit 1; fi
check cmp "${ZIP}" "${TMP}/previous.zip"
check test "$(find "${ROOT}/storage/roms/backup" -name '.backuptool*' -o -name '.backup.*' | wc -l)" = 0
rm "${TMP}/bin/zip"
# A second successful backup archives, rather than includes, the old ZIP.
bash "${SCRIPT}" backup >"${TMP}/second.log" 2>&1
check test "$(find "${ROOT}/storage/roms/backup" -name 'ARCHIVED_ArchR_BACKUP-*.zip' | wc -l)" -ge 2
unzip -Z1 "${ZIP}" >"${TMP}/entries"
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
# Even custom locations containing the backup's parent cannot collect it.
printf 'LOCATIONS=("%s/storage/roms" "%s/storage/roms/backup/old.srm" "%s/storage/.cache/iwd/"*)\n' \
  "${ROOT}" "${ROOT}" "${ROOT}" >"${ROOT}/storage/.config/backuptool.conf"
bash "${SCRIPT}" backup >"${TMP}/custom.log" 2>&1
unzip -Z1 "${ZIP}" >"${TMP}/entries"
check test "$(grep -c '/roms/backup/' "${TMP}/entries" || true)" = 0
check test "$(grep -c 'private.psk' "${TMP}/entries" || true)" = 0
check bash -n "${SCRIPT}"
echo 'ok   backuptool integration tests'
