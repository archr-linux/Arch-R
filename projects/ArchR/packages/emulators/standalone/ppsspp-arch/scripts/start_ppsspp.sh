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

#Launcher settings, per game or per system in system.cfg (psp.frame_skip=2,
#psp["Game.iso"].skip_buffer_effects=1). Each is written to ppsspp.ini only
#when it is set: what the player changes in PPSSPP itself (Tools) stays for
#everything left unset. Before, every start wrote a default over it.
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
INI="${CONF_DIR}/${PPSSPP_INI}"
# ini_set KEY VALUE: one key of ppsspp.ini
ini_set() {
  sed -i "/^${1} =/c\\${1} = ${2}" "${INI}"
}
ASKIP=$(get_setting auto_frame_skip "${PLATFORM}" "${GAME}")
FSKIP=$(get_setting frame_skip "${PLATFORM}" "${GAME}")
FPS=$(get_setting show_fps "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
SKIPB=$(get_setting skip_buffer_effects "${PLATFORM}" "${GAME}")
# God of War runs at 7-8 fps on the R36S with buffer effects; skipping them
# gives 17-19 from an ISO (a CHD in LZMA costs more), and its cutscenes go
# black. A setting for the game or the platform (0 or 1) still decides.
if [ -z "${SKIPB}" ]; then
  case "${GAME}" in
    *"God of War"*) SKIPB=1 ;;
  esac
fi
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

  #Frame skipping. frame_skip=N is the most frames skipped in a row with
  #auto frame skip, the fixed skip without it; auto_frame_skip=0 alone
  #skips nothing. Auto frame skip skips nothing while FrameSkip is 0 (God
  #of War ran at 24% speed, 80% with a cap), so a cap of 0 becomes 2.
  #PPSSPP turns buffer effects back on while auto frame skip is on, so
  #skip_buffer_effects=1 implies a fixed skip, 2 unless frame_skip says
  #otherwise (1 is what dArkOSRE-R36 ships for the R36S,
  #southoz/dArkOSRE-R36@77ef6d941b,
  #files/ROOTFS/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/ppsspp.ini):
  #God of War at 100% speed (30 fps shown), losing its glow.
	case "${ASKIP}" in 0|1) ;; *) ASKIP="" ;; esac
	case "${FSKIP}" in [0-8]) ;; *) FSKIP="" ;; esac
	if [ "${SKIPB}" = "1" ]; then
		[ -z "${ASKIP}" ] && ASKIP=0
		[ "${ASKIP}" = "0" ] && [ -z "${FSKIP}" ] && FSKIP=2
	fi
	[ "${ASKIP}" = "0" ] && [ -z "${FSKIP}" ] && FSKIP=0
	[ "${ASKIP}" = "1" ] && [ "${FSKIP}" = "0" ] && FSKIP=2
	case "${ASKIP}" in
		0) ini_set AutoFrameSkip False ;;
		1) ini_set AutoFrameSkip True ;;
	esac
	[ -n "${FSKIP}" ] && ini_set FrameSkip "${FSKIP}"

  #Graphics Backend. Vulkan exists only while panfrost drives the GPU: on
  #libmali a Vulkan backend, set here or in PPSSPP, would not start.
	case "${GRENDERER}" in
		opengl) ini_set GraphicsBackend "0 (OPENGL)" ;;
		vulkan) ini_set GraphicsBackend "3 (VULKAN)" ;;
	esac
	if [ ! -d /sys/module/panfrost ] && grep -q '^GraphicsBackend = 3' "${INI}"; then
		GRENDERER="opengl"
		ini_set GraphicsBackend "0 (OPENGL)"
	fi

  #Internal Resolution
	case "${IRES}" in
		[1-4]) ini_set InternalResolution "${IRES}" ;;
	esac

  #Show FPS
	case "${FPS}" in
		1) ini_set iShowStatusFlags 2 ;;
		0) ini_set iShowStatusFlags 0 ;;
	esac

  #Skip Buffer Effects
	case "${SKIPB}" in
		1) ini_set SkipBufferEffects True ;;
		0) ini_set SkipBufferEffects False ;;
	esac

  #VSYNC: PPSSPP's key is VerticalSync (VSyncInterval is not read, the
  #setting did nothing). Configs from older packages only have
  #VSyncInterval: add the key.
	if [ "${VSYNC}" = "1" ] || [ "${VSYNC}" = "0" ]; then
		[ "${VSYNC}" = "1" ] && VSYNC_VALUE=True || VSYNC_VALUE=False
		if grep -q '^VerticalSync =' "${INI}"; then
			ini_set VerticalSync "${VSYNC_VALUE}"
		else
			sed -i "/^\[Graphics\]/a VerticalSync = ${VSYNC_VALUE}" "${INI}"
		fi
	fi

  #Clock Speed (0 is PPSSPP's default, the PSP's own)
	case "${CLOCK_SPEED}" in
		0|222|333) ini_set CPUSpeed "${CLOCK_SPEED}" ;;
	esac

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
