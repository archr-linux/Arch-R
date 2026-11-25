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
# Once per config: four keys back to PPSSPP's own defaults, which run
# faster on the RK3326 (GTA VCS 70% -> 78% on a Soy Sauce, 2026-11-18)
# than the values we shipped before. Only a key still at the value we
# shipped changes: one the player set in PPSSPP stays. New installs get
# them from the ini already.
DEFAULTS_MARK="${CONF_DIR}/.defaults-20261119"
# ini_back KEY DEFAULT OLD...: KEY to DEFAULT while it is one of OLD
ini_back() {
  key=$1 default=$2 now=$(sed -n "s/^${1} = //p" "${INI}")
  shift 2
  for old in "$@"; do
    [ "${now}" = "${old}" ] && ini_set "${key}" "${default}" && return
  done
}
if [ -f "${INI}" ] && [ ! -e "${DEFAULTS_MARK}" ]; then
  ini_back HighQualityDepth True 0 False
  ini_back TextureBackoffCache False True 1
  ini_back RenderDuplicateFrames False True 1
  ini_back SkipGPUReadbackMode 0 1
  touch "${DEFAULTS_MARK}"
fi
ASKIP=$(get_setting auto_frame_skip "${PLATFORM}" "${GAME}")
FSKIP=$(get_setting frame_skip "${PLATFORM}" "${GAME}")
FSKIP_USER=${FSKIP}
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
	#The RK3562 (Mali-G52 at 900 MHz) draws every frame: God of War at
	#60/60, 100% with buffer effects skipped and no frame skip.
	SKIP_FIXED=2
	grep -qs 'rockchip,rk3562' /proc/device-tree/compatible && SKIP_FIXED=0
	if [ "${SKIPB}" = "1" ]; then
		[ -z "${ASKIP}" ] && ASKIP=0
		[ "${ASKIP}" = "0" ] && [ -z "${FSKIP}" ] && FSKIP=${SKIP_FIXED}
	fi
	[ "${ASKIP}" = "0" ] && [ -z "${FSKIP}" ] && FSKIP=0
	[ "${ASKIP}" = "1" ] && [ "${FSKIP}" = "0" ] && FSKIP=2
	case "${ASKIP}" in
		0) ini_set AutoFrameSkip False ;;
		1) ini_set AutoFrameSkip True ;;
	esac
	[ -n "${FSKIP}" ] && ini_set FrameSkip "${FSKIP}"

  #Graphics Backend. Vulkan exists only while panfrost drives the GPU: on
  #libmali a Vulkan backend, set here or in PPSSPP, would not start. The
  #SDL the system loads must have Vulkan too: an SDL2 from before the
  #Vulkan update, or the glesonly copy the libmali mode mounts, has none,
  #and PPSSPP then aborts ("Vulkan support is either not configured in
  #SDL") instead of opening the game.
	SDL_LIB=/usr/lib/libSDL2-2.0.so.0
	sdl_vulkan() { grep -q VK_KHR_wayland_surface "$(readlink -f "${SDL_LIB}")" 2>/dev/null; }
	case "${GRENDERER}" in
		opengl) ini_set GraphicsBackend "0 (OPENGL)" ;;
		vulkan) ini_set GraphicsBackend "3 (VULKAN)" ;;
	esac
	if grep -q '^GraphicsBackend = 3' "${INI}" && { [ ! -d /sys/module/panfrost ] || ! sdl_vulkan; }; then
		echo "Vulkan unavailable here (panfrost $([ -d /sys/module/panfrost ] && echo on || echo off), SDL $(sdl_vulkan && echo with || echo without) Vulkan): OpenGL"

		GRENDERER="opengl"
		ini_set GraphicsBackend "0 (OPENGL)"
	fi
	# Nor may PPSSPP's own menu switch to Vulkan there: it restarts itself
	# on the new backend and aborts the same way. With no Vulkan driver in
	# sight it finds no Vulkan device and offers none.
	if [ ! -d /sys/module/panfrost ] || ! sdl_vulkan; then
		export VK_DRIVER_FILES=/dev/null VK_ICD_FILENAMES=/dev/null
	fi
	# PPSSPP marks the backend it starts in FailedGraphicsBackends.txt and
	# clears the mark after 10 frames. A start that dies before that (a
	# crash, a kill) makes the next one fall back to OpenGL without a word
	# and save OpenGL to ppsspp.ini. Vulkan chosen in system.cfg and usable
	# here is what runs: the mark goes. Without a setting it stays.
	FAILED_MARK="${CONF_DIR}/PSP/SYSTEM/FailedGraphicsBackends.txt"
	if [ -s "${FAILED_MARK}" ]; then
		echo "PPSSPP failed to start last time on: $(cat "${FAILED_MARK}")"
		if [ "${GRENDERER}" = "vulkan" ] && grep -q '^GraphicsBackend = 3' "${INI}"; then
			rm -f "${FAILED_MARK}"
		fi
	fi
	# On Vulkan (PanVK) a skip of 1 runs as fast as 2 does on OpenGL, with
	# about 40% more frames (God of War, R36S: 73-84% speed, 22-24 fps
	# against 16): the skip that skip_buffer_effects implies is 1 there,
	# unless frame_skip says otherwise.
	if [ "${SKIPB}" = "1" ] && [ -z "${FSKIP_USER}" ] && [ "${ASKIP}" = "0" ] &&
		grep -q '^GraphicsBackend = 3' "${INI}"; then
		FSKIP=1
		ini_set FrameSkip 1
	fi

  #Internal Resolution
	case "${IRES}" in
		[1-4]) ini_set InternalResolution "${IRES}" ;;
	esac

  #Upscaler: the game drawn at the PSP's own 480x272 and brought to the
  #screen by AMD FSR 1 (PPSSPP's FSR-EASU upscale and FSR-RCAS sharpen
  #post shaders) in place of a bilinear stretch. psp.upscaler=fsr, easu
  #(the upscale alone) or off, per game or platform, rewrites PPSSPP's
  #post shader chain; other shaders in it stay, after FSR. Unset, the
  #chain is the player's. Off by default everywhere: on the RG43V PRO
  #(Mali-G52, 1024x768) FSR keeps the GPU 96% busy and Tekken 6 drops
  #from 55 to 40-43 fps (EASU alone 45-54); the Mali-G31 is weaker still.
  #PPSSPP runs no post shader while it skips buffer effects (God of War).
	UPSCALER=$(get_setting upscaler "${PLATFORM}" "${GAME}")
	case "${UPSCALER}" in
		fsr|easu|off)
			# The chain without FSR, then FSR first: the upscaler must
			# be the first shader.
			CHAIN=$(sed -n '/^\[PostShaderList\]/,/^\[/{s/^PostShader[0-9][0-9]* = //p}' "${INI}" |
				grep -v '^FSR-\(EASU\|RCAS\)$')
			case "${UPSCALER}" in
				fsr) CHAIN=$(printf 'FSR-EASU\nFSR-RCAS\n%s' "${CHAIN}") ;;
				easu) CHAIN=$(printf 'FSR-EASU\n%s' "${CHAIN}") ;;
			esac
			grep -q '^\[PostShaderList\]' "${INI}" || echo '[PostShaderList]' >>"${INI}"
			awk -v chain="$(echo ${CHAIN})" '
				/^\[/ { list = ($0 == "[PostShaderList]") }
				list && /^PostShader[0-9]+ = / { next }
				{ print }
				$0 == "[PostShaderList]" {
					n = split(chain, s, " ")
					for (i = 1; i <= n; i++) print "PostShader" i " = " s[i]
				}' "${INI}" >"${INI}.new" && mv "${INI}.new" "${INI}"
			;;
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
# PanVK: an indexed draw finds its index range on the CPU and is drawn
# directly, not as an indirect draw with a min/max search job on the GPU
# (mesa patch 001-panvk-cpu-index-minmax; from Zenith, a ROCKNIX fork).
# God of War on Vulkan ran 27-40% of full speed without, 40-58% with.
export PANVK_CPU_INDEX_MINMAX=1

#NPU upscale (npu-upscale, the RK3562's NPU; dArkOS's NPU UPSCALE): the
#PSP frame drawn at 1x, nearest, integer scale (960x544) and enlarged on the
#NPU. Setting npu_upscale (off, auto, x2, x3), per game or platform. auto
#upscales only a game PPSSPP already draws at 1x into a buffer: skipping
#buffer effects (God of War) draws straight at the screen's size and keeps
#its own path. x2 or x3 force the 1x buffered render for the run. Nothing
#happens where "npu-upscale supported" fails (every other device).
NPU_SPEC=""
if command -v npu-upscale >/dev/null 2>&1 && npu-upscale supported; then
	npu-upscale ppsspp-ini restore "${INI}"
	NPU=$(get_setting npu_upscale "${PLATFORM}" "${GAME}")
	NPU=${NPU:-auto}
	NPU_SPEC=$(npu-upscale spec psp "${NPU}")
	if [ -n "${NPU_SPEC}" ]; then
		if [ "${NPU}" = auto ]; then
			if npu-upscale ppsspp-auto "${INI}"; then
				npu-upscale ppsspp-ini set "${INI}"
			else
				NPU_SPEC=""
			fi
		else
			npu-upscale ppsspp-ini set "${INI}" force
		fi
	fi
	echo "NPU UPSCALE set to: ${NPU} (${NPU_SPEC:-off})"
fi

if [ -n "${NPU_SPEC}" ]; then
	${EMUPERF} npu-upscale exec "${NPU_SPEC}" -- ppsspp --pause-menu-exit "${ARG}"
	npu-upscale ppsspp-ini restore "${INI}"
	npu-upscale down
else
	${EMUPERF} ppsspp --pause-menu-exit "${ARG}"
fi
