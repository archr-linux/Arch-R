#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# fs-resize ends with a last-resort restart through sysrq. On a host, with
# the real /proc, that restarts the host. Every test that runs fs-resize
# must point SYSRQ_TRIGGER at a file of its own, and fs-resize must write
# the trigger only through that variable. Static check, runs nothing.
#   bash projects/ArchR/packages/archr/tests/fs_resize_sysrq_guard_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "${HERE}/../../../../.." && pwd)
FSR="${TOP}/projects/ArchR/packages/sysutils/busybox/scripts/fs-resize"
FAILED=0
ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }

if grep -q '^: "${SYSRQ_TRIGGER:=/proc/sysrq-trigger}"$' "${FSR}"; then
  ok "fs-resize: the trigger path is SYSRQ_TRIGGER, /proc/sysrq-trigger by default"
else
  fail "fs-resize: no SYSRQ_TRIGGER default"
fi
N=$(grep -c 'sysrq-trigger' "${FSR}")
if [ "${N}" = 1 ]; then
  ok "fs-resize: /proc/sysrq-trigger appears only as that default"
else
  fail "fs-resize: /proc/sysrq-trigger appears ${N} times (only the default may name it)"
fi
if ! grep -nE 'echo [a-z] *>[^$]' "${FSR}" | grep -v 'SYSRQ_TRIGGER' | grep -qi sysrq; then
  ok "fs-resize: every sysrq write goes through \$SYSRQ_TRIGGER"
else
  fail "fs-resize: a sysrq write does not use \$SYSRQ_TRIGGER"
fi

# Every test script, anywhere in the tree, that names fs-resize.
mapfile -t HARNESSES < <(cd "${TOP}" && grep -rlE 'fs-resize' --include='*.sh' . 2>/dev/null |
  grep -E '(^|/)tests?/' | grep -v 'fs_resize_sysrq_guard_test.sh' | grep -v '/build\.' | sort)
if [ "${#HARNESSES[@]}" -gt 0 ]; then
  ok "found ${#HARNESSES[@]} test(s) that run fs-resize"
else
  fail "no test that runs fs-resize found (the search is broken)"
fi
for h in "${HARNESSES[@]}"; do
  if grep -qE 'SYSRQ_TRIGGER=' "${TOP}/${h}"; then
    ok "${h#./}: sets SYSRQ_TRIGGER"
  else
    fail "${h#./}: runs fs-resize without setting SYSRQ_TRIGGER (would restart the host)"
  fi
done

exit "${FAILED}"
