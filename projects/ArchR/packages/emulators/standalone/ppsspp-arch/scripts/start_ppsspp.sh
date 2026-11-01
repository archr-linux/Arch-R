#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile
set_kill set "-9 ppsspp"

SOURCE_DIR="/usr/config/ppsspp"
CONF_DIR="/storage/.config/ppsspp"
PPSSPP_INI="PSP/SYSTEM/ppsspp.ini"

# Check if conf dir exists
if [ ! -d "${CONF_DIR}" ]
then
  cp -rf ${SOURCE_DIR} ${CONF_DIR}
fi

# Check if savestate dir exists
if [ ! -d "/storage/roms/savestates/psp/ppsspp-sa" ]; then
  mkdir -p "/storage/roms/savestates/psp/ppsspp-sa"
fi

#Emulation Station Features
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
ASKIP=$(get_setting auto_frame_skip "${PLATFORM}" "${GAME}")
FPS=$(get_setting show_fps "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
SKIPB=$(get_setting skip_buffer_effects "${PLATFORM}" "${GAME}")
VSYNC=$(get_setting vsync "${PLATFORM}" "${GAME}")
CLOCK_SPEED=$(get_setting clock_speed "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
if [ "${CORES}" = "little" ]; then
  EMUPERF="${SLOW_CORES}"
elif [ "${CORES}" = "big" ]; then
  EMUPERF="${FAST_CORES}"
else
  ### All..
  unset EMUPERF
fi

  #Frame skipping. Default: auto frame skip, up to 3 frames in a row.
  #Auto frame skip only skips while FrameSkip (the most frames skipped in
  #a row) is above 0, and a FrameSkip = 0 left in the file had silently
  #turned it off (an --appendconfig run saves its values into the file):
  #God of War ran at 24% speed, 80% with the cap back. So FrameSkip is
  #always written. Lighter games (Tekken 6, Burnout Legends, Death Jr.)
  #keep 100% and every frame either way.
  #PPSSPP turns buffer effects back on while auto frame skip is on, so
  #skip_buffer_effects=1 implies a fixed skip of one frame in two, as
  #dArkOSRE-R36 ships for the R36S (southoz/dArkOSRE-R36@77ef6d941b,
  #files/ROOTFS/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/ppsspp.ini):
  #God of War at 100% speed (30 fps shown), losing its glow; light games
  #drop to half their frames, hence per game only. frame_skip=N sets the
  #cap (auto) or the fixed skip; auto_frame_skip=0 alone skips nothing.
	if [ -z "${ASKIP}" ]; then
		[ "${SKIPB}" = "1" ] && ASKIP=0 || ASKIP=1
	fi
	FSKIP=$(get_setting frame_skip "${PLATFORM}" "${GAME}")
	case "${FSKIP}" in
		[0-8]) ;;
		*) if [ "${ASKIP}" = "1" ]; then FSKIP=3; elif [ "${SKIPB}" = "1" ]; then FSKIP=1; else FSKIP=0; fi ;;
	esac
	if [ "${ASKIP}" = "0" ]; then
		sed -i '/^AutoFrameSkip =/c\AutoFrameSkip = False' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^AutoFrameSkip =/c\AutoFrameSkip = True' ${CONF_DIR}/${PPSSPP_INI}
		[ "${FSKIP}" = "0" ] && FSKIP=3
	fi
	sed -i "/^FrameSkip =/c\FrameSkip = ${FSKIP}" ${CONF_DIR}/${PPSSPP_INI}

  #Graphics Backend
        if [ "${GRENDERER}" = "opengl" ]; then
                sed -i '/^GraphicsBackend =/c\GraphicsBackend = 0 (OPENGL)' ${CONF_DIR}/${PPSSPP_INI}
        elif [ "${GRENDERER}" = "vulkan" ]; then
                sed -i '/^GraphicsBackend =/c\GraphicsBackend = 3 (VULKAN)' ${CONF_DIR}/${PPSSPP_INI}
        else
		sed -i '/^GraphicsBackend =/c\GraphicsBackend = @GRENDERER@' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Internal Resolution
	if [ "${IRES}" = "2" ]; then
		sed -i '/^InternalResolution/c\InternalResolution = 2' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${IRES}" = "3" ]; then
		sed -i '/^InternalResolution/c\InternalResolution = 3' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${IRES}" = "4" ]; then
                sed -i '/^InternalResolution/c\InternalResolution = 4' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^InternalResolution/c\InternalResolution = 1' ${CONF_DIR}/${PPSSPP_INI}
        fi

  #Show FPS
	if [ "${FPS}" = "1" ]; then
		sed -i '/^iShowStatusFlags =/c\iShowStatusFlags = 2' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^iShowStatusFlags =/c\iShowStatusFlags = 0' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Skip Buffer Effects
	if [ "${SKIPB}" = "1" ]; then
		sed -i '/^SkipBufferEffects =/c\SkipBufferEffects = True' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^SkipBufferEffects =/c\SkipBufferEffects = False' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #VSYNC: PPSSPP's key is VerticalSync (VSyncInterval is not read, the
  #setting did nothing). Unset leaves the file's value, on by default.
	if [ "${VSYNC}" = "1" ]; then
		sed -i '/^VerticalSync =/c\VerticalSync = True' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${VSYNC}" = "0" ]; then
		sed -i '/^VerticalSync =/c\VerticalSync = False' ${CONF_DIR}/${PPSSPP_INI}
	fi

  #Clock Speed
	if [ "${CLOCK_SPEED}" = "222" ]; then
		sed -i '/^CPUSpeed =/c\CPUSpeed = 222' ${CONF_DIR}/${PPSSPP_INI}
	elif [ "${CLOCK_SPEED}" = "333" ]; then
		sed -i '/^CPUSpeed =/c\CPUSpeed = 333' ${CONF_DIR}/${PPSSPP_INI}
	else
		sed -i '/^CPUSpeed =/c\CPUSpeed = 0' ${CONF_DIR}/${PPSSPP_INI}
	fi

#Select+Start quits, as in RetroArch and mupen64plus. PPSSPP has no such
#default: without an "Exit App" mapping the pair did nothing. Built from the
#pad's own Select and Start (first gamepad entry, device 10 or above), so it
#follows each device's controls.ini; a mapping the user set is kept.
#Same mapping as dArkOSRE-R36 (southoz/dArkOSRE-R36@a17bddecc6,
#files/ROOTFS/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini).
CONTROLS_INI="${CONF_DIR}/PSP/SYSTEM/controls.ini"
pad_key() {
  sed -n "s/^${1} = //p" "${CONTROLS_INI}" | tr ',' '\n' | grep -m1 -E '^1[0-9]-[0-9]+$'
}
if [ -f "${CONTROLS_INI}" ] && ! grep -q '^Exit App = ' "${CONTROLS_INI}"; then
  EXIT_SELECT=$(pad_key Select)
  EXIT_START=$(pad_key Start)
  if [ -n "${EXIT_SELECT}" ] && [ -n "${EXIT_START}" ]; then
    sed -i "/\[ControlMapping\]/a Exit App = ${EXIT_SELECT}:${EXIT_START}" "${CONTROLS_INI}"
  fi
fi

#Retroachievements
/usr/bin/cheevos_ppsspp.sh

ARG=${1//[\\]/}

# Debugging info:
  echo "GAME set to: ${GAME}"
  echo "PLATFORM set to: ${PLATFORM}"
  echo "CONF DIR: ${CONF_DIR}/${PPSSPP_INI}"
  echo "CPU CORES set to: ${EMUPERF}"
  echo "AUTO FRAME SKIP set to: ${ASKIP}"
  echo "GRAPHICS RENDERER set to: ${GRENDERER}"
  echo "INTERNAL RESOLUTION set to: ${IRES}"
  echo "FPS set to: ${FPS}"
  echo "SKIP BUFFER EFFECTS set to: ${SKIPB}"
  echo "VSYNC set to: ${VSYNC}"
  echo "Launching /usr/bin/ppsspp ${ARG}"

# Panfrost optimization: forcepack reduces draw call overhead on Mali-G31
export PAN_MESA_DEBUG=forcepack
export MESA_NO_ERROR=1
# Mesa GL command thread: PPSSPP issues many small GL calls per frame
# (sprite/draw bursts) and the standalone build keeps render and CPU on
# separate threads internally. Letting Mesa marshal GL on its own
# thread cuts per-call dispatch latency on Cortex-A35. See
# docs/mesa-glthread-matrix.md.
export MESA_GLTHREAD=true

${EMUPERF} ppsspp --pause-menu-exit "${ARG}"
