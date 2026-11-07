#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Source predefined functions and variables
. /etc/profile
set_kill set "-9 yabasanshiro"

ROM_DIR="/storage/roms/saturn/yabasanshiro"
CONFIG_DIR="/storage/.config/yabasanshiro"
SOURCE_DIR="/usr/config/yabasanshiro"
BIOS_BACKUP="/storage/roms/bios/yabasanshiro"
SAVESTATE_DIR="/storage/roms/savestates/saturn/yabasanshiro/"

if [ ! -d "${ROM_DIR}" ]
then
  mkdir -p "${ROM_DIR}"
fi

if [ ! -d "${BIOS_BACKUP}" ]
then
  mkdir -p "${BIOS_BACKUP}"
fi

if [ ! -d "${CONFIG_DIR}" ]
then
  mkdir -p "${CONFIG_DIR}"
fi

if [ ! -d "${SAVESTATE_DIR}" ]
then
  mkdir -p "${SAVESTATE_DIR}"
fi

if [ ! -e "${CONFIG_DIR}/input.cfg" ]
then
  rm -f ${CONFIG_DIR}/keymapv2.json

  # Handle inputplumber platforms first
  if [[ "${HW_DEVICE}" =~ SM8550|SM8650 ]]; then
    GAMEPAD="'InputPlumber GameController'"
  else
    # Check for js0, else fall back to joypad
    if grep -q "js0" /proc/bus/input/devices; then
      GAMEPAD="'$(grep -b4 js0 /proc/bus/input/devices | awk 'BEGIN {FS="\""}; /Name/ {printf $2}')'"
    else
      GAMEPAD="'$(grep -b4 joypad /proc/bus/input/devices | awk 'BEGIN {FS="\""}; /Name/ {printf $2}')'"
    fi
  fi

  GAMEPADCONFIG=$(xmlstarlet sel -t -c "//inputList/inputConfig[@deviceName=${GAMEPAD}]" -n /storage/.config/emulationstation/es_input.cfg)

  MAPPING_FILE="/usr/config/yabasanshiro/devices/keymapv2_$(eval echo $GAMEPAD).json"
  if [ -e "${MAPPING_FILE}" ]; then
    cp ${MAPPING_FILE} ${CONFIG_DIR}/keymapv2.json
  fi

  if [ ! -z "${GAMEPADCONFIG}" ]
  then
    cat <<EOF >${CONFIG_DIR}/input.cfg
<?xml version="1.0"?>
<inputList>
${GAMEPADCONFIG}
</inputList>
EOF
  fi
fi

BIOS_ARGS=()
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
USE_BIOS=$(get_setting use_hlebios "${PLATFORM}" "${GAME}")
if [ ! "${USE_BIOS}" = 1 ]
then
  USE_BIOS=$(get_setting use_hlebios "${PLATFORM}")
fi

if [ "$USE_BIOS" = 1 ]
then
  for BIOS_NAME in saturn_bios.bin sega_101.bin mpr-17933.bin mpr-18811-mx.ic1 mpr-19367-mx.ic1 stvbios.zip
  do
    BIOS_FILE=$(find /storage/roms/bios -name "${BIOS_NAME}" -print -quit 2>/dev/null)
    if [ -n "${BIOS_FILE}" ]
    then
      BIOS_ARGS=(-b "${BIOS_FILE}")
      break
    fi
  done
fi

# The fork names the per-game config after the game without its last extension
# ("Game.config"); earlier builds used "Game.chd.config". For a .m3u playlist it
# uses the first disc listed (first line that is not blank or a comment, relative
# to the playlist's folder), so the config follows that disc.
CFG_GAME="${GAME}"
case "${1}" in
  *.[mM]3[uU])
    FIRST=""
    while IFS= read -r LINE || [ -n "${LINE}" ]
    do
      LINE="${LINE#$'\xef\xbb\xbf'}"
      LINE="${LINE%%$'\r'}"
      LINE="${LINE#"${LINE%%[![:space:]]*}"}"
      LINE="${LINE%"${LINE##*[![:space:]]}"}"
      case "${LINE}" in
        ""|"#"*) continue ;;
      esac
      FIRST="${LINE}"
      break
    done < "${1}"
    [ -n "${FIRST}" ] && CFG_GAME="${FIRST##*[/\\]}"
    ;;
esac
GAME_CFG="${CFG_GAME}"
case "${CFG_GAME}" in
  ?*.*) GAME_CFG="${CFG_GAME%.*}" ;;
esac
if [ ! -e "${CONFIG_DIR}/${GAME_CFG}.config" ]
then
  if [ -e "${CONFIG_DIR}/${CFG_GAME}.config" ]
  then
    cp -n "${CONFIG_DIR}/${CFG_GAME}.config" "${CONFIG_DIR}/${GAME_CFG}.config"
  else
    cp -n "${SOURCE_DIR}/.config" "${CONFIG_DIR}/${GAME_CFG}.config"
  fi
fi

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
if [ "${CORES}" = "little" ]
then
  EMUPERF="${SLOW_CORES}"
elif [ "${CORES}" = "big" ]
then
  EMUPERF="${FAST_CORES}"
else
  ### All..
  unset EMUPERF
fi

# The fork keeps its files in /storage/.config/yabasanshiro (patched in; HOME is
# left alone): game configs, keymapv2.json, input.cfg, default.config, cheats/
# and retroachievements.cfg. Select opens its menu, Select+Start quits.
mkdir -p "${CONFIG_DIR}/cheats"

echo "Command: yabasanshiro -r 3 -i ${1} ${BIOS_ARGS[*]}" >>/var/log/exec.log 2>&1
${EMUPERF} yabasanshiro -r 3 -i "${1}" "${BIOS_ARGS[@]}" >>/var/log/exec.log 2>&1
RC=$?
# 128+ is the launcher killing the emulator (set_kill), not a failure.
if [ "${RC}" -ne 0 ] && [ "${RC}" -lt 128 ]
then
  echo "yabasanshiro exited with ${RC}" >>/var/log/exec.log
  exit "${RC}"
fi
exit 0
