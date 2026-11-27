#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

# Host test for runemu.sh tools_view and portmaster_installer: the view
# behind /opt/system/Tools is made anew each time (a PortMaster unpacked
# into it by an installer is gone, Arch R's is linked), and PortMaster's
# own Makeself installers are told apart from port scripts, so they run
# without the view and install into /roms/ports instead of /run.
#   bash projects/ArchR/packages/archr/tests/runemu_tools_view_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RUNEMU="${HERE}/../sources/scripts/runemu.sh"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "     got:      $2"
    echo "     expected: $3"
    FAILED=1
  fi
}

TOOLS_VIEW="${TMP}/run/archr/tools"
TOOLS_ROMS="${TMP}/roms"
eval "$(sed -n '/^function tools_view() {/,/^}/p; /^function portmaster_installer() {/,/^}/p' "${RUNEMU}")"

mkdir -p "${TOOLS_ROMS}/tools/Wifi" "${TOOLS_ROMS}/tools/PortMaster" "${TOOLS_ROMS}/ports/PortMaster"
: > "${TOOLS_ROMS}/tools/Backup.sh"
mkdir -p "${TOOLS_VIEW}/PortMaster/runtimes"
: > "${TOOLS_VIEW}/PortMaster/runtimes/big.squashfs"
: > "${TOOLS_VIEW}/PortMaster.sh"
tools_view
check "a PortMaster an installer left in the view is gone" \
  "$(readlink "${TOOLS_VIEW}/PortMaster")" "${TOOLS_ROMS}/ports/PortMaster"
check "and so is its PortMaster.sh" "$([ -e "${TOOLS_VIEW}/PortMaster.sh" ] && echo left || echo gone)" "gone"
check "tools are linked" "$(readlink "${TOOLS_VIEW}/Wifi") $(readlink "${TOOLS_VIEW}/Backup.sh")" \
  "${TOOLS_ROMS}/tools/Wifi ${TOOLS_ROMS}/tools/Backup.sh"
check "the card's own PortMaster is not" "$(ls "${TOOLS_VIEW}" | tr '\n' ' ')" "Backup.sh PortMaster Wifi "
check "the tools themselves are untouched" "$(ls "${TOOLS_ROMS}/tools" | tr '\n' ' ')" "Backup.sh PortMaster Wifi "

makeself() {
  printf '#!/bin/bash\n# This script was generated using Makeself 2.5.0\nMD5="x"\n'
  printf 'if [ -d "/roms2/ports/" ]; then\n  TMPROOT="/roms2/ports"\nfi\n'
  printf 'label="%s"\nscript="./installer.sh"\n' "$1"
  head -c 2048 /dev/urandom
}
makeself "PortMaster Full Installer" > "${TMP}/Install.Full.PortMaster.sh"
makeself "PortMaster Installer" > "${TMP}/Install.PortMaster.sh"
makeself "Some Game" > "${TMP}/Other.sh"
printf '#!/bin/bash\n# PORTMASTER: game.zip, Game.sh\ncontrolfolder="/opt/system/Tools/PortMaster"\nlabel="PortMaster Installer"\n' > "${TMP}/Game.sh"
for f in Install.Full.PortMaster.sh Install.PortMaster.sh Other.sh Game.sh; do
  r="${r:-}${f}=$(portmaster_installer "${TMP}/${f}" && echo yes || echo no) "
done
check "PortMaster's installers are told apart from ports" "${r}" \
  "Install.Full.PortMaster.sh=yes Install.PortMaster.sh=yes Other.sh=no Game.sh=no "
exit "${FAILED}"
