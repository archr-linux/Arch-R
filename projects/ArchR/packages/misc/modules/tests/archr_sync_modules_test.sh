#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-sync-modules (issue #54): the user's own Tools and
# their gamelist entries survive the boot sync; built-ins a release drops
# go away.
#   bash projects/ArchR/packages/misc/modules/tests/archr_sync_modules_test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SYNC="$(dirname "${HERE}")/scripts/archr-sync-modules"
T=$(mktemp -d)
trap 'rm -rf "${T}"' EXIT
FAILED=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi; }
game() { printf '  <game><path>./%s</path><name>%s</name></game>\n' "$1" "$2"; }
gamelist() { { echo '<?xml version="1.0"?>'; echo '<gameList>'; cat; echo '</gameList>'; } >"$1"; }

S="${T}/usr" D="${T}/storage"
mkdir -p "${S}/images" "${D}"
echo built >"${S}/Built.sh"; echo old >"${S}/Old.sh"; echo img >"${S}/images/a.svg"
{ game Built.sh Built; game Old.sh Old; } | gamelist "${S}/gamelist.xml"

# First sync of a console that never had a manifest (the old --delete era).
python3 "${SYNC}" "${S}" "${D}"
check "built-ins copied" '[ -f "${D}/Built.sh" ] && [ -f "${D}/images/a.svg" ]'
check "manifest written" 'grep -qx Built.sh "${D}/.archr-builtin"'

# The user adds a Tool and its entry, and edits a built-in's entry.
echo mine >"${D}/ExampleTool.sh"
{ game Built.sh "Built edited"; game Old.sh Old; game ExampleTool.sh "Example Tool"; game Gone.sh Gone; } | gamelist "${D}/gamelist.xml"

# Next release drops Old.sh; then the boot sync runs.
rm "${S}/Old.sh"; game Built.sh Built | gamelist "${S}/gamelist.xml"
python3 "${SYNC}" "${S}" "${D}"
check "user tool kept" '[ -f "${D}/ExampleTool.sh" ]'
check "user entry kept" 'grep -q "Example Tool" "${D}/gamelist.xml"'
check "dropped built-in removed" '[ ! -e "${D}/Old.sh" ]'
check "its entry removed" '! grep -q ">Old<" "${D}/gamelist.xml"'
check "entry without a file dropped" '! grep -q ">Gone<" "${D}/gamelist.xml"'
check "built-in entry is the built-in one" 'grep -q ">Built<" "${D}/gamelist.xml" && ! grep -q "Built edited" "${D}/gamelist.xml"'
check "one entry per path" '[ "$(grep -c "<path>" "${D}/gamelist.xml")" = 2 ]'

# A second boot changes nothing.
cp "${D}/gamelist.xml" "${T}/before.xml"
python3 "${SYNC}" "${S}" "${D}"
check "stable on a second boot" 'cmp -s "${T}/before.xml" "${D}/gamelist.xml"'
check "user tool still there" '[ -f "${D}/ExampleTool.sh" ]'

# A broken user gamelist never stops the sync.
echo '<gameList><game>' >"${D}/gamelist.xml"
python3 "${SYNC}" "${S}" "${D}"
check "broken gamelist replaced by the built-in" 'grep -q ">Built<" "${D}/gamelist.xml"'
exit ${FAILED}
