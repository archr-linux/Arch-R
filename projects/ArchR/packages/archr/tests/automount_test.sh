#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for automount with a second card: fake /proc, devices and
# mount/umount/blkid/fsck that record calls and copy a card's files in.
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
tool fsck 'echo "fsck $*" >>"$T/calls"; [ -e "$T/slow" ] && sleep 5'

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
  rm -rf "${TMP:?}"/{storage,proc,run,dev,calls,log,busy,system.cfg}
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

bash -n "${SCRIPT}" && echo "ok   bash -n" || { echo "FAIL bash -n"; FAILED=1; }

# Only the system card.
setup
run
check "no second card: nothing mounted" '! [ -e "${TMP}/calls" ] && ! [ -e "${LINK}" ]'
check "no second card: /storage/roms untouched" '! mounted "${STORAGE}/roms" && [ -f "${STORAGE}/roms/snes/Internal.sfc" ]'
check "no second card: no roms/ made in games-external" '! [ -e "${EXT}/roms" ]'
check "no second card: merged.device defaults to internal" 'grep -qx "system.merged.device=internal" "${TMP}/system.cfg"'

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

# A card that fails to mount is checked (bounded) and mounted again.
setup exfat 62000000 "snes/A.sfc"
touch "${SD2}.failonce"
run
check "fsck after a failed mount, then mounted" 'called "fsck -Mly ${SD2}" && mounted "${EXT}"'
setup exfat 62000000 "snes/A.sfc"
touch "${SD2}.failonce" "${TMP}/slow"
START=${SECONDS}
AUTOMOUNT_FSCK_TIMEOUT=1 run
check "a hung fsck is cut at its time limit" '[ $((SECONDS - START)) -lt 4 ] && mounted "${EXT}"'
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

# Unified storage, explicit and ext4 only.
MERGED=1 setup ext4 62000000 "roms/snes/B.sfc"
run
check "merged ext4: overlay on /storage/roms, no link" '[ "$(awk -v p="${STORAGE}/roms" "\$2 == p {print \$3}" "${TMP}/proc/mounts")" = overlay ] && ! [ -e "${LINK}" ]'
run remove "${SD2}"
check "merged: remove drops the overlay first" 'called "umount -l ${STORAGE}/roms" && ! mounted "${STORAGE}/roms" && ! mounted "${EXT}"'
MERGED=1 setup exfat 62000000 "snes/B.sfc"
run
check "merged on exfat: no overlay, link instead" '! mounted "${STORAGE}/roms" && [ -L "${LINK}" ]'

# Automount off: never mounts.
setup exfat 62000000 "snes/A.sfc"
echo "system.automount=0" >>"${TMP}/system.cfg"
run
check "automount off: nothing mounted" '! mounted "${EXT}" && ! [ -e "${LINK}" ]'

exit ${FAILED}
