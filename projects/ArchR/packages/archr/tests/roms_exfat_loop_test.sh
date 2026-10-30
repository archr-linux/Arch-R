#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# The ROMs partition on real block devices: sparse card images on loop
# devices, the host's kernel exFAT/ext4 drivers and tools, and the real
# fs-resize, init (mount_roms) and archr-roms-migrate run in a chroot whose
# /usr is an overlay of the host's (reboot is a stub there). Needs root.
# Touches only the loop devices it attaches to its own images.
#
#   sudo bash projects/ArchR/packages/archr/tests/roms_exfat_loop_test.sh [WORKDIR]
#
# Cards: 32 GB (31.9 GB, the usual "32 GB") and 64 GB, first boot; an 8 GB
# card (too small: old layout); a first boot whose mkfs.exfat fails (falls
# back); migration of an old-layout 64 GB card; a migration cut in the
# middle of a file copy and one cut right after the shrink, both retaken.

# The checks are strings run by eval: variables they read look unused.
# shellcheck disable=SC2034
set -u
[ "$(id -u)" = 0 ] || { echo "run as root (loop devices)"; exit 2; }
# Private mounts: nothing leaks to the host's mount table.
if [ -z "${ROMS_LOOP_NS:-}" ]; then
  ROMS_LOOP_NS=1 exec unshare -m --propagation private bash "$0" "$@"
fi
HERE=$(cd "$(dirname "$0")" && pwd)
PKGS=$(cd "${HERE}/../.." && pwd)
BB="${PKGS}/sysutils/busybox/scripts"
MIGRATE="${PKGS}/archr/sources/scripts/archr-roms-migrate"
W=$(mktemp -d "${1:-/var/tmp}/roms-exfat-loop.XXXXXX")
R="${W}/root"
FAILED=0
LOOPS=()
PROGRESS_DIR_EXISTED=
[ -e /dev/.progress ] && PROGRESS_DIR_EXISTED=1

ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
note() { echo "# $*"; }

cleanup() {
  local l m
  umount -R -l "${R}" 2>/dev/null
  for m in $(awk -v r="${W}" 'index($2, r) == 1 { print $2 }' /proc/self/mounts | sort -r); do
    umount -l "${m}" 2>/dev/null
  done
  for l in "${LOOPS[@]}"; do losetup -d "${l}" 2>/dev/null; done
  [ -n "${PROGRESS_DIR_EXISTED}" ] || rm -rf /dev/.progress
  # Never delete through a mount (the chroot binds the host's /dev).
  if awk -v r="${W}" 'index($2, r) == 1 { found = 1 } END { exit !found }' /proc/self/mounts; then
    echo "mounts left under ${W}; not deleting it"
  else
    rm -rf --one-file-system "${W}"
  fi
}
trap cleanup EXIT

### Chroot: the host's /usr through an overlay, plus the ArchR scripts.
mkdir -p "${R}" "${W}/up" "${W}/wk"
mount -t tmpfs tmpfs "${R}"
mkdir -p "${R}"/{usr,etc,dev,proc,sys,run,tmp,storage,flash,opt/cut}
ln -s usr/bin "${R}/bin"; ln -s usr/bin "${R}/sbin"; ln -s usr/lib "${R}/lib"; ln -s usr/lib "${R}/lib64"
mount -t overlay overlay -o "lowerdir=/usr,upperdir=${W}/up,workdir=${W}/wk" "${R}/usr"
mount --bind /etc "${R}/etc"; mount -o remount,bind,ro "${R}/etc"
mount --rbind /dev "${R}/dev"
mount -t proc proc "${R}/proc"
mount --rbind /sys "${R}/sys"; mount -o remount,bind,ro "${R}/sys"
mount -t tmpfs tmpfs "${R}/run"
mount -t tmpfs tmpfs "${R}/tmp"
rm -f "${R}/usr/bin/reboot" "${R}/usr/bin/poweroff"
printf '#!/bin/sh\necho "reboot stub $*"\n' >"${R}/usr/bin/reboot"
cp "${R}/usr/bin/reboot" "${R}/usr/bin/poweroff"
chmod +x "${R}/usr/bin/reboot" "${R}/usr/bin/poweroff"
if [ "$(chroot "${R}" /usr/bin/reboot -f)" != "reboot stub -f" ]; then
  echo "reboot is not stubbed in the chroot; stopping"; exit 2
fi
mkdir -p "${R}/usr/lib/archr"
cp "${BB}/functions" "${BB}/roms-partition" "${R}/usr/lib/archr/"
sed 's/@DISTRONAME@/ArchR/g' "${BB}/fs-resize" >"${R}/usr/lib/archr/fs-resize"
cp "${MIGRATE}" "${R}/usr/bin/archr-roms-migrate"
chmod +x "${R}/usr/lib/archr/fs-resize" "${R}/usr/bin/archr-roms-migrate"
printf '#!/bin/sh\nsleep "$(awk -v u="$1" "BEGIN { print u / 1000000 }")"\n' >"${R}/usr/bin/usleep"
chmod +x "${R}/usr/bin/usleep"
# mount_roms, cut out of the initramfs init.
{
  echo 'progress() { echo "### $1 ###"; }'
  sed -n '/^ROMS_MOUNT_OPTS=/,/^}/p' "${BB}/init"
  echo 'mount_roms'
} >"${R}/usr/lib/archr/mount_roms.sh"
# A resize2fs that dies, with the whole migration, right after the shrink.
cat >"${R}/opt/cut/resize2fs" <<'EOF'
#!/bin/sh
/usr/bin/resize2fs "$@"; rc=$?
if [ "$1" = -p ] && [ -f /tmp/cut-after-shrink ]; then rm -f /tmp/cut-after-shrink; kill -9 0; fi
exit $rc
EOF
chmod +x "${R}/opt/cut/resize2fs"
inr() { chroot "${R}" /usr/bin/env PATH=/opt/cut:/usr/bin LC_ALL=C "$@"; }

### Cards. $1 image, $2 size in bytes, $3 "new" (as flashed: STORAGE 32 MiB
### and .please_resize_me) or "old" (an old card: STORAGE to the end).
attach() {
  local l
  l=$(losetup --find --show -P "$1") || return 1
  case ${l} in /dev/loop[0-9]*) ;; *) echo "unexpected loop ${l}"; exit 2 ;; esac
  LOOPS+=("${l}")
  udevadm settle 2>/dev/null
  echo "${l}"
}
detach() { losetup -d "$1"; }

make_card() {
  local img=$1 bytes=$2 kind=$3 l end
  truncate -s "${bytes}" "${img}"
  parted -s "${img}" mklabel msdos
  if [ "${kind}" = new ]; then end=$(( 9994240 + 65536 - 1 )); else end=100%; fi
  parted -s -a min "${img}" unit s mkpart primary fat32 32768 557055 \
    mkpart primary ext4 557056 9994239 mkpart primary ext4 9994240 "${end}$( [ "${end}" = 100% ] || echo s)"
  parted -s "${img}" set 1 boot on
  l=$(attach "${img}")
  mkfs.vfat -F 32 -n ARCHR "${l}p1" >/dev/null
  mkfs.ext4 -q -F -L ARCHR_ROOT -i 1048576 "${l}p2"
  mkfs.ext4 -q -F -L STORAGE -i 262144 "${l}p3"
  if [ "${kind}" = new ]; then
    mount "${l}p3" "${R}/storage" && touch "${R}/storage/.please_resize_me" && umount "${R}/storage"
  fi
  detach "${l}"
}

boot_mounts() { mount -o rw,noatime "$1p3" "${R}/storage" && mount -o ro "$1p1" "${R}/flash"; }
boot_umounts() { umount -R "${R}/storage" 2>/dev/null; umount "${R}/flash" 2>/dev/null; }

sectors() { echo $(( $(blockdev --getsz "$1") )); }
ptype() { sfdisk --part-type "$1" "$2" 2>/dev/null; }

first_boot() {
  local name=$1 bytes=$2 img="${W}/$1.img" l
  note "first boot: ${name}"
  make_card "${img}" "${bytes}" new
  l=$(attach "${img}")
  boot_mounts "${l}"
  inr /usr/lib/archr/fs-resize >"${W}/${name}.fs-resize.out" 2>&1
  boot_umounts
  detach "${l}"; l=$(attach "${img}")
  FB_LOOP=${l}
}

### 1. First boot, 32 GB and 64 GB: STORAGE 8 GiB, ARCHR_ROMS the rest.
for card in 32:31914983424 64:63864569856; do
  name=card${card%%:*}; bytes=${card#*:}
  first_boot "${name}" "${bytes}"
  l=${FB_LOOP}
  check "${name}: four partitions" '[ -b "${l}p4" ]'
  check "${name}: STORAGE is 8 GiB" '[ "$(sectors "${l}p3")" = 16777216 ]'
  check "${name}: ext4 fills STORAGE and is clean" '[ $(( $(dumpe2fs -h "${l}p3" 2>/dev/null | awk -F: "/^Block count/ {print \$2}") * 8 )) = 16777216 ] && e2fsck -f -n "${l}p3" >/dev/null 2>&1'
  check "${name}: ARCHR_ROMS is exFAT, labelled, type 0x07, clean" '[ "$(blkid -o value -s TYPE "${l}p4")" = exfat ] && [ "$(blkid -o value -s LABEL "${l}p4")" = ARCHR_ROMS ] && [ "$(ptype "${l}" 4)" = 7 ] && fsck.exfat -n "${l}p4" >/dev/null 2>&1'
  check "${name}: ARCHR_ROMS reaches the end of the card" '[ $(( $(cat /sys/class/block/${l##*/}p4/start) + $(sectors "${l}p4") )) -gt $(( $(sectors "${l}") - 2048 )) ]'
  note "${name}: ARCHR_ROMS $(( $(sectors "${l}p4") / 2048 )) MiB"

  # The initramfs step.
  boot_mounts "${l}"
  inr sh /usr/lib/archr/mount_roms.sh >"${W}/${name}.mount.out" 2>&1
  OPTS=$(awk -v p="${R}/storage/roms" '$2 == p { print $4 }' /proc/self/mounts)
  check "${name}: mount_roms mounts it on /storage/roms" '[ "$(awk -v p="${R}/storage/roms" "\$2 == p { print \$3 }" /proc/self/mounts)" = exfat ]'
  check "${name}: mount options (root, 0755/0755, utf8, noatime, remount-ro on errors)" 'grep -q "fmask=0022" <<<"${OPTS}" && grep -q "dmask=0022" <<<"${OPTS}" && grep -q noatime <<<"${OPTS}" && grep -q "errors=remount-ro" <<<"${OPTS}" && grep -q "iocharset=utf8" <<<"${OPTS}"'
  check "${name}: a clean card is not checked" '[ "$(cat "${R}/run/archr/roms-fs")" = clean ]'
  # How the system uses it.
  D="${R}/storage/roms"
  mkdir -p "${D}/nes" && echo x >"${D}/nes/a.nes"
  check "${name}: tmpfiles' d 0777 root root works on a folder" 'chmod 0777 "${D}/nes" && chown 0:0 "${D}/nes"'
  check "${name}: files are 0755 root, modules can read them" '[ "$(stat -c %a:%u "${D}/nes/a.nes")" = 755:0 ]'
  check "${name}: chmod 0644 is refused (why the tmpfiles note has no mode)" '! chmod 0644 "${D}/nes/a.nes" 2>/dev/null'
  check "${name}: chmod +x is a no-op that works (PortMaster)" 'chmod +x "${D}/nes/a.nes"'
  check "${name}: no symbolic links (why flycast had to change)" '! ln -s a.nes "${D}/nes/link" 2>/dev/null'
  check "${name}: names differ only in case are one file" 'echo y >"${D}/nes/A.NES" && [ "$(cat "${D}/nes/a.nes")" = y ]'
  check "${name}: a colon is refused (why the scraper must sanitize)" '! touch "${D}/nes/Zelda: A.png" 2>/dev/null'
  check "${name}: files over 4 GiB" 'timeout 120 truncate -s 4600M "${D}/big.iso" && [ "$(stat -c %s "${D}/big.iso")" = 4823449600 ] && rm -f "${D}/big.iso"'
  check "${name}: rename over an existing file (atomic config writes)" 'echo new >"${D}/nes/t.tmp" && mv -f "${D}/nes/t.tmp" "${D}/nes/a.nes" && [ "$(cat "${D}/nes/a.nes")" = new ]'
  # Dirty volume: what the kernel leaves when power goes with unsynced data.
  boot_umounts
  printf '\002\000' | dd of="${l}p4" bs=1 seek=106 conv=notrunc status=none
  boot_mounts "${l}"
  rm -f "${R}/run/archr/roms-fs"
  inr sh /usr/lib/archr/mount_roms.sh >>"${W}/${name}.mount.out" 2>&1
  check "${name}: a dirty card is checked before the mount" 'grep -Eq "^(checked|repaired)$" "${R}/run/archr/roms-fs" && mountpoint -q "${R}/storage/roms"'
  boot_umounts
  check "${name}: and the check clears the dirty flag" '[ "$(dd if="${l}p4" bs=1 skip=106 count=1 status=none | od -An -tu1 | tr -d " ")" = 0 ]'
  # The migration skips a card that already has the partition.
  boot_mounts "${l}"
  OUT=$(inr archr-roms-migrate check)
  check "${name}: archr-roms-migrate sees the new layout" 'grep -qx LAYOUT=exfat <<<"${OUT}"'
  boot_umounts
  detach "${l}"
done

### 2. 8 GB card: no room for 8 GiB of STORAGE and 2 GiB of ROMs.
first_boot card8 7948206080
l=${FB_LOOP}
check "card8: keeps the old layout (three partitions, STORAGE to the end)" '[ ! -b "${l}p4" ] && [ $(( $(cat /sys/class/block/${l##*/}p3/start) + $(sectors "${l}p3") )) -gt $(( $(sectors "${l}") - 2048 )) ]'
check "card8: ext4 grown and clean" 'e2fsck -f -n "${l}p3" >/dev/null 2>&1'
detach "${l}"

### 3. First boot with a failing mkfs.exfat: back to the old layout.
mv "${R}/usr/bin/mkfs.exfat" "${R}/usr/bin/mkfs.exfat.real"
printf '#!/bin/sh\nexit 1\n' >"${R}/usr/bin/mkfs.exfat"; chmod +x "${R}/usr/bin/mkfs.exfat"
first_boot cardfail 31914983424
l=${FB_LOOP}
check "mkfs fails: partition 4 removed" '[ ! -b "${l}p4" ]'
check "mkfs fails: STORAGE grown to the end, ext4 too, clean" '[ $(( $(cat /sys/class/block/${l##*/}p3/start) + $(sectors "${l}p3") )) -gt $(( $(sectors "${l}") - 2048 )) ] && [ $(( $(dumpe2fs -h "${l}p3" 2>/dev/null | awk -F: "/^Block count/ {print \$2}") * 8 )) -ge $(( $(sectors "${l}p3") - 8 )) ] && e2fsck -f -n "${l}p3" >/dev/null 2>&1'
detach "${l}"
mv -f "${R}/usr/bin/mkfs.exfat.real" "${R}/usr/bin/mkfs.exfat"

### 4. Migration of an old 64 GB card.
populate() {
  local s=${R}/storage r=${R}/storage/roms i
  mkdir -p "${s}/.config/system" "${s}/.cache" "${r}"/{nes,snes/media/covers,bios/dc,savestates/nes,dreamcast,psx}
  echo "system.language=pt_BR" >"${s}/.config/system/system.cfg"
  head -c 200000000 /dev/urandom >"${r}/psx/Big Game (USA).bin"
  for i in $(seq 1 1500); do head -c $(( (i % 7 + 1) * 1000 )) /dev/urandom >"${r}/nes/game${i}.nes"; done
  head -c 5000 /dev/urandom >"${r}/nes/Mario.zip"; head -c 5001 /dev/urandom >"${r}/nes/mario.zip"
  head -c 7000 /dev/urandom >"${r}/snes/Zelda: A Link.sfc"
  head -c 900 /dev/urandom >"${r}/snes/media/covers/Zelda: A Link.png"
  head -c 2048 /dev/urandom >"${r}/bios/dc/dc_boot.bin"
  head -c 4096 /dev/urandom >"${r}/savestates/nes/game1.state1"
  ln -s ../bios/dc "${r}/dreamcast/data"
}
sums() { (cd "$1" && find . -path ./.archr-migrate-tmp -prune -o -type f -print0 | sort -z | xargs -0 md5sum | sort -k2); }
expected() { sums "$1" | sed -e 's#Zelda: A Link#Zelda_ A Link#' -e 's#\./nes/mario\.zip#./nes/mario (2).zip#' | sort -k2; }
NEW_IN_R=/run/archr/roms-migrate/roms

migrate_card() {   # $1 name, $2 bytes; leaves MC_LOOP attached, storage mounted
  local img="${W}/$1.img" l
  make_card "${img}" "$2" old
  l=$(attach "${img}")
  boot_mounts "${l}"
  populate
  BEFORE=$(expected "${R}/storage/roms")
  MC_LOOP=${l}
}

final_checks() {   # $1 name
  local l=$2
  boot_umounts
  detach "${l}"; l=$(attach "${W}/$1.img")
  check "$1: four partitions, STORAGE 8 GiB" '[ -b "${l}p4" ] && [ "$(sectors "${l}p3")" = 16777216 ]'
  check "$1: ext4 clean after the shrink" 'e2fsck -f -n "${l}p3" >/dev/null 2>&1'
  check "$1: exFAT clean" 'fsck.exfat -n "${l}p4" >/dev/null 2>&1'
  boot_mounts "${l}"
  inr sh /usr/lib/archr/mount_roms.sh >/dev/null 2>&1
  AFTER=$(sums "${R}/storage/roms")
  check "$1: every ROM, save and BIOS intact on exFAT" '[ -n "${AFTER}" ] && [ "${BEFORE}" = "${AFTER}" ]'
  check "$1: no temporary folder left" '[ ! -e "${R}/storage/roms/.archr-migrate-tmp" ]'
  umount "${R}/storage/roms"
  check "$1: nothing left in the ext4 roms folder" '[ -z "$(ls -A "${R}/storage/roms")" ]'
  check "$1: configs untouched" 'grep -q pt_BR "${R}/storage/.config/system/system.cfg"'
  check "$1: marker gone, log written" '[ ! -e "${R}/storage/.roms-migrate" ] && grep -q "Done:" "${R}/storage/.cache/roms-migrate.log"'
  boot_umounts
  detach "${l}"
}

migrate_card mig64 63864569856
l=${MC_LOOP}
OUT=$(inr archr-roms-migrate check); RC=$?
note "preview: $(tr '\n' ' ' <<<"${OUT}")"
check "mig64: preview allows it" '[ ${RC} = 0 ] && grep -qx RESULT=ok <<<"${OUT}" && grep -qx STORAGE_AFTER_MIB=8192 <<<"${OUT}"'
inr archr-roms-migrate start >/dev/null
check "mig64: armed" 'grep -qx STATE=armed "${R}/storage/.roms-migrate"'
START=$(date +%s)
inr env ROMS_MIGRATE_NOREBOOT=1 archr-roms-migrate run >"${W}/mig64.run.out" 2>&1
note "mig64: run took $(( $(date +%s) - START )) s"
final_checks mig64 "${l}"

### 5. Not enough room: the preview refuses, the card is untouched.
make_card "${W}/full.img" 31914983424 old
l=$(attach "${W}/full.img")
boot_mounts "${l}"
mkdir -p "${R}/storage/roms/ps2"
head -c 20000000 /dev/urandom >"${R}/storage/roms/ps2/a.iso"
truncate -s 18G "${R}/storage/roms/ps2/b.iso"   # apparent 18 GiB: an exFAT copy needs it all
OUT=$(inr archr-roms-migrate check); RC=$?
check "full: refused for lack of room" '[ ${RC} = 1 ] && grep -qx RESULT=no-space <<<"${OUT}"'
check "full: start refuses too" '! inr archr-roms-migrate start >/dev/null && [ ! -e "${R}/storage/.roms-migrate" ]'
boot_umounts; detach "${l}"

### 6. Cut in the middle of a file copy, then the next boot.
migrate_card cut32 31914983424
l=${MC_LOOP}
inr archr-roms-migrate start >/dev/null
setsid chroot "${R}" /usr/bin/env PATH=/usr/bin LC_ALL=C ROMS_MIGRATE_NOREBOOT=1 archr-roms-migrate run >"${W}/cut32.run.out" 2>&1 &
PID=$!
for _ in $(seq 1 1200); do
  [ -n "$(find "${R}${NEW_IN_R}/.archr-migrate-tmp" -type f -size +1M 2>/dev/null)" ] && break
  sleep 0.05
done
kill -9 -- -"${PID}" 2>/dev/null; wait "${PID}" 2>/dev/null
check "cut32: cut while a big file was being copied" '[ -n "$(find "${R}${NEW_IN_R}/.archr-migrate-tmp" -type f 2>/dev/null)" ]'
check "cut32: marker says copying" 'grep -qx STATE=copying "${R}/storage/.roms-migrate"'
# Power gone: the exFAT volume is left as it was, dirty.
umount -l "${R}${NEW_IN_R}" 2>/dev/null
boot_umounts
printf '\002\000' | dd of="${l}p4" bs=1 seek=106 conv=notrunc status=none
detach "${l}"; l=$(attach "${W}/cut32.img")
boot_mounts "${l}"
inr sh /usr/lib/archr/mount_roms.sh >/dev/null 2>&1
check "cut32: next boot, init leaves ARCHR_ROMS alone while migrating" '! mountpoint -q "${R}/storage/roms"'
inr env ROMS_MIGRATE_NOREBOOT=1 archr-roms-migrate run >"${W}/cut32.resume.out" 2>&1
check "cut32: resume finishes" '[ ! -e "${R}/storage/.roms-migrate" ]'
final_checks cut32 "${l}"

### 7. Cut right after the shrink (before partition 3 is resized).
migrate_card shrink32 31914983424
l=${MC_LOOP}
inr archr-roms-migrate start >/dev/null
touch "${R}/tmp/cut-after-shrink"
setsid chroot "${R}" /usr/bin/env PATH=/opt/cut:/usr/bin LC_ALL=C ROMS_MIGRATE_NOREBOOT=1 archr-roms-migrate run >"${W}/shrink32.run.out" 2>&1
check "shrink32: cut after the shrink" '[ ! -e "${R}/tmp/cut-after-shrink" ] && ! [ -b "${l}p4" ]'
boot_umounts
detach "${l}"; l=$(attach "${W}/shrink32.img")
check "shrink32: ext4 still clean" 'e2fsck -f -n "${l}p3" >/dev/null 2>&1'
boot_mounts "${l}"
inr env ROMS_MIGRATE_NOREBOOT=1 archr-roms-migrate run >"${W}/shrink32.resume.out" 2>&1
check "shrink32: resume finishes" '[ ! -e "${R}/storage/.roms-migrate" ]'
final_checks shrink32 "${l}"

for f in "${W}"/*.out; do echo "## ${f##*/}"; tail -n 5 "${f}"; done
exit ${FAILED}
