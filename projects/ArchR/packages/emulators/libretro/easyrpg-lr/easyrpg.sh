#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021-present 351ELEC (https://github.com/351ELEC)
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)

# The RPG Maker 2000 and 2003 run-time packages (RTP), which most games
# need, downloaded once into the core's system folder
# (rtp/2000, rtp/2003). Each one is taken into a temporary folder and
# moved into place only when complete: a failed download leaves nothing,
# and the next game tries again (an empty folder, as an older version of
# this script left when the download failed, counts as missing).

. "${EASYRPG_PROFILE:-/etc/profile}"

DEST="${EASYRPG_RTP:-/storage/roms/bios/rtp}"
# The publisher's own address, then its older mirror (dl.degica.com, the
# address used before, no longer exists).
URLS="${EASYRPG_RTP_URLS:-https://assets.rpgmakerweb.com https://dl.komodo.jp/rpgmakerweb/run-time-packages}"
VIEWER="${EASYRPG_VIEWER:-text_viewer}"

declare -A SHA256=(
  [rpg2000_rtp_installer.exe]=ec82b92da65ca6fdb2d3df25dfbcd7f2bb716e4fe63a079e8e5e396e91fa5e29
  [rpg2003_rtp_installer.zip]=ddd519b50a22a2a95beeb831d29f7d7d92ae6263f953491163b446b808b66863
)

installed() {
  [ -n "$(find "${DEST}/$1" -type f -print -quit 2>/dev/null)" ]
}

# install FILE VERSION
install_rtp() {
  local file=$1 version=$2 tmp url ok=""
  tmp=$(mktemp -d "${DEST}/.${version}.XXXXXX") || return 1
  for url in ${URLS}; do
    if curl -fsSL --connect-timeout 10 -o "${tmp}/${file}" "${url}/${file}" &&
       [ "$(sha256sum "${tmp}/${file}" | cut -d' ' -f1)" = "${SHA256[${file}]}" ]; then
      ok=1
      break
    fi
  done
  if [ -n "${ok}" ] && (
       cd "${tmp}" || exit 1
       if [[ "${file}" == *.zip ]]; then
         7z x -y "${file}" >/dev/null || exit 1
         rm -f "${file}"
         file=${file%.zip}.exe
       fi
       7z x -y "${file}" >/dev/null || exit 1
       rm -f "${file}"
     ) && [ -n "$(find "${tmp}" -type f -print -quit)" ]; then
    rm -rf "${DEST:?}/${version}"
    mv "${tmp}" "${DEST}/${version}"
    return 0
  fi
  rm -rf "${tmp}"
  return 1
}

installed 2000 && installed 2003 && exit 0

mkdir -p "${DEST}" || exit 1
clear >/dev/console 2>&1
echo "Downloading the RPG Maker run-time files, please be patient..." >/dev/console 2>&1
failed=""
installed 2000 || install_rtp rpg2000_rtp_installer.exe 2000 || failed=1
installed 2003 || install_rtp rpg2003_rtp_installer.zip 2003 || failed=1
clear >/dev/console 2>&1
if [ -n "${failed}" ]; then
  "${VIEWER}" -e -w -t "RPG Maker run-time files" -m "Could not download the RPG Maker run-time files. Connect to the internet and open the game again." 2>/dev/null
  exit 1
fi
exit 0
