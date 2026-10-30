#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-roms-migrate, no root: fake parted (a partition table
# in a file), mount, blkid, df and the e2fsprogs/exfatprogs tools. The ROMs
# are real files and rsync is real, so copying, checking, renaming, the cut
# copy and its retake are exercised for real. Partitioning on real devices
# is tested by roms_exfat_loop_test.sh (root, loop devices).
#   bash projects/ArchR/packages/archr/tests/roms_migrate_test.sh

# The checks are strings run by eval: variables they read look unused.
# shellcheck disable=SC2034
set -u
# As on the device: services run without a locale.
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
SCRIPT="${PKG}/sources/scripts/archr-roms-migrate"
REAL_LIB="${PKG}/../sysutils/busybox/scripts/roms-partition"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

BIN="${TMP}/bin"
mkdir -p "${BIN}"
tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${TMP}" "$2" >"${BIN}/$1"; chmod +x "${BIN}/$1"; }

# Disk: /dev/mmcblk0, 29.7 GiB, three partitions, STORAGE to the end.
# Table lines "N START END" in ${TMP}/table; calls go to ${TMP}/calls.
TOTAL=62259200
tool parted '
echo "parted $*" >>"$T/calls"
args=" $* "
if [[ ${args} == *" print "* ]]; then
  echo "BYT;"; echo "/dev/mmcblk0:'"${TOTAL}"'s:sd/mmc:512:512:msdos:SD:;"
  while read -r n s e; do echo "${n}:${s}s:${e}s:$((e - s + 1))s:::;"; done <"$T/table"
elif [[ ${args} == *" mkpart "* ]]; then
  set -- $*; for a; do case $a in *s) start=${a%s} ;; esac; done
  echo "4 ${start} $(('"${TOTAL}"' - 1))" >>"$T/table"
elif [[ ${args} == *" resizepart "* ]]; then
  set -- $*; end=${!#}; [ "${end}" = 100% ] && end=$(('"${TOTAL}"' - 1)) || end=${end%s}
  [ -f "$T/parted-fail" ] && exit 1
  awk -v e="${end}" "\$1 == 3 { \$3 = e } { print }" "$T/table" >"$T/t" && mv "$T/t" "$T/table"
elif [[ ${args} == *" rm 4 "* ]]; then
  grep -v "^4 " "$T/table" >"$T/t"; mv "$T/t" "$T/table"
fi'
reset_table() {
  printf '1 32768 557055\n2 557056 9994239\n3 9994240 %s\n' $((TOTAL - 1)) >"${TMP}/table"
}
tool blkid '
d=${!#}; d=${d##*/}
case "$*" in *TYPE*) cat "$T/dev/$d.type" 2>/dev/null ;; *LABEL*) cat "$T/dev/$d.label" 2>/dev/null ;; esac'
tool mkfs.exfat 'echo "mkfs.exfat $*" >>"$T/calls"; d=${!#}; d=${d##*/}; echo exfat >"$T/dev/$d.type"; echo ARCHR_ROMS >"$T/dev/$d.label"; rm -rf "$T/exfat"; mkdir -p "$T/exfat"'
tool fsck.exfat 'echo "fsck.exfat $*" >>"$T/calls"; [ "$1" = -p ] && exit $(cat "$T/fsck-exfat-rc" 2>/dev/null || echo 0); exit 0'
tool e2fsck 'echo "e2fsck $*" >>"$T/calls"; exit 0'
tool dumpe2fs 'echo "Block size:               4096"'
tool resize2fs '
echo "resize2fs $*" >>"$T/calls"
[ "$1" = -P ] && echo "Estimated minimum size of the filesystem: $(cat "$T/minblocks")"
exit 0'
tool df 'echo "  Used"; echo "  $(cat "$T/used")"'
tool udevadm ':'
tool sync ':'
# Mounts: STORAGE stays a plain folder; "umount" only records it. The exFAT
# partition is ${TMP}/exfat, bound by a symlink at the mount point.
tool mount '
echo "mount $*" >>"$T/calls"
case "$*" in
  *exfat*) dst=${!#}; rmdir "${dst}" 2>/dev/null; ln -sfn "$T/exfat" "${dst}"; echo "/dev/mmcblk0p4 ${dst} exfat rw 0 0" >>"$T/proc/mounts" ;;
  *) echo "/dev/mmcblk0p3 $T/storage ext4 rw 0 0" >>"$T/proc/mounts" ;;
esac'
tool umount '
echo "umount $*" >>"$T/calls"
[ -f "$T/umount-busy" ] && exit 1
awk -v p="$1" "\$2 != p" "$T/proc/mounts" >"$T/m"; mv "$T/m" "$T/proc/mounts"
[ -L "$1" ] && rm -f "$1"; exit 0'
tool mountpoint 'grep -q " ${!#} " "$T/proc/mounts"'

# A lib that skips the wait for a /dev node (none here).
cat >"${TMP}/lib" <<EOF
. "${REAL_LIB}"
roms_wait_node() { :; }
EOF

export ROMS_MIGRATE_STORAGE="${TMP}/storage" ROMS_MIGRATE_LIB="${TMP}/lib" \
  ROMS_MIGRATE_POWER="${TMP}/power" ROMS_MIGRATE_WORK="${TMP}/work" \
  ROMS_MIGRATE_PROC="${TMP}/proc" ROMS_MIGRATE_NOREBOOT=1 PATH="${BIN}:${PATH}"
R="${TMP}/storage/roms"
migrate() { bash "${SCRIPT}" "$@"; }

setup() {
  rm -rf "${TMP:?}/storage" "${TMP:?}/exfat" "${TMP:?}/work" "${TMP:?}/dev" "${TMP}/power" "${TMP}/calls" \
    "${TMP}/fsck-exfat-rc" "${TMP}/umount-busy" "${TMP}/parted-fail"
  mkdir -p "${TMP}/storage/.cache" "${TMP}/dev" "${TMP}/proc" "${TMP}/power/battery" \
    "${R}/nes" "${R}/snes/media/covers" "${R}/bios/dc" "${R}/savestates/nes" "${R}/dreamcast"
  echo "/dev/mmcblk0p3 ${TMP}/storage ext4 rw 0 0" >"${TMP}/proc/mounts"
  echo Battery >"${TMP}/power/battery/type"; echo Discharging >"${TMP}/power/battery/status"
  echo 80 >"${TMP}/power/battery/capacity"
  reset_table
  echo 3000 >"${TMP}/used"          # MiB used on STORAGE
  echo 500000 >"${TMP}/minblocks"   # 1.9 GiB minimum for resize2fs
  head -c 300000 /dev/urandom >"${R}/nes/Zelda.nes"
  head -c 5000 /dev/urandom >"${R}/nes/Mario.zip"
  head -c 5001 /dev/urandom >"${R}/nes/mario.zip"
  head -c 7000 /dev/urandom >"${R}/snes/Zelda: A Link.sfc"
  # exFAT folds case in Unicode too.
  mkdir -p "${R}/gba"
  head -c 3000 /dev/urandom >"${R}/gba/POKÉMON.gba"
  head -c 3001 /dev/urandom >"${R}/gba/Pokémon.gba"
  head -c 900 /dev/urandom >"${R}/snes/media/covers/Zelda: A Link.png"
  head -c 2048 /dev/urandom >"${R}/bios/dc/dc_boot.bin"
  head -c 4096 /dev/urandom >"${R}/savestates/nes/Zelda.state1"
  echo readme >"${R}/README.txt"
  ln -s ../bios/dc "${R}/dreamcast/data"
}

# Every regular file with its checksum, relative to a folder.
sums() { (cd "$1" && find . -path ./.archr-migrate-tmp -prune -o -type f -print0 | sort -z | xargs -0 md5sum); }

### 1. Preview.
setup
OUT=$(migrate check); RC=$?
check "check: runs on an untouched card" '[ ${RC} = 0 ] && grep -qx RESULT=ok <<<"${OUT}"'
check "check: STORAGE keeps 8 GiB when it holds less" 'grep -qx STORAGE_AFTER_MIB=8192 <<<"${OUT}"'
check "check: the ROMs partition gets the rest" 'grep -qx ROMS_PART_MIB=$(( (TOTAL - 9994240 - 8192 * 2048) / 2048 )) <<<"${OUT}"'
check "check: renames counted (a colon twice, two case clashes)" 'grep -qx RENAMES=4 <<<"${OUT}"'
check "check: lists each rename with its new name" \
  'grep -qxF "$(printf "RENAME=snes/Zelda: A Link.sfc\tZelda_ A Link.sfc")" <<<"${OUT}" && grep -qxF "$(printf "RENAME=snes/media/covers/Zelda: A Link.png\tZelda_ A Link.png")" <<<"${OUT}" && grep -qxF "$(printf "RENAME=nes/mario.zip\tmario (2).zip")" <<<"${OUT}" && [ "$(grep -c ^RENAME= <<<"${OUT}")" = 4 ]'
check "check: a clash in Unicode case (POKÉMON, Pokémon)" 'grep -qxF "$(printf "RENAME=gba/Pokémon.gba\tPokémon (2).gba")" <<<"${OUT}"'
check "check: symbolic links counted" 'grep -qx SYMLINKS=1 <<<"${OUT}"'
check "check: changes nothing" '[ ! -e "${TMP}/calls" ] || ! grep -qv "parted -s -m" "${TMP}/calls"'

echo 15000 >"${TMP}/used"
OUT=$(migrate check)
check "check: STORAGE grows past 8 GiB to hold what it has, plus 1 GiB" 'grep -qx STORAGE_AFTER_MIB=16024 <<<"${OUT}"'
echo 3000 >"${TMP}/used"

truncate -s 20G "${R}/nes/huge.iso"
OUT=$(migrate check); RC=$?
check "check: refuses when the ROMs do not fit the new partition" '[ ${RC} = 1 ] && grep -qx RESULT=no-space <<<"${OUT}"'
rm -f "${R}/nes/huge.iso"

echo 20 >"${TMP}/power/battery/capacity"
OUT=$(migrate check); RC=$?
check "check: refuses on battery under 50 %" '[ ${RC} = 1 ] && grep -qx RESULT=low-power <<<"${OUT}"'
echo Charging >"${TMP}/power/battery/status"
OUT=$(migrate check)
check "check: a charger is enough" 'grep -qx RESULT=ok <<<"${OUT}"'

### 2. Arm, cancel.
setup
migrate start >/dev/null
check "start: arms the marker" 'grep -qx STATE=armed "${TMP}/storage/.roms-migrate"'
OUT=$(migrate check); RC=$?
check "check: an armed card reports it" '[ ${RC} = 2 ] && grep -qx RESULT=armed <<<"${OUT}"'
migrate cancel
check "cancel: disarms" '[ ! -e "${TMP}/storage/.roms-migrate" ]'

### 3. Low battery at the maintenance boot: gives up, nothing changed.
setup
migrate start >/dev/null
echo 10 >"${TMP}/power/battery/capacity"
migrate run >/dev/null
check "run: low battery gives up before shrinking" '! grep -q "^resize2fs /dev" "${TMP}/calls" && ! grep -q resizepart "${TMP}/calls"'
check "run: low battery removes the marker and remounts STORAGE" '[ ! -e "${TMP}/storage/.roms-migrate" ] && grep -q "ext4" "${TMP}/proc/mounts"'

### 4. STORAGE busy: gives up.
setup
migrate start >/dev/null
touch "${TMP}/umount-busy"
migrate run >/dev/null
check "run: a busy STORAGE gives up untouched" '[ ! -e "${TMP}/storage/.roms-migrate" ] && ! grep -q resize2fs\ /dev "${TMP}/calls"'

### 5. The whole migration.
setup
BEFORE=$(sums "${R}" | sed -e 's#Zelda: A Link#Zelda_ A Link#' -e 's#\./nes/mario\.zip#./nes/mario (2).zip#' -e 's#\./gba/Pokémon\.gba#./gba/Pokémon (2).gba#' | sort -k2)
migrate start >/dev/null
migrate run >"${TMP}/run.out"; RC=$?
check "run: succeeds" '[ ${RC} = 0 ]'
check "run: shrinks, then partitions, formats and checks, in order" \
  'grep -E "^(resize2fs -p /dev|parted .*resizepart|parted .*mkpart|mkfs.exfat|fsck.exfat -n)" "${TMP}/calls" | cut -c1-12 | tr "\n" , | grep -q "^resize2fs -p,parted ---pr,parted -s -a,mkfs.exfat -,fsck.exfat -"'
check "run: STORAGE resized to exactly the new partition 3" 'grep -q "^resize2fs -p /dev/mmcblk0p3 16777216s" "${TMP}/calls"'
check "run: partition 4 starts where planned" 'grep -q "^4 26771456 " "${TMP}/table"'
check "run: exFAT with the ROMs label and 32K clusters" 'grep -q "mkfs.exfat -c 32K -L ARCHR_ROMS /dev/mmcblk0p4" "${TMP}/calls"'
AFTER=$(sums "${TMP}/exfat" | sort -k2)
check "run: every file arrives intact (renamed where exFAT needs it)" '[ "${BEFORE}" = "${AFTER}" ]'
check "run: the ext4 roms folder is empty" '[ -z "$(ls -A "${R}")" ]'
check "run: no temporary folder left" '[ ! -e "${TMP}/exfat/.archr-migrate-tmp" ]'
check "run: the symbolic link is not copied" '[ ! -e "${TMP}/exfat/dreamcast/data" ] && [ -d "${TMP}/exfat/dreamcast" ]'
check "run: renames and the link are logged" 'grep -q "Renamed: snes/Zelda: A Link.sfc -> Zelda_ A Link.sfc" "${TMP}/storage/.cache/roms-migrate.log" && grep -q "Renamed: nes/mario.zip -> mario (2).zip" "${TMP}/storage/.cache/roms-migrate.log" && grep -q "Renamed: gba/Pokémon.gba -> Pokémon (2).gba" "${TMP}/storage/.cache/roms-migrate.log" && grep -q "symbolic link): dreamcast/data" "${TMP}/storage/.cache/roms-migrate.log"'
check "run: the marker is gone" '[ ! -e "${TMP}/storage/.roms-migrate" ]'
check "run: the ROMs partition is unmounted at the end" '! grep -q exfat "${TMP}/proc/mounts"'

### 6. Cut in the middle of the copy, then the next boot.
setup
head -c 150000000 /dev/zero >"${R}/nes/zz-big.iso"
BEFORE=$(sums "${R}" | sed -e 's#Zelda: A Link#Zelda_ A Link#' -e 's#\./nes/mario\.zip#./nes/mario (2).zip#' -e 's#\./gba/Pokémon\.gba#./gba/Pokémon (2).gba#' | sort -k2)
migrate start >/dev/null
setsid bash "${SCRIPT}" run >"${TMP}/cut.out" 2>&1 &
PID=$!
for _ in $(seq 1 300); do
  [ -n "$(find "${TMP}/exfat/.archr-migrate-tmp" -type f 2>/dev/null)" ] && break
  sleep 0.05
done
kill -9 -- -"${PID}" 2>/dev/null
wait "${PID}" 2>/dev/null
check "cut: hit during a file copy" '[ -n "$(find "${TMP}/exfat/.archr-migrate-tmp" -type f 2>/dev/null)" ]'
check "cut: the marker says copying" 'grep -qx STATE=copying "${TMP}/storage/.roms-migrate"'
check "cut: the entry being copied is still whole on ext4" '[ "$(stat -c %s "${R}/nes/zz-big.iso")" = 150000000 ]'
# The next boot: the exFAT partition is not mounted any more.
awk '$3 != "exfat"' "${TMP}/proc/mounts" >"${TMP}/m"; mv "${TMP}/m" "${TMP}/proc/mounts"
rm -f "${TMP}/storage/../work/roms" 2>/dev/null
migrate run >"${TMP}/resume.out"; RC=$?
AFTER=$(sums "${TMP}/exfat" | sort -k2)
check "resume: succeeds" '[ ${RC} = 0 ] && [ ! -e "${TMP}/storage/.roms-migrate" ]'
check "resume: checks the exFAT partition before mounting it" 'grep -q "fsck.exfat -p /dev/mmcblk0p4" "${TMP}/calls"'
check "resume: does not shrink or format again" '[ "$(grep -c "^mkfs.exfat" "${TMP}/calls")" = 1 ]'
check "resume: every file intact, no partial file left" '[ "${BEFORE}" = "${AFTER}" ] && [ ! -e "${TMP}/exfat/.archr-migrate-tmp" ]'

### 7. A copy that does not match stays on ext4, set aside.
setup
chmod 000 "${R}/snes/media/covers/Zelda: A Link.png"
migrate start >/dev/null
migrate run >/dev/null 2>&1
chmod 644 "${TMP}/storage/roms-not-migrated/snes/media/covers/"* 2>/dev/null
check "mismatch: the entry is kept on ext4 in roms-not-migrated" '[ -f "${TMP}/storage/roms-not-migrated/snes/Zelda_ A Link.sfc" ]'
check "mismatch: the other entries move" '[ -f "${TMP}/exfat/nes/Zelda.nes" ] && [ -z "$(ls -A "${R}")" ]'
check "mismatch: the migration still ends" '[ ! -e "${TMP}/storage/.roms-migrate" ]'

### 8. A broken exFAT partition: three tries, then normal boots until retry.
setup
migrate start >/dev/null
echo 4 >"${TMP}/fsck-exfat-rc"
migrate run >/dev/null 2>&1
check "broken: first try keeps the marker" 'grep -qx STATE=copying "${TMP}/storage/.roms-migrate" && grep -qx TRIES=1 "${TMP}/storage/.roms-migrate"'
check "broken: nothing deleted from ext4" '[ -f "${R}/nes/Zelda.nes" ]'
migrate run >/dev/null 2>&1
migrate run >/dev/null 2>&1
check "broken: stalls after three tries" 'grep -qx STATE=stalled "${TMP}/storage/.roms-migrate"'
migrate retry
check "retry: back to copying" 'grep -qx STATE=copying "${TMP}/storage/.roms-migrate" && grep -qx TRIES=0 "${TMP}/storage/.roms-migrate"'
rm -f "${TMP}/fsck-exfat-rc"
migrate run >/dev/null 2>&1
check "retry: completes once the partition is fine" '[ ! -e "${TMP}/storage/.roms-migrate" ] && [ -f "${TMP}/exfat/nes/Zelda.nes" ]'

### 9. Partition 3 cannot be resized: grows STORAGE back, gives up.
setup
migrate start >/dev/null
touch "${TMP}/parted-fail"
migrate run >/dev/null 2>&1
check "parted fails: gives up, no partition 4, ROMs untouched" '[ ! -e "${TMP}/storage/.roms-migrate" ] && ! grep -q "^4 " "${TMP}/table" && [ -f "${R}/nes/Zelda.nes" ]'
check "parted fails: STORAGE grown back" '[ "$(grep -c "^resize2fs /dev/mmcblk0p3$" "${TMP}/calls")" = 1 ]'

exit ${FAILED}
