#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# One-time switch of DuckStation's card 1 from PerGameTitle (named after
# the title in DuckStation's game database) to PerGameFileTitle (named after
# the game file), so the launcher can move saves to and from RetroArch.
# A title-named card would stop loading after the switch, so it happens
# only when no <title>_1.mcd card in the card folder holds a save.
#
# PS1 memory card (128 KiB): frame 0 starts with "MC"; frames 1 to 15
# (128 bytes each, from offset 0x80) are the directory, one per block,
# whose first byte is 0xA0 when the block is free (0x51/0x52/0x53 in use,
# 0xA1/0xA2/0xA3 deleted but still holding data). A card is empty only
# when all 15 are 0xA0. Anything else, or anything unreadable: no switch.
#
#   duckstation_card_filetitle.sh <settings.ini>
# The marker <settings dir>/.archr-card-filetitle records the decision;
# with it present nothing is done again. A read error leaves no marker.

set -u
CONF_FILE="$1"
CONF_DIR=$(dirname "${CONF_FILE}")
MARKER="${CONF_DIR}/.archr-card-filetitle"
[ -e "${MARKER}" ] && exit 0
[ -f "${CONF_FILE}" ] || exit 0

# [MemoryCards] Card1Type and Directory.
setting() {
  sed -n '/^\[MemoryCards\]/,/^\[/{s/^'"$1"'[[:space:]]*=[[:space:]]*//p}' "${CONF_FILE}" | head -n1
}
TYPE=$(setting Card1Type)
if [ "${TYPE}" != "PerGameTitle" ]; then
  echo "kept ${TYPE:-default}" >"${MARKER}"
  exit 0
fi
DIR=$(setting Directory)
DIR="${DIR:-memcards}"
case "${DIR}" in
  /*) ;;
  *) DIR="${CONF_DIR}/${DIR}" ;;
esac

# 0 empty, 1 holds a save, 2 unreadable or not a PS1 card.
card_state() {
  local frames
  [ "$(stat -c %s "$1" 2>/dev/null)" = 131072 ] || return 2
  [ "$(head -c 2 "$1" 2>/dev/null)" = MC ] || return 2
  frames=$(for n in $(seq 1 15); do
    od -An -tx1 -j $((n * 128)) -N1 "$1" 2>/dev/null || echo error
  done | tr -d ' \n')
  [ "${#frames}" = 30 ] || return 2
  [ "${frames}" = "$(printf 'a0%.0s' $(seq 1 15))" ] && return 0
  return 1
}

if [ -d "${DIR}" ]; then
  for card in "${DIR}"/*_1.mcd; do
    [ -e "${card}" ] || continue
    card_state "${card}"
    case $? in
      0) ;;
      1)
        echo "kept PerGameTitle: ${card##*/} holds a save" >"${MARKER}"
        exit 0
        ;;
      *) exit 0 ;;
    esac
  done
fi

TMP="${CONF_FILE}.tmp.$$"
sed '/^\[MemoryCards\]/,/^\[/{s/^Card1Type[[:space:]]*=.*/Card1Type = PerGameFileTitle/}' \
  "${CONF_FILE}" >"${TMP}" && grep -q '^Card1Type = PerGameFileTitle$' "${TMP}" &&
  mv -f "${TMP}" "${CONF_FILE}" && echo "switched to PerGameFileTitle" >"${MARKER}"
rm -f "${TMP}"
