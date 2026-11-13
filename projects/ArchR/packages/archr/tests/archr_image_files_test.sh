#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-image-files: staged files from four packages in a
# fake root, with a stale file, a missing one, a link, a file a package
# owns and one two packages disagree on.
#   bash projects/ArchR/packages/archr/tests/archr_image_files_test.sh

# Checks are eval'd strings: variables are read only there.
# shellcheck disable=SC2016
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/archr-image-files"
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

R="${T}/root"
A="${R}/usr/share/archr/image-files/archr"
Q="${R}/usr/share/archr/image-files/quirks"
B="${R}/usr/share/archr/image-files/busybox"
L="${R}/usr/share/archr/image-files/linux"
mkdir -p "${A}/etc/profile.d" "${A}/usr/lib/systemd/system/archr.target.wants" \
  "${Q}/etc/profile.d" "${B}/usr/lib/sysctl.d" "${L}/usr/lib/sysctl.d" \
  "${A}/usr/lib/autostart/common" \
  "${R}/etc/profile.d" "${R}/usr/lib/sysctl.d" "${R}/usr/lib/systemd/system"

echo new >"${A}/etc/profile.d/100-gamecontroller-functions"
echo old >"${R}/etc/profile.d/100-gamecontroller-functions"
echo unit >"${A}/usr/lib/systemd/system/archr-boot-trace.service"
ln -s ../archr-boot-trace.service "${A}/usr/lib/systemd/system/archr.target.wants/archr-boot-trace.service"
printf '#!/bin/sh\n' >"${A}/usr/lib/autostart/common/001-setup"
chmod 0755 "${A}/usr/lib/autostart/common/001-setup"
echo same >"${Q}/etc/profile.d/999-export"
echo same >"${R}/etc/profile.d/999-export"
touch -d 2020-01-01 "${R}/etc/profile.d/999-export"
echo staged >"${A}/etc/profile.d/050-owned"
echo package >"${R}/etc/profile.d/050-owned"
echo busybox >"${B}/usr/lib/sysctl.d/memory.conf"
echo linux >"${L}/usr/lib/sysctl.d/memory.conf"
echo linux >"${R}/usr/lib/sysctl.d/memory.conf"

printf '/etc/\n/etc/profile.d/\n/etc/profile.d/050-owned\n' >"${T}/owned"

ARCHR_ROOT="${R}" ARCHR_OWNED="${T}/owned" sh "${SCRIPT}" >"${T}/out" 2>&1
RC=$?

check "exits 0" '[ "${RC}" = 0 ]'
check "a stale file is replaced" '[ "$(cat "${R}/etc/profile.d/100-gamecontroller-functions")" = new ]'
check "a missing unit is added" '[ "$(cat "${R}/usr/lib/systemd/system/archr-boot-trace.service")" = unit ]'
check "its wants link is added as a link" \
  '[ "$(readlink "${R}/usr/lib/systemd/system/archr.target.wants/archr-boot-trace.service")" = ../archr-boot-trace.service ]'
check "an autostart script keeps its mode" '[ -x "${R}/usr/lib/autostart/common/001-setup" ]'
check "an identical file is not rewritten" \
  '[ "$(stat -c %Y "${R}/etc/profile.d/999-export")" = "$(date -d 2020-01-01 +%s)" ]'
check "a file a package owns is left alone" '[ "$(cat "${R}/etc/profile.d/050-owned")" = package ]'
check "a file two packages disagree on is left alone" '[ "$(cat "${R}/usr/lib/sysctl.d/memory.conf")" = linux ]'
check "the disagreement is logged" 'grep -q "memory.conf: packages disagree" "${T}/out"'
check "each written file is logged" '[ "$(grep -c "(archr)$" "${T}/out")" = 4 ]'
check "no temporary file is left" '! find "${R}" -name ".archr-image-files.*" | grep -q .'

# A second run finds nothing to do.
ARCHR_ROOT="${R}" ARCHR_OWNED="${T}/owned" sh "${SCRIPT}" >"${T}/out2" 2>&1
check "a second run writes nothing" '! grep -q "(archr)$" "${T}/out2"'

# No staged files at all: nothing to do, no error.
ARCHR_ROOT="${T}/empty" ARCHR_OWNED="${T}/owned" sh "${SCRIPT}"
RC=$?
check "no image-files folder: exits 0" '[ "${RC}" = 0 ]'

exit "${FAILED}"
