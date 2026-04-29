#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Source predefined functions and variables
. /etc/profile
. /etc/os-release

### Shell trace + persistent debug log are gated by system.loglevel=verbose.
### Default (off/none/quiet) writes nothing to microSD on launch.
if [ "$(get_setting system.loglevel)" = "verbose" ]; then
  RUNEMU_DEBUG="/storage/.cache/log/runemu-debug.log"
  mkdir -p "$(dirname "${RUNEMU_DEBUG}")"
  exec 2>>"${RUNEMU_DEBUG}"
  set -x
fi

### Switch to performance mode early to speed up configuration and reduce time it takes to get into games.
performance

# Command line schema
# $1 = Game/Port
# $2 = Platform
# $3 = Core
# $4 = Emulator

ARGUMENTS="$@"
PLATFORM="${ARGUMENTS##*-P}"  # read from -P onwards
PLATFORM="${PLATFORM%% *}"  # until a space is found
CORE="${ARGUMENTS##*--core=}"  # read from --core= onwards
CORE="${CORE%% *}"  # until a space is found
EMULATOR="${ARGUMENTS##*--emulator=}"  # read from --emulator= onwards
EMULATOR="${EMULATOR%% *}"  # until a space is found
ROMNAME="$1"
BASEROMNAME=${ROMNAME##*/}
GAMEFOLDER="${ROMNAME//${BASEROMNAME}}"

### Define the variables used throughout the script
BLUETOOTH_STATE=$(get_setting controllers.bluetooth.enabled)
ES_CONFIG="/storage/.emulationstation/es_settings.cfg"
VERBOSE=false
LOG_DIRECTORY="/var/log"
LOG_FILE="exec.log"
RUN_SHELL="/usr/bin/bash"
RETROARCH_TEMP_CONFIG="/storage/.config/retroarch/retroarch.cfg"
RETROARCH_APPEND_CONFIG="/tmp/.retroarch.cfg"
NETWORK_PLAY="No"
SET_SETTINGS_TMP="/tmp/shader"
OUTPUT_LOG="${LOG_DIRECTORY}/${LOG_FILE}"
SCRIPT_NAME=$(basename "$0")

### Export Game Guide Path
GAME_GUIDE_PATH_CHECK="${1%.*}.txt"
if [ ! -f "${GAME_GUIDE_PATH_CHECK}" ]; then
  GAME_GUIDE_PATH_CHECK="No Game Guide Found"
fi
  /usr/bin/game-guides-tool "${1}"

### Function Library
function log() {
        if [ ${LOG} == true ]
        then
                if [[ ! -d "$LOG_DIRECTORY" ]]
                then
                        mkdir -p "$LOG_DIRECTORY"
                fi
                echo "${SCRIPT_NAME}: $*" 2>&1 | tee -a ${LOG_DIRECTORY}/${LOG_FILE}
        else
                echo "${SCRIPT_NAME}: $*"
        fi
}

function loginit() {
        if [ ${LOG} == true ]
        then
                if [ -e ${LOG_DIRECTORY}/${LOG_FILE} ]
                then
                        rm -f ${LOG_DIRECTORY}/${LOG_FILE}
                fi
                cat <<EOF >${LOG_DIRECTORY}/${LOG_FILE}
Emulation Run Log - Started at $(date)

ARG1: $1
ARG2: $2
ARG3: $3
ARG4: $4
ARGS: $*
EMULATOR: ${EMULATOR}
PLATFORM: ${PLATFORM}
CORE: ${CORE}
ROM NAME: ${ROMNAME}
BASE ROM NAME: ${ROMNAME##*/}
USING CONFIG: ${RETROARCH_TEMP_CONFIG}
USING APPENDCONFIG : ${RETROARCH_APPEND_CONFIG}
GAME GUIDE PATH: ${GAME_GUIDE_PATH_CHECK}

EOF
        else
                log $0 "Emulation Run Log - Started at $(date)"
        fi
}

function quit() {
        ${VERBOSE} && log $0 "Cleaning up and exiting"
        bluetooth enable
        resume_background_services
        restore_ksm
        set_kill set "emulationstation"
        clear_screen
        # Restore CPU governor to user pref (or ondemand fallback). Without
        # the fallback the CPU stays in performance + boost after exit
        # because performance() unconditionally turns boost on for the
        # 1512 MHz turbo OPP, draining battery in the menu.
        DEVICE_CPU_GOVERNOR=$(get_setting system.cpugovernor)
        case "${DEVICE_CPU_GOVERNOR}" in
                performance|ondemand|schedutil|powersave)
                        ${DEVICE_CPU_GOVERNOR}
                        ;;
                *)
                        ondemand
                        ;;
        esac
        exit $1
}

# KSM (Kernel Same-page Merging) compares page contents across processes
# to deduplicate memory. On a Cortex-A35 in-order core it's a noticeable
# source of jitter — exactly the kind of background CPU eater that shows
# up as p99 frametime spikes during gameplay. Pause it for the duration
# of the run and put it back the way the user/memory-manager left it on
# exit.
KSM_RUN_FILE="/sys/kernel/mm/ksm/run"
KSM_PREVIOUS_STATE=""

function pause_ksm() {
        [ -e "${KSM_RUN_FILE}" ] || return
        KSM_PREVIOUS_STATE="$(cat "${KSM_RUN_FILE}" 2>/dev/null)"
        echo 0 > "${KSM_RUN_FILE}" 2>/dev/null
}

function restore_ksm() {
        [ -e "${KSM_RUN_FILE}" ] || return
        [ -z "${KSM_PREVIOUS_STATE}" ] && return
        echo "${KSM_PREVIOUS_STATE}" > "${KSM_RUN_FILE}" 2>/dev/null
}

function clear_screen() {
        ${VERBOSE} && log $0 "Clearing screen"
        clear
}

function bluetooth() {
        if [ "$1" == "disable" ]
        then
                ${VERBOSE} && log $0 "Disabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        NPID=$(pgrep -f archr-bluetooth-agent)
                        if [[ ! -z "$NPID" ]]; then
                                kill "$NPID"
                        fi
                fi
        elif [ "$1" == "enable" ]
        then
                ${VERBOSE} && log $0 "Enabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        systemd-run archr-bluetooth-agent
                fi
        fi
}

### Sync/VPN/HTTP daemons compete with the emulator for CPU, RAM and microSD
### I/O. Stop them on launch and restart only the ones that were running on
### exit (so we never enable a service the user had off).
GAMEPLAY_PAUSE_SERVICES="syncthing tailscaled zerotier-one simple-http-server"
SERVICES_PAUSED_DURING_GAME=""

function pause_background_services() {
        for svc in ${GAMEPLAY_PAUSE_SERVICES}; do
                if systemctl is-active --quiet "${svc}" 2>/dev/null; then
                        ${VERBOSE} && log $0 "Pausing ${svc} for gameplay"
                        systemctl stop "${svc}" >/dev/null 2>&1
                        SERVICES_PAUSED_DURING_GAME+=" ${svc}"
                fi
        done
}

function resume_background_services() {
        for svc in ${SERVICES_PAUSED_DURING_GAME}; do
                ${VERBOSE} && log $0 "Resuming ${svc} after gameplay"
                systemctl start "${svc}" >/dev/null 2>&1 &
        done
}

### Enable logging
case $(get_setting system.loglevel) in
  off|none)
    LOG=false
  ;;
  verbose)
    LOG=true
    VERBOSE=true
  ;;
  *)
    LOG=true
  ;;
esac

### Prepare to load our emulator and game.
loginit "$1" "$2" "$3" "$4"
clear_screen
bluetooth disable
pause_background_services
pause_ksm
set_kill stop

### Determine which emulator we're launching and make appropriate adjustments before launching.
${VERBOSE} && log $0 "Configuring for ${EMULATOR}"
case ${EMULATOR} in
  mednafen)
    set_kill set "-9 mednafen"
    RUNTHIS='${RUN_SHELL} /usr/bin/start_mednafen.sh "${ROMNAME}" "${CORE}" "${PLATFORM}"'
  ;;
  retroarch)
    # Make sure NETWORK_PLAY isn't defined before we start our tests/configuration.
    del_setting netplay.mode

    case ${ARGUMENTS} in
      *"--host"*)
        ${VERBOSE} && log $0 "Setup netplay host."
        NETWORK_PLAY="${ARGUMENTS##*--host}"  # read from --host onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--host ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "host"
      ;;
      *"--connect"*)
        ${VERBOSE} && log $0 "Setup netplay client."
        NETWORK_PLAY="${ARGUMENTS##*--connect}"  # read from --connect onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--connect ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "client"
      ;;
      *"--netplaymode spectator"*)
        ${VERBOSE} && log $0 "Setup netplay spectator."
        set_setting "netplay.mode" "spectator"
      ;;
    esac

    ### Set set_kill to kill the appropriate retroarch
    set_kill set "retroarch retroarch32"

    ### Assume we're running 64bit Retroarch
    RABIN="retroarch"

    case ${HW_ARCH} in
      aarch64)
        if [[ "${CORE}" =~ pcsx_rearmed32 ]] || \
           [[ "${CORE}" =~ gpsp ]] || \
           [[ "${CORE}" =~ desmume ]]
        then
          ### Configure for 32bit Retroarch
          ${VERBOSE} && log $0 "Configuring for 32bit cores."
          export RABIN="retroarch32"
        fi
      ;;
    esac


    ### Configure specific emulator requirements
    case ${CORE} in
      freej2me*)
        ${VERBOSE} && log $0 "Setup freej2me requirements."
        /usr/bin/freej2me.sh
        JAVA_HOME='/storage/jdk'
        export JAVA_HOME
        PATH="$JAVA_HOME/bin:$PATH"
        export PATH
        export _JAVA_OPTIONS="-Djava.awt.headless=true"
      ;;
      easyrpg*)
        # easyrpg needs runtime files to be downloaded on the first run
        ${VERBOSE} && log $0 "Setup easyrpg requirements."
        /usr/bin/easyrpg.sh
      ;;
    esac


    RUNTHIS='${EMUPERF} /usr/bin/${RABIN} -L /tmp/cores/${CORE}_libretro.so --config ${RETROARCH_TEMP_CONFIG} --appendconfig ${RETROARCH_APPEND_CONFIG} "${ROMNAME}"'

    CONTROLLERCONFIG="${ARGUMENTS#*--controllers=*}"

    if [[ "${ARGUMENTS}" == *"-state_slot"* ]]
    then
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% -state_slot*}"  # until -state is found
      SNAPSHOT="${ARGUMENTS#*-state_slot *}" # -state_slot x
      SNAPSHOT="${SNAPSHOT%% -*}"
        if [[ "${ARGUMENTS}" == *"-autosave"* ]]; then
          CONTROLLERCONFIG="${CONTROLLERCONFIG%% -autosave*}"  # until -autosave is found
          AUTOSAVE="${ARGUMENTS#*-autosave *}" # -autosave x
          AUTOSAVE="${AUTOSAVE%% -*}"
        else
          AUTOSAVE=""
        fi
    else
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% --*}"  # until a -- is found
      SNAPSHOT=""
      AUTOSAVE=""
    fi

    # Configure platform specific requirements
    case ${PLATFORM} in
      "atomiswave")
        rm ${ROMNAME}.nvmem*
      ;;
      "scummvm")
        GAMEDIR=$(cat "${ROMNAME}" | awk 'BEGIN {FS="\""}; {print $2}')
        cd "${GAMEDIR}"
        RUNTHIS='${RUN_SHELL} /usr/bin/start_scummvm.sh libretro .'
      ;;
    esac

    ### Configure retroarch
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      rm -f "${SET_SETTINGS_TMP}"
    fi
    ${VERBOSE} && log $0 "Execute setsettings (${PLATFORM} ${ROMNAME} ${CORE} --controllers=${CONTROLLERCONFIG} --autosave=${AUTOSAVE} --snapshot=${SNAPSHOT})"
    (/usr/bin/setsettings.sh "${PLATFORM}" "${ROMNAME}" "${CORE}" --controllers="${CONTROLLERCONFIG}" --autosave="${AUTOSAVE}" --snapshot="${SNAPSHOT}" >${SET_SETTINGS_TMP})

    ### If setsettings wrote data in the background, grab it and assign it to EXTRAOPTS
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      EXTRAOPTS=$(cat ${SET_SETTINGS_TMP})
      rm -f ${SET_SETTINGS_TMP}
      ${VERBOSE} && log $0 "Extra Options: ${EXTRAOPTS}"
    fi

    if [[ ${EXTRAOPTS} != 0 ]]; then
      RUNTHIS=$(echo ${RUNTHIS} | sed "s|--config|${EXTRAOPTS} --config|")
    fi
  ;;
  *)
    case ${PLATFORM} in
      "setup")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      "gamecube"|"triforce")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_gc.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "wii"|"wiiware")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_wii.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "ports")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
	      sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "windows")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        # Hook into Portmaster control mapping
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "shell")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      *)
        RUNTHIS='${RUN_SHELL} "/usr/bin/start_${CORE%-*}.sh" "${ROMNAME}" "${PLATFORM}"'
      ;;
    esac
  ;;
esac

### Execution time.
clear_screen
${VERBOSE} && log $0 "executing game: ${ROMNAME}"
${VERBOSE} && log $0 "script to execute: ${RUNTHIS}"

### Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Configure big.little (${CORES})"
case ${CORES} in
  little)
    EMUPERF="${SLOW_CORES}"
  ;;
  big)
    EMUPERF="${FAST_CORES}"
  ;;
  *)
    unset EMUPERF
  ;;
esac

### We need the original system cooling profile later so get it now!
COOLINGPROFILE=$(get_setting cooling.profile)

### Configure GPU performance mode
### Default to "performance" during gameplay so devfreq pins min_freq at the
### highest OPP. ROCKNIX achieves the same effect by exposing only one GPU
### OPP (560 MHz) in their DT; we keep the full ladder for idle/menu and
### force the floor up here. Without this, simple_ondemand kept the GPU
### oscillating between 200-400 MHz mid-frame, costing ~50% of PSP/N64/DC
### performance versus competing distros.
GPUPERF=$(get_setting "gpuperf" "${PLATFORM}" "${ROMNAME##*/}")
GPUPERF="${GPUPERF:-performance}"
${VERBOSE} && log $0 "Set GPU performance to (${GPUPERF})"
gpu_performance_level ${GPUPERF}
get_gpu_performance_level >/tmp/.gpu_performance_level

### Make sure Mesa's shader cache directory exists. Mesa won't create the
### root path itself when MESA_SHADER_CACHE_DIR points somewhere new; the
### result is silent fall-through to "no cache" and a stutter every time
### the user re-launches a game whose shaders should already be hot.
[ -d /storage/.cache/mesa_shader_cache ] || mkdir -p /storage/.cache/mesa_shader_cache 2>/dev/null

if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ### Set any custom fan profile (make this better!)
  GAMEFAN=$(get_setting "cooling.profile" "${PLATFORM}" "${ROMNAME##*/}")
  if [ ! -z "${GAMEFAN}" ]
  then
    ${VERBOSE} && log $0 "Set fan profile to (${GAMEFAN})"
    set_setting cooling.profile ${GAMEFAN}
    systemctl restart fancontrol
  fi
fi

### Display mode for emulation
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  set_refresh_rate "${DISPLAY_MODE}"
fi

FORCEPACK=$(get_setting "forcepack" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${FORCEPACK}" ] && [ "${FORCEPACK}" = "On" ]
then
    ${VERBOSE} && log $0 "Enabling panfrost forcepack"
    export PAN_MESA_DEBUG=forcepack
fi

### Offline all but the number of threads we need for this game if configured.
NUMTHREADS=$(get_setting "threads" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${NUMTHREADS}" ] &&
   [ ! ${NUMTHREADS} = "default" ]
then
  ${VERBOSE} && log $0 "Configure active cores (${NUMTHREADS})"
  onlinethreads ${NUMTHREADS} 0
fi

### Set the governor mode for emulation
CPU_GOVERNOR=$(get_setting "cpugovernor" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Set emulation performance mode to (${CPU_GOVERNOR})"
${CPU_GOVERNOR}

### Check whether MangoHud is supported and enabled
if [ "${DEVICE_MANGOHUD_SUPPORT}" == "true" ]; then
  MANGOHUD_ENABLED=$(get_setting "archr.mangohud.enabled"  "${PLATFORM}" "${ROMNAME##*/}")
  if [ "${MANGOHUD_ENABLED}" = "1" ]; then
    # Enable GPU profiling and MangoHud
    gpu_profiling "on"
    RUNTHIS="/usr/bin/mangohud ${RUNTHIS}"
    ${VERBOSE} && log $0 "Enabling MangoHud"
  fi
fi

# If the rom is a shell script just execute it, useful for DOSBOX and ScummVM scan scripts
if [[ "${ROMNAME}" == *".sh" ]] && [ ! "${PLATFORM}" = "ports" ] && [ ! "${PLATFORM}" = "windows" ]; then
        ${VERBOSE} && log $0 "Executing shell script ${ROMNAME}"
        "${ROMNAME}" &>>${OUTPUT_LOG}
        ret_error=$?
else
        ${VERBOSE} && log $0 "Executing $(eval echo ${RUNTHIS})"
        eval ${RUNTHIS} &>>${OUTPUT_LOG}
        ret_error=$?
fi

### Switch back to performance mode to clean up
performance

clear_screen

### Disable touch on the secondary screen for dual screen devices
if [[ "${DEVICE_HAS_DUAL_SCREEN}" == "true" ]]; then
  # Disable touch events for Retroid Pocket devices to prevent focus loss
  if [[ "${QUIRK_DEVICE}" == "Retroid Pocket 5" || "${QUIRK_DEVICE}" == "Retroid Pocket Flip2" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini V2" ]]; then
    swaymsg input "0:0:generic_ft5x06_(a0)" events disabled
    swaymsg input "0:0:generic_ft5x06_(8d)" events disabled
  fi
fi

### Go back to system display mode , if we had specialized mode defined
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  DISPLAY_MODE=$(get_setting "system.display_mode")
  DISPLAY_OUTPUT=$(/usr/bin/wlr-randr | awk 'NR==1{print $1;}')
  if [ -z "${DISPLAY_MODE}" ]; then
    # if we have no system mode use the displays preferred mode
    /usr/bin/wlr-randr --output ${DISPLAY_OUTPUT} --preferred
  else
    # If we have user specifed system mode set that
    set_refresh_rate "${DISPLAY_MODE}"
  fi
fi

### Restore cooling profile.
if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ${VERBOSE} && log $0 "Restore system cooling profile (${COOLINGPROFILE})"
  set_setting cooling.profile ${COOLINGPROFILE}
  systemctl restart fancontrol &
fi

### Restore system GPU performance mode.
### Honour an explicit per-system setting if the user picked one. Otherwise
### keep the governor at "performance" — every transition back to ondemand
### exercises a regulator/clock refcount path in mali_kbase that fires
### "unbalanced disables for vdd_logic" / "Enabling unprepared clk_gpu"
### kernel WARNs and occasionally takes the device down. Battery cost of
### staying performance in the menu is small; PM stability is worth it.
GPUPERF=$(get_setting "system.gpuperf")
if [ ! -z ${GPUPERF} ]
then
  ${VERBOSE} && log $0 "Restore system GPU performance mode (${GPUPERF})"
  gpu_performance_level ${GPUPERF} &
else
  ${VERBOSE} && log $0 "Keeping GPU governor at performance (mali_kbase PM workaround)"
  # No-op: leave whatever gameplay set in place.
fi
rm -f /tmp/.gpu_performance_level 2>/dev/null

### Reset the number of cores to use.
NUMTHREADS=$(get_setting "system.threads")
${VERBOSE} && log $0 "Restore active threads (${NUMTHREADS})"
if [ -n "${NUMTHREADS}" ]
then
        onlinethreads ${NUMTHREADS} 0 &
else
        onlinethreads all 1 &
fi

### Disable GPU profiling
gpu_profiling "off"

### Backup save games
CLOUD_BACKUP=$(get_setting "cloud.backup")
if [ "${CLOUD_BACKUP}" = "1" ]
then
  INETUP=$(/usr/bin/amionline >/dev/null 2>&1)
  if [ $? == 0 ]
  then
    log $0 "backup saves to the cloud."
    /usr/bin/run /usr/bin/cloud_backup
  fi
fi

${VERBOSE} && log $0 "Checking errors: ${ret_error} "
if [ "${ret_error}" == "0" ]
then
        quit 0
else
        log $0 "exiting with ${ret_error}"
        quit 1
fi
