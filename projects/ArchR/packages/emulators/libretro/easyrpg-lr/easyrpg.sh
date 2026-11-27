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
# The screen before the game (archr-osd) while they come down; B cancels.
PREPARE="${EASYRPG_PREPARE:-/usr/bin/archr-prepare}"
TITLE="${1:-RPG Maker}"
STEPS=""

declare -A SHA256=(
  [rpg2000_rtp_installer.exe]=ec82b92da65ca6fdb2d3df25dfbcd7f2bb716e4fe63a079e8e5e396e91fa5e29
  [rpg2003_rtp_installer.zip]=ddd519b50a22a2a95beeb831d29f7d7d92ae6263f953491163b446b808b66863
)
declare -A SIZE=(
  [rpg2000_rtp_installer.exe]=10609639
  [rpg2003_rtp_installer.zip]=13268108
)

# fetch FILE URL OUT VERSION: curl, through the screen when there is one;
# 130 when B stopped it.
fetch() {
  local file=$1 url=$2 out=$3 version=$4 n=0 word
  if [ ! -x "${PREPARE}" ] || [ -z "${STEPS}" ]; then
    curl -fsSL --connect-timeout 10 -o "${out}" "${url}/${file}"
    return
  fi
  for word in ${STEPS//|/ }; do
    [ "${word}" = "rtp:${version}" ] && break
    n=$((n + 1))
  done
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" "${PREPARE}" \
    --title "${TITLE}" --steps "${STEPS}" --step "${n}" \
    --watch "${out}" --total "${SIZE[${file}]}" -- \
    curl -fsSL --connect-timeout 10 -o "${out}" "${url}/${file}"
}

installed() {
  [ -n "$(find "${DEST}/$1" -type f -print -quit 2>/dev/null)" ]
}

# install FILE VERSION
install_rtp() {
  local file=$1 version=$2 tmp url ok=""
  tmp=$(mktemp -d "${DEST}/.${version}.XXXXXX") || return 1
  for url in ${URLS}; do
    fetch "${file}" "${url}" "${tmp}/${file}" "${version}"
    case $? in
    0) ;;
    130)
      rm -rf "${tmp}"
      return 130
      ;;
    *) continue ;;
    esac
    if [ "$(sha256sum "${tmp}/${file}" | cut -d' ' -f1)" = "${SHA256[${file}]}" ]; then
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
steps=()
installed 2000 || steps+=(rtp:2000)
installed 2003 || steps+=(rtp:2003)
STEPS=$(IFS='|'; echo "${steps[*]}")
failed=""
for version in 2000 2003; do
  installed "${version}" && continue
  file=rpg2000_rtp_installer.exe
  [ "${version}" = 2003 ] && file=rpg2003_rtp_installer.zip
  install_rtp "${file}" "${version}"
  case $? in
  0) ;;
  130)
    [ -x "${PREPARE}" ] && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" "${PREPARE}" --end
    exit 130
    ;;
  *) failed=1 ;;
  esac
done
[ -x "${PREPARE}" ] && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" "${PREPARE}" --end
if [ -n "${failed}" ]; then
  "${VIEWER}" -e -w -t "RPG Maker run-time files" -m "Could not download the RPG Maker run-time files. Connect to the internet and open the game again." 2>/dev/null
  exit 1
fi
exit 0
