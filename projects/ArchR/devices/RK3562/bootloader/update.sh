#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

# Bootloader update for the RK3562 handhelds. There is no Arch R loader on
# the card (the factory U-Boot on the eMMC boots it), so nothing is written
# to raw sectors: only the DTBs the card already ships are refreshed, and
# extlinux.conf is created when missing. The kernel itself is kept in sync
# by archr-flash-sync.

[ -z "$SYSTEM_ROOT" ] && SYSTEM_ROOT=""
[ -z "$BOOT_ROOT" ] && BOOT_ROOT="/flash"

mount -o remount,rw $BOOT_ROOT

echo -n > $BOOT_ROOT/update.log
log() { echo $*; echo $* >> $BOOT_ROOT/update.log; }
log "Starting bootloader update"

if [ -d $BOOT_ROOT/dtbs ]; then
  log "Updating device trees..."
  for dtb in $SYSTEM_ROOT/usr/share/bootloader/device_trees/*.dtb; do
    [ -f "$dtb" ] || continue
    [ -f "$BOOT_ROOT/dtbs/${dtb##*/}" ] || continue
    cp -f "$dtb" "$BOOT_ROOT/dtbs/${dtb##*/}"
  done
fi

if [ ! -f $BOOT_ROOT/extlinux/extlinux.conf ]; then
  log "Creating extlinux.conf..."
  mkdir -p $BOOT_ROOT/extlinux
  cp -f $SYSTEM_ROOT/usr/share/bootloader/extlinux/* $BOOT_ROOT/extlinux/
fi

log "Finishing bootloader update..."
sync
mount -o remount,ro $BOOT_ROOT

echo "UPDATE" > /storage/.boot.hint
echo "DONE"
