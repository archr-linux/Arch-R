#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Source predefined functions and variables
. /etc/profile
. /etc/os-release

### Shell trace + persistent debug log are gated by system.loglevel=verbose.
### Default (off/none/quiet) writes nothing to microSD on launch.
### /var/log is mounted from /storage/.cache/log by var-log.mount, so
### /var/log/runemu-debug.log lands on the rw overlay and survives.
if [ "$(get_setting system.loglevel)" = "verbose" ]; then
  RUNEMU_DEBUG="/var/log/runemu-debug.log"
  mkdir -p "$(dirname "${RUNEMU_DEBUG}")"
  exec 2>>"${RUNEMU_DEBUG}"
  set -x
fi

### Switch to performance mode early to speed up configuration and reduce time it takes to get into games.
performance

# Command line schema, one shell word per argument:
#   $1 = Game/Port, then in any order:
#   -P<platform> --core=<core> --emulator=<emulator> --controllers=<string>
#   --governor=<performance|ondemand|schedutil|powersave> (this launch only)
#   --cpu-max=<kHz>  CPU ceiling of this launch only, one of the CPU's own
#   --measure        archr-perf-probe measures the run for launcher modules
#   --entryslot=<0..999|auto>  RetroArch: start from this save state slot
#   --entrystate=<file>        standalone emulators: start from this state
#   -state_slot N  -autosave N  -state_file FILE (ignored)
#   netplay: --host | --connect [IP] | --port N | --nick NAME | --spectate
#            | --netplaymode spectator | --mitm-session ID
# Values are taken from argument boundaries only, never from substrings of
# the joined command line, so a ROM path, controller string or nickname
# cannot change another field. Netplay values may also be --flag=value.
# --nick takes exactly one argument: quote multiword names.
ROMNAME="$1"
PLATFORM=""
CORE=""
EMULATOR=""
CONTROLLERCONFIG=""
SNAPSHOT=""
AUTOSAVE=""
NETPLAY_SESSION_MODE=""
NETPLAY_SESSION_HOST=""
NETPLAY_SESSION_PORT=""
NETPLAY_SESSION_NICK=""
NETPLAY_SESSION_SPECTATE=0
GOVERNOR_OVERRIDE=""
CPU_MAX_OVERRIDE=""
MEASURE=0
ENTRYSLOT=""
ENTRYSTATE=""
NETPLAY_SESSION_MITM=""
ARGV=("$@")
for ((i = 1; i < ${#ARGV[@]}; i++)); do
  ARG="${ARGV[i]}"
  NEXT="${ARGV[i+1]-}"
  case "${ARG}" in
    --core=*) CORE="${ARG#*=}" ;;
    --emulator=*) EMULATOR="${ARG#*=}" ;;
    --controllers=*) CONTROLLERCONFIG="${ARG#*=}" ;;
    --governor=*) GOVERNOR_OVERRIDE="${ARG#*=}" ;;
    --cpu-max=*) CPU_MAX_OVERRIDE="${ARG#*=}" ;;
    --measure) MEASURE=1 ;;
    --entryslot=*) ENTRYSLOT="${ARG#*=}" ;;
    --entrystate=*) ENTRYSTATE="${ARG#*=}" ;;
    --connect=*) NETPLAY_SESSION_MODE="client"; NETPLAY_SESSION_HOST="${ARG#*=}" ;;
    --port=*) NETPLAY_SESSION_PORT="${ARG#*=}" ;;
    --nick=*) NETPLAY_SESSION_NICK="${ARG#*=}" ;;
    --mitm-session=*) NETPLAY_SESSION_MITM="${ARG#*=}" ;;
    --host) NETPLAY_SESSION_MODE="host" ;;
    --spectate) NETPLAY_SESSION_SPECTATE=1 ;;
    --*|-state_slot|-autosave|-state_file)
      case "${ARG}" in
        --connect|--port|--nick|--netplaymode|--mitm-session|-state_slot|-autosave|-state_file) ;;
        *) continue ;;
      esac
      [ "${ARG}" = "--connect" ] && NETPLAY_SESSION_MODE="client"
      # A missing value (end of list or another flag) is not consumed. An
      # empty argument after --nick is its value: the saved nickname is used.
      if [ "${ARG}" = "--nick" ] && [ $((i + 1)) -lt ${#ARGV[@]} ] && [ -z "${NEXT}" ]; then
        i=$((i + 1))
        continue
      fi
      [ -n "${NEXT}" ] && [ "${NEXT#-}" = "${NEXT}" ] || continue
      i=$((i + 1))
      case "${ARG}" in
        --connect) NETPLAY_SESSION_HOST="${NEXT}" ;;
        --port) NETPLAY_SESSION_PORT="${NEXT}" ;;
        --nick) NETPLAY_SESSION_NICK="${NEXT}" ;;
        --mitm-session) NETPLAY_SESSION_MITM="${NEXT}" ;;
        --netplaymode)
          # Legacy spectator: a client that joins as a spectator.
          if [ "${NEXT}" = "spectator" ]; then
            NETPLAY_SESSION_MODE="client"
            NETPLAY_SESSION_SPECTATE=1
          fi
          ;;
        -state_slot) SNAPSHOT="${NEXT}" ;;
        -autosave) AUTOSAVE="${NEXT}" ;;
      esac
      ;;
    -P*) PLATFORM="${ARG#-P}" ;;
  esac
done
# The save state to start from (the launcher's Saves screen): a RetroArch
# slot, "auto" for the automatic state, or an absolute state file for the
# standalone emulator's start script. Anything else starts the game as usual.
[[ "${ENTRYSLOT}" =~ ^([0-9]{1,3}|auto)$ ]] || ENTRYSLOT=""
[[ "${ENTRYSTATE}" == /* && -f "${ENTRYSTATE}" ]] || ENTRYSTATE=""
export ARCHR_ENTRY_STATE="${ENTRYSTATE}"
BASEROMNAME=${ROMNAME##*/}
GAMEFOLDER="${ROMNAME//${BASEROMNAME}}"

### Define the variables used throughout the script
BLUETOOTH_STATE=$(get_setting controllers.bluetooth.enabled)
VERBOSE=false
LOG_DIRECTORY="/var/log"
LOG_FILE="exec.log"
RUN_SHELL="/usr/bin/bash"
RETROARCH_TEMP_CONFIG="/storage/.config/retroarch/retroarch.cfg"
RETROARCH_APPEND_CONFIG="/tmp/.retroarch.cfg"
# Set for a RetroArch game: archr-retroarch-unappend runs after it.
RA_UNAPPEND=0
CURRENT_GAME="/run/archr/current-game"
NETWORK_PLAY="No"
SET_SETTINGS_TMP="/tmp/shader"
OUTPUT_LOG="${LOG_DIRECTORY}/${LOG_FILE}"
SCRIPT_NAME=$(basename "$0")
GAMBATTE_OPT="/storage/.config/retroarch/config/Gambatte/Gambatte.opt"
GAMBATTE_OPT_SAVED="/tmp/.runemu-gambatte.opt"
GAMBATTE_OPT_ABSENT="/tmp/.runemu-gambatte.absent"
# Set only by the run that completed the backup; only that run restores.
GAMBATTE_RESTORE_ARMED=0

### Save Gambatte.opt before a netplay session writes its address into it.
### The copy is made under a temporary name and renamed, so a recovery copy
### only ever exists complete. A copy left by an earlier run whose restore
### failed is never overwritten or deleted: this session is refused.
function save_session_core_options() {
        local tmp="${GAMBATTE_OPT_SAVED}.$$"
        if [ -e "${GAMBATTE_OPT_SAVED}" ] || [ -e "${GAMBATTE_OPT_ABSENT}" ]; then
                echo "runemu.sh: unrestored ${GAMBATTE_OPT} copy in /tmp, restore it first" >&2
                return 1
        fi
        if [ -e "${GAMBATTE_OPT}" ]; then
                if ! { cp -f "${GAMBATTE_OPT}" "${tmp}" && mv -f "${tmp}" "${GAMBATTE_OPT_SAVED}"; }; then
                        rm -f "${tmp}"
                        echo "runemu.sh: could not save ${GAMBATTE_OPT}" >&2
                        return 1
                fi
        else
                : >"${GAMBATTE_OPT_ABSENT}" || return 1
        fi
        GAMBATTE_RESTORE_ARMED=1
}

### Put back the options saved above; non-zero when that fails (the
### recovery copy is then kept).
function restore_session_core_options() {
        [ "${GAMBATTE_RESTORE_ARMED}" = 1 ] || return 0
        GAMBATTE_RESTORE_ARMED=0
        if [ -e "${GAMBATTE_OPT_SAVED}" ]; then
                if cp -f "${GAMBATTE_OPT_SAVED}" "${GAMBATTE_OPT}" && cmp -s "${GAMBATTE_OPT_SAVED}" "${GAMBATTE_OPT}"; then
                        rm -f "${GAMBATTE_OPT_SAVED}"
                else
                        echo "runemu.sh: could not restore ${GAMBATTE_OPT}, copy kept in ${GAMBATTE_OPT_SAVED}" >&2
                        return 1
                fi
        elif [ -e "${GAMBATTE_OPT_ABSENT}" ]; then
                rm -f "${GAMBATTE_OPT}" && rm -f "${GAMBATTE_OPT_ABSENT}" || return 1
        fi
}

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
        local rc=$1
        restore_session_core_options || [ "${rc}" != 0 ] || rc=1
        bluetooth enable
        resume_background_services
        restore_ksm
        set_kill set "archr-launcher"
        rm -f "${CURRENT_GAME}"
        clear_screen
        # Restore CPU governor to user pref (or ondemand fallback). Gameplay
        # switches to the performance governor, so without the fallback the
        # CPU stays pinned at max in the menu, draining battery. The 1512 MHz
        # turbo OPP itself follows the user's overclock toggle (performance()
        # calls restore_cpu_boost), so it is not forced on here.
        DEVICE_CPU_GOVERNOR=$(get_setting system.cpugovernor)
        case "${DEVICE_CPU_GOVERNOR}" in
                performance|ondemand|schedutil|powersave)
                        ${DEVICE_CPU_GOVERNOR}
                        ;;
                *)
                        ondemand
                        ;;
        esac
        exit ${rc}
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

# Ports source /roms/ports/PortMaster/control.txt, which only exists once
# PortMaster is unpacked; until now that happened only when the PortMaster app
# was opened. A port copied from the PC on a fresh card, or a system update
# that changed control.txt, must not depend on it.
function portmaster_ready() {
        if [ -f /storage/roms/ports/PortMaster/control.txt ] &&
           [ -f /storage/.config/PortMaster/mapper.txt ] &&
           cmp -s /usr/config/PortMaster/control.txt /storage/roms/ports/PortMaster/control.txt; then
                return
        fi
        ${VERBOSE} && log $0 "Preparing PortMaster"
        ( . /usr/bin/portmaster_prepare ) >/dev/null 2>>${OUTPUT_LOG}
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

### A disc kept in an archive (.zip or .7z holding a .gdi, .cdi, .chd or
### .cue) on the systems flycast runs. flycast opens any archive as an
### arcade cartridge, so the disc fails ("Unknown game"; the Atomiswave
### conversions are Dreamcast discs). The disc is extracted once to
### DISC_CACHE and that copy runs, its disc file named after the archive so
### saves and states keep the game's name. Only the last disc stays; the
### next one replaces it. Without the room for it, a card says so and the
### game does not start.
DISC_CACHE="${DISC_CACHE:-/storage/.cache/archr-disc}"
SEVENZIP="${SEVENZIP:-/usr/bin/7z}"
GAME_FILE="${ROMNAME}"

disc_card() {
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" archr-osd send disc "$1" >/dev/null 2>&1
}

disc_from_archive() {
  local list inner ext source need free work disc pid rc
  case "${PLATFORM}" in dreamcast|atomiswave|naomi|naomi2|naomigd) ;; *) return 0 ;; esac
  case "${ROMNAME,,}" in *.zip|*.7z) ;; *) return 0 ;; esac
  list=$("${SEVENZIP}" l -slt -- "${ROMNAME}" 2>/dev/null) || return 0
  # Entries only: the first "Path =" is the archive itself.
  list=$(sed -n '/^----------$/,$p' <<<"${list}")
  for ext in gdi cdi chd cue; do
    inner=$(sed -n 's/^Path = //p' <<<"${list}" | grep -i "\.${ext}$" | head -n 1)
    [ -n "${inner}" ] && break
  done
  [ -n "${inner}" ] || return 0
  work="${DISC_CACHE}/disc"
  disc="${work}/${inner%/*}"
  [ "${inner}" = "${inner%/*}" ] && disc="${work}"
  disc="${disc}/${BASEROMNAME%.*}.${ext}"
  source="${ROMNAME}|$(stat -c '%s %Y' "${ROMNAME}")"
  if [ -f "${disc}" ] && [ "$(cat "${DISC_CACHE}/source" 2>/dev/null)" = "${source}" ]; then
    log $0 "Disc in archive: ${disc} (already extracted)"
    GAME_FILE="${disc}"
    return 0
  fi
  rm -rf "${DISC_CACHE}"
  mkdir -p "${DISC_CACHE}" || return 0
  need=$(sed -n 's/^Size = //p' <<<"${list}" | awk '{s += $1} END {printf "%d", s / 1024 + 65536}')
  free=$(df -Pk "${DISC_CACHE}" | awk 'NR == 2 {print $4}')
  if [ "${free:-0}" -lt "${need}" ]; then
    log $0 "Disc in archive: ${need} KiB needed, ${free} KiB free"
    disc_card nospace
    sleep 4
    exit 0
  fi
  "${SEVENZIP}" x -y -o"${work}" -- "${ROMNAME}" >/dev/null 2>&1 &
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    disc_card start
    sleep 3
  done
  wait "${pid}"
  rc=$?
  # Most archives already name the disc after themselves (Hero.zip holding
  # Hero.chd): then it is in place, and mv onto itself would fail.
  if [ "${rc}" -ne 0 ] || [ ! -f "${work}/${inner}" ] ||
     { [ "${work}/${inner}" != "${disc}" ] && ! mv -f "${work}/${inner}" "${disc}"; }; then
    log $0 "Disc in archive: extraction failed (${rc})"
    rm -rf "${DISC_CACHE}"
    return 0
  fi
  printf '%s\n' "${source}" >"${DISC_CACHE}/source"
  log $0 "Disc in archive: ${inner} extracted as ${disc}"
  GAME_FILE="${disc}"
}
disc_from_archive

### Prepare to load our emulator and game.
loginit "$1" "$2" "$3" "$4"
clear_screen
bluetooth disable
# The running game and this script's PID, for the screenshot shortcut's
# file name; a record whose PID is gone is stale (a crash, a reboot). Then
# what archr-game-save-exit needs to save it: system, emulator and core.
mkdir -p "${CURRENT_GAME%/*}" &&
  printf '%s\n%s\n%s\n%s\n%s\n' "${ROMNAME}" "$$" "${PLATFORM}" "${EMULATOR}" "${CORE}" >"${CURRENT_GAME}"
# The game's state from an earlier "save and exit" stops being the latest
# progress now (a launch from it got its path already).
/usr/bin/archr-game-save-exit --forget "${ROMNAME}" 2>/dev/null
# Emulators that can save a state when closed from outside do it while the
# resume, switcher or critical battery features are on (Retomar e alternar,
# Energia): RetroArch's automatic state, Flycast's AutoSaveState.
ARCHR_SAVE_ON_EXIT=1
if [ "$(get_setting launcher.resume)" = off ] && [ "$(get_setting hotkey.switcher.enabled)" = 0 ] &&
   [ "$(get_setting power.battery.critical)" = 0 ]; then
  ARCHR_SAVE_ON_EXIT=0
fi
export ARCHR_SAVE_ON_EXIT
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

    # Netplay flags come from the argument loop at the top. A session
    # host/port/nick/relay session is handed to setsettings.sh for this run
    # only; without them setsettings falls back to the saved
    # global.netplay.* keys.
    # The host and port end up on the RetroArch command line and config:
    # accept only address characters and a real port number.
    if [ -n "${NETPLAY_SESSION_HOST}" ] && [[ ! "${NETPLAY_SESSION_HOST}" =~ ^[A-Za-z0-9.:-]+$ ]]; then
      echo "runemu.sh: invalid netplay host '${NETPLAY_SESSION_HOST}'" >&2
      quit 2
    fi
    if [ -n "${NETPLAY_SESSION_PORT}" ] && { [[ ! "${NETPLAY_SESSION_PORT}" =~ ^[0-9]{1,5}$ ]] ||
         [ "${NETPLAY_SESSION_PORT}" -lt 1 ] || [ "${NETPLAY_SESSION_PORT}" -gt 65535 ]; }; then
      echo "runemu.sh: invalid netplay port '${NETPLAY_SESSION_PORT}'" >&2
      quit 2
    fi
    # The nickname is written into the RetroArch config: plain names only,
    # anything else falls back to the saved nickname.
    if [ -n "${NETPLAY_SESSION_NICK}" ] && [[ ! "${NETPLAY_SESSION_NICK}" =~ ^[A-Za-z0-9_.\ -]{1,32}$ ]]; then
      echo "runemu.sh: ignoring netplay nick '${NETPLAY_SESSION_NICK}'" >&2
      NETPLAY_SESSION_NICK=""
    fi
    if [ -n "${NETPLAY_SESSION_MITM}" ] && [[ ! "${NETPLAY_SESSION_MITM}" =~ ^[A-Za-z0-9]{1,64}$ ]]; then
      echo "runemu.sh: invalid netplay relay session '${NETPLAY_SESSION_MITM}'" >&2
      quit 2
    fi
    if [ -n "${NETPLAY_SESSION_MODE}" ]; then
      ${VERBOSE} && log $0 "Setup netplay ${NETPLAY_SESSION_MODE}."
      set_setting netplay.mode "${NETPLAY_SESSION_MODE}"
    fi
    export NETPLAY_SESSION_MODE NETPLAY_SESSION_HOST NETPLAY_SESSION_PORT \
           NETPLAY_SESSION_NICK NETPLAY_SESSION_SPECTATE NETPLAY_SESSION_MITM

    # Gambatte link play writes the netplay host and port into its core
    # options. When they come from this session, keep the previous file and
    # put it back after the game (see restore_session_core_options).
    if [ "${CORE}" = "gambatte" ] && { [ -n "${NETPLAY_SESSION_HOST}" ] || [ -n "${NETPLAY_SESSION_PORT}" ]; }; then
      save_session_core_options || quit 1
    fi

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
        JAVA_HOME='/opt/jdk'
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


    RUNTHIS='${EMUPERF} /usr/bin/${RABIN} -L /tmp/cores/${CORE}_libretro.so --config ${RETROARCH_TEMP_CONFIG} --appendconfig ${RETROARCH_APPEND_CONFIG} ${ENTRYARGS} "${GAME_FILE}"'

    # A slot loads with -e (its saves go on in that slot); the automatic
    # state loads with autosave on for this run.
    ENTRYARGS=""
    case "${ENTRYSLOT}" in
      auto) AUTOSAVE=1 ;;
      ?*)
        # shellcheck disable=SC2034 # read by the RUNTHIS template
        ENTRYARGS="-e ${ENTRYSLOT}"
        SNAPSHOT="${ENTRYSLOT}"
      ;;
    esac

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
    RA_UNAPPEND=1
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
        portmaster_ready
        if [[ "${ROMNAME,,}" == *".appimage" ]]; then
          RUNTHIS='${EMUPERF} "${ROMNAME}"'
        else
          RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        fi
        chmod +x "${ROMNAME}"
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "windows")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        portmaster_ready
        # Hook into Portmaster control mapping
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "shell")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      *)
        RUNTHIS='${RUN_SHELL} "/usr/bin/start_${CORE%-*}.sh" "${GAME_FILE}" "${PLATFORM}"'
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
### /var/cache/mesa is a symlink into /storage/.cache/mesa_shader_cache
### installed by the archr meta-package; create through the symlink so
### the underlying overlay path exists.
[ -d /var/cache/mesa ] || mkdir -p /var/cache/mesa 2>/dev/null

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
# A launcher module may pick the governor of this launch only.
CPU_GOVERNOR=$(pick_governor "${GOVERNOR_OVERRIDE}" "${CPU_GOVERNOR}")
${VERBOSE} && log $0 "Set emulation performance mode to (${CPU_GOVERNOR})"
${CPU_GOVERNOR}
# ...and its CPU ceiling, after the governor (performance() pins the
# highest); the performance call after the game puts the highest back.
CPU_MAX=$(pick_cpu_max "${CPU_MAX_OVERRIDE}")
if [ -n "${CPU_MAX}" ]; then
  ${VERBOSE} && log $0 "Cap the CPU at ${CPU_MAX} kHz for this launch"
  set_cpu_max_freq "${CPU_MAX}" || :
fi

### Check whether MangoHud is supported and enabled
if [ "${DEVICE_MANGOHUD_SUPPORT}" == "true" ]; then
  MANGOHUD_ENABLED=$(get_setting "archr.mangohud.enabled"  "${PLATFORM}" "${ROMNAME##*/}")
  if [ "${MANGOHUD_ENABLED}" = "1" ]; then
    # Enable GPU profiling and MangoHud with the current overlay settings
    /usr/bin/mangohud_set apply || log $0 "MangoHud settings not applied"
    gpu_profiling "on"
    RUNTHIS="/usr/bin/mangohud ${RUNTHIS}"
    ${VERBOSE} && log $0 "Enabling MangoHud"
  fi
fi

### Where this run's output starts in exec.log and when it started, for an
### error report (archr-error-report) if it fails.
RUN_OFFSET=$(stat -c %s "${OUTPUT_LOG}" 2>/dev/null || echo 0)
RUN_START=${SECONDS}

# If the rom is a shell script just execute it, useful for DOSBOX and ScummVM scan scripts
if [[ "${ROMNAME}" == *".sh" ]] && [ ! "${PLATFORM}" = "ports" ] && [ ! "${PLATFORM}" = "windows" ]; then
        ${VERBOSE} && log $0 "Executing shell script ${ROMNAME}"
        "${ROMNAME}" &>>${OUTPUT_LOG}
        ret_error=$?
else
        ${VERBOSE} && log $0 "Executing $(eval echo ${RUNTHIS})"
        # A launcher module learns from this run: measured under its ceiling.
        PERF_PROBE=""
        if [ "${MEASURE}" = 1 ]; then
          archr-perf-probe $$ &
          # shellcheck disable=SC2128 # $! is the probe's pid
          PERF_PROBE=$!
        fi
        # Launch the emulator at high priority: with the full-preempt
        # kernel this keeps frame pacing stable when background work
        # (udev, journald, wifi) wakes up mid-frame. Same value dArkOS
        # uses for its emulators.
        eval nice -n -19 ${RUNTHIS} &>>${OUTPUT_LOG}
        ret_error=$?
        if [ -n "${PERF_PROBE}" ]; then
          kill -TERM "${PERF_PROBE}" 2>/dev/null
          wait "${PERF_PROBE}" 2>/dev/null
        fi
fi

### A failed run is reported, unless reports are off. Its own unit: this
### game's scope is stopped as soon as runemu.sh returns, and the report
### must not hold the launcher back. archr-error-report leaves out exits
### that come from outside (the exit hotkey, a shutdown).
### A port's script usually exits 0 even when the game inside it failed:
### every port run goes, and its output decides.
case "${PLATFORM}" in
  ports | windows) REPORT=(port "${ret_error}" "$((SECONDS - RUN_START))" "${RUN_OFFSET}" "${ROMNAME}") ;;
  *) REPORT=(game "${ret_error}" "$((SECONDS - RUN_START))" "${RUN_OFFSET}" "${PLATFORM}" "${EMULATOR}" "${CORE}") ;;
esac
if { [ "${ret_error}" != 0 ] || [ "${REPORT[0]}" = port ]; } &&
   [ "$(get_setting system.error_reports)" != 0 ]; then
  timeout 3 systemd-run --no-block --collect --quiet --unit="archr-error-report-game-$$" \
    -p Nice=10 /usr/bin/archr-error-report "${REPORT[@]}" -- "${ARGV[@]}" >/dev/null 2>&1 || :
fi

### RetroArch saves into retroarch.cfg what the append config only lent to
### this game (savestate folder, pads, overlay): put that back, keep
### what the user changed.
if [ "${RA_UNAPPEND}" = 1 ]; then
  archr-retroarch-unappend "${RETROARCH_TEMP_CONFIG}" "${RETROARCH_APPEND_CONFIG}" ||
    log $0 "retroarch.cfg: the append config could not be taken back"
fi

### Switch back to performance mode to clean up
performance

### Saves, states and screenshots live with the ROMs, on exFAT when the card
### has the ROMs partition (no journal). The emulators write them on exit but
### never fsync: write them out now, so a device turned off in the menu
### keeps them.
sync

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
