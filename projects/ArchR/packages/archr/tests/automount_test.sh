#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for automount with a second card: fake /proc, devices and
# mount/umount/blkid/fsck/mergerfs that record calls and copy a card's files
# in. The fake union never touches files, so the file lists prove that the
# script itself never moves, copies or deletes a ROM.
#   bash projects/ArchR/packages/archr/tests/automount_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
SCRIPT="${PKG}/sources/scripts/automount"
FUNCTIONS="${PKG}/profile.d/001-functions"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

export AUTOMOUNT_PROFILE="${TMP}/profile" AUTOMOUNT_STORAGE="${TMP}/storage" \
  AUTOMOUNT_PROC="${TMP}/proc" AUTOMOUNT_SYS="${TMP}/sys" AUTOMOUNT_RUN="${TMP}/run"
cat >"${AUTOMOUNT_PROFILE}" <<EOF
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
J_CONF_LOCK="${TMP}/system.cfg.lock"
set_setting() { rewrite_config config_with "\${1}" "\${2}"; }
log() { echo "\$*" >>"${TMP}/log"; }
# The functions put /usr/bin first: the fake tools must stay ahead of it.
PATH="${TMP}/bin:\${PATH}"
EOF

# Fake tools. A device is ${TMP}/dev/<name>, with <name>.type (blkid) and
# <name>.card/ (its files, copied in on mount). ${TMP}/busy names a mount
# point that refuses umount; <name>.failonce fails the first mount.
BIN="${TMP}/bin"
mkdir -p "${BIN}"
tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${TMP}" "$2" >"${BIN}/$1"; chmod +x "${BIN}/$1"; }
tool blkid '
if [ "$1" = -o ]; then cat "$5.type"; exit; fi
for t in "$T"/dev/*.type; do d=${t%.type}; echo "$d: TYPE=\"$(cat "$t")\""; done'
tool mount '
echo "mount $*" >>"$T/calls"
for a in "$@"; do case $a in -*) ;; *) src=$dst; dst=$a ;; esac; done
case " $* " in
  *" --make-private "*) ;;
  *" --bind "*) echo "$src $dst none rw 0 0" >>"$T/proc/mounts" ;;
  *" -t overlay "*) echo "overlay $dst overlay rw 0 0" >>"$T/proc/mounts" ;;
  *) [ -e "$src.failonce" ] && { rm "$src.failonce"; exit 32; }
     type=$(cat "$src.type"); echo "$src $dst $type rw 0 0" >>"$T/proc/mounts"
     cp -r "$src.card/." "$dst/" ;;
esac'
tool umount '
echo "umount $*" >>"$T/calls"
dst=${!#}
[ "$(cat "$T/busy" 2>/dev/null)" = "$dst" ] && exit 32
grep -q " $dst " "$T/proc/mounts" || exit 1
awk -v p="$dst" "\$2 != p" "$T/proc/mounts" >"$T/m" && mv "$T/m" "$T/proc/mounts"
case $dst in */games-external) find "$dst" -mindepth 1 -delete ;; esac'
tool mergerfs '
echo "mergerfs $*" >>"$T/calls"
[ -e "$T/mergerfs-fails" ] && exit 1
echo "archr-roms ${!#} fuse.mergerfs rw 0 0" >>"$T/proc/mounts"'
tool fsck 'echo "fsck $*" >>"$T/calls"; [ -e "$T/slow" ] && sleep 5; exit "$(cat "$T/fsck-rc" 2>/dev/null || echo 0)"'

tool systemd-run 'echo "systemd-run $*" >>"$T/calls"; while [ "${1#-}" != "$1" ]; do shift; done; exec "$@"'
for t in lsmod modprobe sync systemd-tmpfiles; do tool "$t" ':'; done
export PATH="${BIN}:${PATH}"

STORAGE="${AUTOMOUNT_STORAGE}"
EXT="${STORAGE}/games-external"
LINK="${AUTOMOUNT_RUN}/roms2"
SD1="${TMP}/dev/mmcblk1p3"
SD2="${TMP}/dev/mmcblk0p1"

# A fresh device: SD1 (system) mounted, its ROMs in place, and the card
# described by: type, size in KiB, and files relative to the card root.
setup() {
  rm -rf "${TMP:?}"/{storage,proc,run,dev,calls,log,busy,system.cfg,fsck-rc,mergerfs-fails}
  mkdir -p "${STORAGE}/roms/snes" "${EXT}" "${TMP}/proc" "${TMP}/dev" "${TMP}/sys"
  touch "${STORAGE}/roms/snes/Internal.sfc"
  printf 'system.merged.storage=%s\n' "${MERGED:-0}" >"${TMP}/system.cfg"
  for p in 1 2 3; do echo ext4 >"${TMP}/dev/mmcblk1p${p}.type"; touch "${TMP}/dev/mmcblk1p${p}"; done
  echo vfat >"${TMP}/dev/mmcblk1p1.type"
  printf '%s %s ext4 rw 0 0\n' "${TMP}/dev/mmcblk1p2" / "${SD1}" "${STORAGE}" >"${TMP}/proc/mounts"
  printf '%s %s vfat ro 0 0\n' "${TMP}/dev/mmcblk1p1" /flash >>"${TMP}/proc/mounts"
  printf 'major minor  #blocks  name\n\n 179 0 31166976 mmcblk1\n 179 3 26169856 mmcblk1p3\n' >"${TMP}/proc/partitions"
  if [ $# -gt 0 ]; then
    echo "$1" >"${SD2}.type"
    touch "${SD2}"
    printf ' 179 8 %s mmcblk0\n 179 9 %s mmcblk0p1\n' "$2" "$2" >>"${TMP}/proc/partitions"
    shift 2
    mkdir -p "${SD2}.card"
    for f in "$@"; do mkdir -p "$(dirname "${SD2}.card/$f")"; touch "${SD2}.card/$f"; done
  fi
}
run() { bash "${SCRIPT}" "$@"; }
check() {
  if eval "${2}"; then echo "ok   ${1}"; else echo "FAIL ${1}"; FAILED=1; fi
}
mounted() { grep -q " $1 " "${TMP}/proc/mounts"; }
called() { grep -q -- "$1" "${TMP}/calls" 2>/dev/null; }
fstype() { awk -v p="$1" '$2 == p {t = $3} END {print t}' "${TMP}/proc/mounts"; }
setting() { grep -x "system.merged.storage=$1" "${TMP}/system.cfg" >/dev/null; }
# Every file on both cards with its size: what must never change.
files() { (cd "${TMP}" && find storage/roms "${SD2#${TMP}/}.card" "${EXT#${TMP}/}" -type f ! -name .tmp-archr -printf '%p %s\n' | sort); }
call_line() { grep -n -- "$1" "${TMP}/calls" | head -1 | cut -d: -f1; }

bash -n "${SCRIPT}" && echo "ok   bash -n" || { echo "FAIL bash -n"; FAILED=1; }

# Only the system card.
setup
run
check "no second card: nothing mounted" '! [ -e "${TMP}/calls" ] && ! [ -e "${LINK}" ]'
check "no second card: /storage/roms untouched" '! mounted "${STORAGE}/roms" && [ -f "${STORAGE}/roms/snes/Internal.sfc" ]'
check "no second card: no roms/ made in games-external" '! [ -e "${EXT}/roms" ]'

# dArkOS layout: exFAT, systems at the card root.
setup exfat 62000000 "snes/Mario (Ü).sfc" "gb/Tetris.gb"
run
check "exfat: mounted on games-external only" 'mounted "${EXT}" && ! mounted "${STORAGE}/roms"'
check "exfat: uid/gid and utf8 options" 'called "mount -t exfat -o uid=0,gid=0,fmask=0022,dmask=0022,iocharset=utf8 ${SD2} ${EXT}"'
check "exfat: never bound over /storage/roms" '! called -- "--bind"'
check "exfat: ROMs at the card root are published" '[ "$(readlink "${LINK}")" = "${EXT}" ]'
check "exfat: no empty roms/ created on the card" '! [ -e "${EXT}/roms" ]'
check "exfat: SD1 still visible" '[ -f "${STORAGE}/roms/snes/Internal.sfc" ]'

# A card with roms/, FAT32, 4 GiB (under the old 8 GiB floor).
setup vfat 3900000 "roms/snes/Zelda.sfc"
run
check "vfat 4 GiB: mounted with utf8" 'called "mount -t vfat -o uid=0,gid=0,fmask=0022,dmask=0022,utf8 ${SD2} ${EXT}"'
check "vfat: roms/ is published" '[ "$(readlink "${LINK}")" = "${EXT}/roms" ]'

# Restarted (another add event) while the card is mounted: nothing moves.
: >"${TMP}/calls"
run
check "restart: no remount, /storage/roms not unmounted" '! [ -s "${TMP}/calls" ] && [ "$(readlink "${LINK}")" = "${EXT}/roms" ]'

# Pulled out: only the second card's own device acts, lazily.
run remove "${TMP}/dev/mmcblk1p3"
check "remove: another device is ignored" 'mounted "${EXT}"'
run remove "${SD2}"
check "remove: lazy umount and link gone" 'called "umount -l ${EXT}" && ! mounted "${EXT}" && ! [ -e "${LINK}" ]'
check "remove: /storage/roms never unmounted" '! called "umount -l ${STORAGE}/roms"'

# A tiny partition is not a games card.
setup vfat 32768 "snes/A.sfc"
run
check "32 MiB partition ignored" '! mounted "${EXT}" && ! [ -e "${LINK}" ]'

# Unknown filesystem: left alone, boot goes on.
setup swap 8000000
run
check "swap partition ignored" '! mounted "${EXT}"'

# A card that fails to mount is checked read-only and mounted anyway.
setup exfat 62000000 "snes/A.sfc"
touch "${SD2}.failonce"
run
check "clean check: fsck -n, mounted, no warning" 'called "fsck -n ${SD2}" && mounted "${EXT}" && ! [ -e "${LINK}.errors" ]'
check "never repairs" '! grep -qE "fsck.* -[a-zA-Z]*[ya]" "${TMP}/calls"'
setup exfat 62000000 "snes/A.sfc"
touch "${SD2}.failonce"
echo 4 >"${TMP}/fsck-rc"
run
check "errors found: mounted anyway, warning published" 'mounted "${EXT}" && [ -L "${LINK}" ] && [ -e "${LINK}.errors" ]'
run remove "${SD2}"
check "remove clears the warning" '! [ -e "${LINK}.errors" ]'
setup exfat 62000000 "snes/A.sfc"
touch "${SD2}.failonce" "${TMP}/slow"
START=${SECONDS}
AUTOMOUNT_FSCK_TIMEOUT=1 run
check "a hung check is cut at its limit, mounted, warning published" '[ $((SECONDS - START)) -lt 4 ] && mounted "${EXT}" && [ -e "${LINK}.errors" ]'
rm -f "${TMP}/slow"

# Eject: none, busy (link restored), done.
setup
run eject
RC=$?
check "eject without a card: 2" '[ ${RC} -eq 2 ]'
setup exfat 62000000 "snes/A.sfc"
run
echo "${EXT}" >"${TMP}/busy"
run eject
RC=$?
check "eject busy: 1, card and link stay" '[ ${RC} -eq 1 ] && mounted "${EXT}" && [ -L "${LINK}" ]'
rm "${TMP}/busy"
run eject
RC=$?
check "eject: 0, card and link gone" '[ ${RC} -eq 0 ] && ! mounted "${EXT}" && ! [ -e "${LINK}" ]'

# Unified storage: mergerfs, any filesystem, off by default.
BRANCH="${AUTOMOUNT_RUN}/sd1-roms"
OPTS="category.create=epmfs,func.getattr=newest,minfreespace=1G,moveonenospc=true,cache.files=partial,dropcacheonclose=true,fsname=archr-roms"
MERGED=1 setup exfat 62000000 "snes/Mario.sfc" "gba/Zelda.gba"
touch "${STORAGE}/.ms_unsupported"
run
# Taken once the card is in (the fake mount copies its files in).
BEFORE=$(files)
check "unified exfat: one /storage/roms, SD1 branch first" 'called "mergerfs -o ${OPTS} ${BRANCH}:${EXT} ${STORAGE}/roms" && [ "$(fstype "${STORAGE}/roms")" = fuse.mergerfs ]'
check "unified: the daemon gets its own scope" 'called "systemd-run --scope --quiet --collect mergerfs"'
check "unified: SD1 bound privately as its branch" 'called "mount --bind ${STORAGE}/roms ${BRANCH}" && called "mount --make-private ${BRANCH}"'
check "unified: no second folder for the launcher" '! [ -e "${LINK}" ]'
check "unified: old overlay markers dropped" '! [ -e "${STORAGE}/.ms_unsupported" ]'
: >"${TMP}/calls"
run
check "unified restart: nothing remounted" '! [ -s "${TMP}/calls" ]'

# Off, on, off, on: only mounts change, never a file.
run unify 0
RC=$?
check "unify 0: union gone lazily, both folders listed, setting saved" '[ ${RC} -eq 0 ] && called "umount -l ${STORAGE}/roms" && [ -z "$(fstype "${STORAGE}/roms")" ] && [ "$(readlink "${LINK}")" = "${EXT}" ] && setting 0'
check "unify 0: the card stays mounted, SD1 branch unbound" 'mounted "${EXT}" && ! mounted "${BRANCH}"'
run unify 1
run unify 0
run unify 1
RC=$?
check "unify 1: one union again, no link, setting saved" '[ ${RC} -eq 0 ] && [ "$(grep -c " ${STORAGE}/roms " "${TMP}/proc/mounts")" -eq 1 ] && ! [ -e "${LINK}" ] && setting 1'
check "on/off/on: no file lost, moved or duplicated" '[ "$(files)" = "${BEFORE}" ]'

# Pulled out while unified: the union goes first, SD1 is /storage/roms again.
run remove "${SD2}"
check "remove unified: union, then card, lazily" '[ "$(call_line "umount -l ${STORAGE}/roms")" -lt "$(call_line "umount -l ${EXT}")" ] && ! mounted "${STORAGE}/roms" && ! mounted "${EXT}" && ! [ -e "${LINK}" ]'
check "remove unified: SD1 files in place" '[ -f "${STORAGE}/roms/snes/Internal.sfc" ]'

# A card with roms/ joins through that folder.
MERGED=1 setup vfat 3900000 "roms/snes/Zelda.sfc"
run
check "unified vfat: roms/ is the SD2 branch" 'called "mergerfs -o ${OPTS} ${BRANCH}:${EXT}/roms ${STORAGE}/roms"'
# Eject: busy card puts the union back; then done.
echo "${EXT}" >"${TMP}/busy"
run eject
RC=$?
check "eject busy unified: 1, union back" '[ ${RC} -eq 1 ] && [ "$(fstype "${STORAGE}/roms")" = fuse.mergerfs ] && mounted "${EXT}"'
rm "${TMP}/busy"
run eject
RC=$?
check "eject unified: 0, union and card gone" '[ ${RC} -eq 0 ] && ! mounted "${STORAGE}/roms" && ! mounted "${EXT}"'

# No second card at boot: SD1 alone, the setting waits for a card.
MERGED=1 setup
run
check "unified, no card: plain /storage/roms" '! called mergerfs && ! mounted "${STORAGE}/roms"'
run unify 0
run unify 1
RC=$?
check "unify without a card: saved, nothing mounted" '[ ${RC} -eq 0 ] && setting 1 && ! called mergerfs'
run unify 2
RC=$?
check "unify rejects other values" '[ ${RC} -eq 1 ] && setting 1'

# mergerfs fails: both folders stay listed, the switch goes back.
setup exfat 62000000 "snes/A.sfc"
run
touch "${TMP}/mergerfs-fails"
run unify 1
RC=$?
check "union fails: 1, setting back to 0, link kept, SD1 unbound" '[ ${RC} -eq 1 ] && setting 0 && [ -L "${LINK}" ] && ! mounted "${BRANCH}" && ! mounted "${STORAGE}/roms"'
MERGED=1 setup exfat 62000000 "snes/A.sfc"
touch "${TMP}/mergerfs-fails"
run
RC=$?
check "union fails at boot: card still listed, boot goes on" '[ ${RC} -eq 0 ] && mounted "${EXT}" && [ -L "${LINK}" ]'

# The old overlay's leftovers: its work dir goes, every file stays.
MERGED=1 setup ext4 62000000 "roms/snes/B.sfc" ".tmp/games-workdir/work/x"
mkdir -p "${STORAGE}/.tmp/games-workdir/work" "${STORAGE}/.games-internal-bind/roms"
run
check "overlay leftovers: work dirs and bind dir removed" '! [ -e "${EXT}/.tmp/games-workdir" ] && ! [ -e "${STORAGE}/.tmp/games-workdir" ] && ! [ -e "${STORAGE}/.games-internal-bind" ]'
check "overlay leftovers: ROMs untouched, union mounted" '[ -f "${EXT}/roms/snes/B.sfc" ] && [ -f "${STORAGE}/roms/snes/Internal.sfc" ] && [ "$(fstype "${STORAGE}/roms")" = fuse.mergerfs ]'

# Automount off: never mounts.
setup exfat 62000000 "snes/A.sfc"
echo "system.automount=0" >>"${TMP}/system.cfg"
run
check "automount off: nothing mounted" '! mounted "${EXT}" && ! [ -e "${LINK}" ]'

exit ${FAILED}
