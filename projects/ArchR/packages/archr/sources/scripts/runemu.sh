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

### When memory runs out, the game is what the OOM killer closes, never
### the compositor or the launcher (they run at -800 and -500, and this
### launch would inherit the launcher's). Everything the game starts
### inherits 300.
echo 300 >/proc/self/oom_score_adj 2>/dev/null

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

### MAME 2003-Plus, the default for arcade, opens only .zip: given a .7z it
### reports every file of the set as NOT FOUND. Every other arcade core reads
### .7z; FinalBurn Neo is the one that plays best on this hardware.
if [ "${EMULATOR}" = "retroarch" ] && [ "${CORE}" = "mame2003_plus" ] &&
   [[ "${ROMNAME,,}" == *.7z ]] && [ -f /usr/lib/libretro/fbneo_libretro.so ]; then
  CORE="fbneo"
fi

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
# that changed control.txt or mod_ArchR.txt, must not depend on it. control.txt
# runs mapper.txt: one that lost its exec bit leaves every port without
# /tmp/gamecontrollerdb.txt (no SDL pad mapping), and the prepare restores it.
function portmaster_ready() {
        if [ -f /storage/roms/ports/PortMaster/control.txt ] &&
           [ -x /storage/.config/PortMaster/mapper.txt ] &&
           cmp -s /usr/config/PortMaster/control.txt /storage/roms/ports/PortMaster/control.txt &&
           cmp -s /usr/config/PortMaster/mod_ArchR.txt /storage/roms/ports/PortMaster/mod_ArchR.txt &&
           cmp -s /usr/config/PortMaster/libgl_ArchR.txt /storage/roms/ports/PortMaster/libgl_ArchR.txt; then
                return
        fi
        ${VERBOSE} && log $0 "Preparing PortMaster"
        ( . /usr/bin/portmaster_prepare ) >/dev/null 2>>${OUTPUT_LOG}
}

# A port copied from a PC or unpacked by hand often loses the execute bit on
# its programs, and the script stops at "Permission denied". Before a port:
# its folder (the one whose port.json lists the script, else the script's
# GAMEDIR) gets +x on programs that lack it: ELF files and #! scripts, among
# files with no extension or a program-like one. Nothing else is touched.
function port_dir() {
        local script=$1 base=${1##*/} json dir
        for json in "${script%/*}"/*/port.json; do
                [ -f "${json}" ] || continue
                jq -e --arg s "${base}" '.items // [] | index($s)' "${json}" >/dev/null 2>&1 && {
                        echo "${json%/port.json}"
                        return
                }
        done
        dir=$(sed -n 's#^[[:space:]]*GAMEDIR=.*/\([^/"$ ]*\)"\{0,1\}[[:space:]]*$#\1#p' "${script}" 2>/dev/null | head -n 1)
        [ -n "${dir}" ] && [ -d "${script%/*}/${dir}" ] && echo "${script%/*}/${dir}"
}
# PortMaster's own tools (gptokeyb, oga_controls...) lose it the same way
# when the PortMaster folder was copied from a PC or another system: the
# port then runs without its controls ("gptokeyb: Permission denied").
function port_programs() {
        find "$1" -maxdepth "$2" -type f ! -perm -u+x \( ! -name '*.*' -o -name '*.sh' \
                -o -name '*.aarch64' -o -name '*.arm64' -o -name '*.armhf' -o -name '*.bin' \
                -o -name '*.elf' -o -name '*.x86' -o -name '*.x86_64' \) -size +0 -print0 2>/dev/null
}

# /opt/system/Tools (dArkOS) is /run/archr/tools: one link per entry of
# /roms/tools, except PortMaster, which is always Arch R's. A card from
# dArkOS keeps its own PortMaster in /roms/tools, and every port's header
# takes /opt/system/Tools/PortMaster first: its control.txt breaks here.
# The view is made anew each time: whatever was written into it (it is a
# folder in /run, a small tmpfs) was never meant to be there.
TOOLS_VIEW=${TOOLS_VIEW:-/run/archr/tools}
TOOLS_ROMS=${TOOLS_ROMS:-/storage/roms}
function tools_view() {
  local v=${TOOLS_VIEW} e
  rm -rf "${v}"
  mkdir -p "${TOOLS_ROMS}/tools" "${v}" || return 0
  for e in "${TOOLS_ROMS}"/tools/* "${TOOLS_ROMS}"/tools/.[!.]*; do
    [ -e "${e}" ] || continue
    [ "${e##*/}" = PortMaster ] && continue
    ln -s "${e}" "${v}/${e##*/}" 2>/dev/null
  done
  ln -s "${TOOLS_ROMS}/ports/PortMaster" "${v}/PortMaster" 2>/dev/null
}

# PortMaster's own installers (Install.PortMaster.sh, Install.Full.PortMaster.sh,
# Makeself archives) install into /opt/system/Tools when it is a folder, and
# into /roms/ports, where Arch R keeps PortMaster, when it is not. With the
# view there the full one unpacked 660 MB into /run: it filled, and the
# launcher session went down with it. They run without the view.
function portmaster_installer() {
  local head
  head=$(head -n 60 "$1" 2>/dev/null | tr -d '\0')
  grep -q '^# This script was generated using Makeself' <<<"${head}" &&
    grep -qE '^label="PortMaster( Full)? Installer"$' <<<"${head}"
}

# libmali has OpenGL ES alone, yet SDL2 picks its desktop "opengl" renderer
# on it (the window is made, the first draw crashes in libmali): PortMaster
# itself closed at once on the RG43V. Ports there get the GLES2 renderer,
# unless they or the user chose one.
function port_render_driver() {
  [ -d "${MALI_MODULE:-/sys/module/mali_kbase}" ] || return 0
  [ -n "${SDL_RENDER_DRIVER}" ] && return 0
  export SDL_RENDER_DRIVER=opengles2
}

function port_exec_bits() {
        local dir file magic
        dir=$(port_dir "$1")
        { [ -n "${dir}" ] && port_programs "${dir}" 4
          port_programs /storage/roms/ports/PortMaster 1; } |
        while IFS= read -r -d '' file; do
                magic=$(head -c 4 "${file}" 2>/dev/null | od -An -c | tr -d ' ')
                case "${magic}" in
                        177ELF|'#!'*) chmod u+x,go+x "${file}" 2>/dev/null &&
                                ${VERBOSE} && log $0 "Execute bit set on ${file}" ;;
                esac
        done
}

# A PortMaster port mounts its runtime (mono, weston_pkg, frt, a JDK...)
# from PortMaster/libs. The PortMaster app fetches it with the port; a port
# copied by hand (from dArkOS, from a PC) has none, and dies offline or
# half way. Before a port: the runtimes it names (port.json "runtime", or
# the script's <x>runtime="name" and libs/<name>.squashfs) that are missing
# are fetched with harbourmaster, as the catalog scripts do. Offline it
# does not start: a toast says what it needs, and nothing is reported.
PM_DIR=${PM_DIR:-/storage/roms/ports/PortMaster}
function port_runtimes() {
        local script=$1 dir=$2
        {
                [ -f "${dir}/port.json" ] &&
                        jq -r '.attr.runtime // [] | if type == "array" then .[] else . end' "${dir}/port.json"
                if grep -q 'libs/[^[:space:]]*\.squashfs' "${script}"; then
                        sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?[A-Za-z_]*runtime="?([A-Za-z0-9][A-Za-z0-9._+-]*)"?[[:space:]]*(#.*)?$/\2/p' "${script}"
                        grep -oE 'libs/[A-Za-z0-9][A-Za-z0-9._+-]*\.squashfs' "${script}" | sed 's#^libs/##'
                fi
        } 2>/dev/null | sed 's/\.squashfs$//' | grep -xE '[A-Za-z0-9][A-Za-z0-9._+-]*' | sort -u
}
function port_runtime_present() {
        [ -f "${PM_DIR}/libs/$1.squashfs" ] || [ -e "${PM_DIR}/libs/$1" ] || [ -d "${PM_DIR}/runtimes/$1" ]
}
# A runtime cut short (a download that stopped, a copy from the PC that did
# not finish) cannot mount, and the port dies on it with no clear reason.
# The squashfs superblock holds the filesystem's size (bytes_used, 8 bytes
# at offset 40): a smaller file, or one that is no squashfs, is broken.
function port_runtime_broken() {
        local f="${PM_DIR}/libs/$1.squashfs" used size
        [ -f "${f}" ] || return 1
        [ "$(head -c 4 "${f}" 2>/dev/null)" = hsqs ] || return 0
        used=$(od -An -t u8 -j 40 -N 8 "${f}" 2>/dev/null | tr -d ' ')
        size=$(stat -c %s "${f}" 2>/dev/null)
        [ -n "${used}" ] && [ -n "${size}" ] && [ "${size}" -lt "${used}" ]
}
# The port's name for the user: its port.json title, else the script's.
function port_title() {
        local name
        name=$(jq -r '.attr.title // empty' "$2/port.json" 2>/dev/null)
        [ -n "${name}" ] || name=$(basename "$1" .sh)
        echo "${name}"
}
# The screen before a game (archr-prepare, drawn by archr-osd) while a port
# fetches what it needs the first time: PREP_STEPS lists the steps it will
# take ("runtime:NAME", "debian", "disc"), each slow command runs through
# prep_run with that step's place, and prep_end takes the screen away. B on
# that screen stops the command: prep_run returns 130. Without the helper
# the command just runs.
PREPARE=${PREPARE:-/usr/bin/archr-prepare}
PREP_STEPS=""
PREP_TITLE=""
PREP_SHOWN=0
function prep_run() { # STEP [archr-prepare options] -- COMMAND...
        local step=$1 n=0 word opts=() list=()
        shift
        while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts+=("$1"); shift; done
        shift
        IFS='|' read -ra list <<<"${PREP_STEPS:-}"
        for word in "${list[@]}"; do
                [ "${word}" = "${step}" ] && break
                n=$((n + 1))
        done
        if [ ! -x "${PREPARE:-/usr/bin/archr-prepare}" ] || [ "${n}" -ge "${#list[@]}" ]; then
                "$@"
                return
        fi
        PREP_SHOWN=1
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" "${PREPARE:-/usr/bin/archr-prepare}" \
                --title "${PREP_TITLE:-}" --steps "${PREP_STEPS}" --step "${n}" "${opts[@]}" -- "$@"
}
function prep_end() {
        [ "${PREP_SHOWN:-0}" = 1 ] || return 0
        PREP_SHOWN=0
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}" "${PREPARE:-/usr/bin/archr-prepare}" --end
}
# A port's steps: the runtimes to fetch, then Debian when it runs there and
# is not downloaded yet.
function port_prep_plan() {
        local script=$1 dir runtime steps=()
        dir=$(port_dir "${script}")
        while IFS= read -r runtime; do
                [ -n "${runtime}" ] || continue
                if port_runtime_broken "${runtime}" || ! port_runtime_present "${runtime}"; then
                        steps+=("runtime:${runtime}")
                fi
        done < <(port_runtimes "${script}" "${dir}")
        if port_compat_wanted "${script}" && ! "${COMPAT}" status 2>/dev/null | grep -q '^installed: /'; then
                steps+=(debian)
        fi
        PREP_STEPS=$(IFS='|'; echo "${steps[*]}")
        PREP_TITLE=$(port_title "${script}" "${dir}")
}
function port_runtime_ready() {
        local script=$1 dir runtime missing=()
        dir=$(port_dir "${script}")
        while IFS= read -r runtime; do
                [ -n "${runtime}" ] || continue
                # A broken runtime goes, and is fetched again like a missing one.
                if port_runtime_broken "${runtime}"; then
                        log $0 "Port runtime ${runtime} is incomplete: removed to fetch it again"
                        rm -f "${PM_DIR}/libs/${runtime}.squashfs" "${PM_DIR}/libs/${runtime}.squashfs.md5"
                fi
                port_runtime_present "${runtime}" || missing+=("${runtime}")
        done < <(port_runtimes "${script}" "${dir}")
        [ "${#missing[@]}" -gt 0 ] || return 0
        if ${AMIONLINE:-/usr/bin/amionline} >/dev/null 2>&1; then
                # A runtime harbourmaster does not know or could not fetch:
                # the port still starts, and its script says what it lacks.
                for runtime in "${missing[@]}"; do
                        log $0 "Port runtime ${runtime} missing: fetching it"
                        # Its download bars ("X MB / Y MB") feed the screen.
                        prep_run "runtime:${runtime}" --bars -- sh -c \
                                'cd "$1" && exec timeout 900 ./harbourmaster --quiet --no-check runtime_check "$2.squashfs" 2>&1' \
                                sh "${PM_DIR}" "${runtime}" >>${OUTPUT_LOG} 2>&1
                        if [ $? = 130 ]; then
                                log $0 "Port runtime ${runtime}: download cancelled"
                                return 1
                        fi
                done
                return 0
        fi
        log $0 "Port runtime ${missing[*]} missing and no network: not started"
        local name
        name=$(port_title "${script}" "${dir}")
        local need="${missing[*]}"
        case "$(get_setting system.language)" in
        pt*) archr-toast error errors "${name} precisa de ${need}" "Conecte à internet uma vez para baixar" ;;
        es*) archr-toast error errors "${name} necesita ${need}" "Conéctate a internet una vez para descargarlo" ;;
        ru*) archr-toast error errors "${name}: нужен ${need}" "Подключитесь к интернету один раз, чтобы скачать" ;;
        de*) archr-toast error errors "${name} braucht ${need}" "Einmal mit dem Internet verbinden, um es zu laden" ;;
        zh*) archr-toast error errors "${name} 需要 ${need}" "请连接一次互联网以下载" ;;
        *) archr-toast error errors "${name} needs ${need}" "Connect to the internet once to download it" ;;
        esac
        return 1
}

# dArkOS compatibility mode (archr-compat-debian): a port made for dArkOS
# that needs Debian itself runs inside a Debian runtime. system.cfg decides
# first (ports["X.sh"].compat=debian|native, ports.compat=off), then: our
# list, a mark left by an earlier run that failed for want of Debian, or a
# script that installs with apt-get/dpkg. After a run, port_compat_learn
# leaves or takes back that mark.
COMPAT_STATE=${COMPAT_STATE:-/storage/.cache/compat-debian}
COMPAT=${COMPAT:-/usr/bin/archr-compat-debian}
COMPAT_SHARE=${ARCHR_COMPAT_SHARE:-/usr/share/archr/compat-debian}
PORT_COMPAT=0
function port_compat_wanted() {
        local script=$1 base=${1##*/}
        case "$(get_setting compat ports "${base}")" in
        debian | on | 1) return 0 ;;
        native | off | 0) return 1 ;;
        esac
        [ -e "${COMPAT_STATE}/no/${base}" ] && return 1
        [ -e "${COMPAT_STATE}/wanted/${base}" ] && return 0
        "${COMPAT}" listed "${base}" && return 0
        # A command, not a word in a message: at the start of a line or
        # after ; && || then do, maybe behind sudo or $ESUDO.
        grep -qE '(^|;|&&|\|\||\bthen|\bdo)[[:space:]]*((sudo|\$\{?ESUDO\}?)[[:space:]]+)?(apt-get|apt|dpkg)[[:space:]]+(-[-A-Za-z=]+[[:space:]]+)*(install|update|--configure|-i)([[:space:]]|$)' \
                "${script}" 2>/dev/null
}
function port_compat_toast() { # KIND CATEGORY NAME pt|es|ru|de|zh|en texts...
        local kind=$1 cat=$2
        shift 2
        case "$(get_setting system.language)" in
        pt*) archr-toast "${kind}" "${cat}" "$1" "$2" ;;
        es*) archr-toast "${kind}" "${cat}" "$3" "$4" ;;
        *) archr-toast "${kind}" "${cat}" "$5" "$6" ;;
        esac
}
function port_compat_ready() {
        local script=$1 name rc mb size file
        name=$(port_title "${script}" "$(port_dir "${script}")")
        size=$(sed -n 's/^SIZE=//p' "${COMPAT_SHARE}/manifest" 2>/dev/null)
        file=$(sed -n 's/^FILE=//p' "${COMPAT_SHARE}/manifest" 2>/dev/null)
        # Rounded up, as the launcher's page shows it.
        mb=$(( (${size:-0} + 1048575) / 1048576 ))
        # The tool writes <image>.part until it has the manifest's size.
        prep_run debian --watch "${COMPAT_STATE}/${file}.part" --total "${size:-0}" -- \
                "${COMPAT}" ensure >>${OUTPUT_LOG} 2>&1
        rc=$?
        case "${rc}" in
        0) return 0 ;;
        130) log $0 "Compatibility runtime download cancelled: ${name} not started" ;;
        2) log $0 "Compatibility runtime missing and no network: ${name} not started"
           port_compat_toast error network \
                "${name}" "Precisa baixar o Debian: conecte à internet (${mb} MB)" \
                "${name}" "Necesita descargar Debian: conéctate a internet (${mb} MB)" \
                "${name}" "Needs Debian downloaded: connect to the internet (${mb} MB)" ;;
        *) log $0 "Compatibility runtime could not be installed: ${name} not started"
           port_compat_toast error errors \
                "Modo de compatibilidade não instalou" "Veja o espaço livre e tente de novo" \
                "El modo de compatibilidad no se instaló" "Revisa el espacio libre e inténtalo de nuevo" \
                "Compatibility mode did not install" "Check the free space and try again" ;;
        esac
        return 1
}
# What only Debian answers: a library or glibc symbol Arch R lacks, apt or
# dpkg, a python module from Debian's dist-packages.
COMPAT_SIGNS="error while loading shared libraries|version .GLIBC_2\.(4[1-9]|[5-9][0-9])' not found|(apt-get|apt|dpkg): (command )?not found|ModuleNotFoundError: No module named"
function port_compat_learn() {
        local script=$1 offset=$2 base=${1##*/} name
        [ -f "${COMPAT_SHARE}/manifest" ] || return 0
        case "$(get_setting compat ports "${base}")" in debian | on | 1 | native | off | 0) return 0 ;; esac
        tail -c +$((offset + 1)) "${OUTPUT_LOG}" 2>/dev/null | grep -qE "${COMPAT_SIGNS}" || return 0
        name=$(port_title "${script}" "$(port_dir "${script}")")
        if [ "${PORT_COMPAT}" = 1 ]; then
                # Debian did not help either: back to Arch R, for good.
                mkdir -p "${COMPAT_STATE}/no" && rm -f "${COMPAT_STATE}/wanted/${base}" &&
                        : >"${COMPAT_STATE}/no/${base}"
                log $0 "${base} failed in compatibility mode too: not trying it again"
                return 0
        fi
        [ -e "${COMPAT_STATE}/no/${base}" ] && return 0
        mkdir -p "${COMPAT_STATE}/wanted" && : >"${COMPAT_STATE}/wanted/${base}" || return 0
        log $0 "${base} needs Debian: compatibility mode from the next run"
        port_compat_toast info errors \
                "${name}" "Na próxima vez abre com as bibliotecas do Debian" \
                "${name}" "La próxima vez se abre con las bibliotecas de Debian" \
                "${name}" "Next time it opens with Debian's libraries"
}

# PortMaster's bind_directories/bind_files mount a port's save folder (in the
# ports folder) over a path such as ~/.config or /tmp and never take it back. A port deleted
# afterwards leaves that path on a dead folder, and the next port that uses it
# without binding (Sword of Jade after another OHRRPGCE port) cannot write there.
# Before a port: drop binds whose folder is gone. After it: drop the binds it made.
MOUNTINFO=${MOUNTINFO:-/proc/self/mountinfo}
function port_binds() {
        # mountinfo: field 4 is the folder mounted, 5 where; spaces come as \040.
        awk -v want="$1" '$5 !~ "^/storage/roms(/|$)" && $4 ~ "/ports/" &&
                (want != "dead" || $4 ~ "//deleted$") { print $5 }' "${MOUNTINFO}" | sort -u
}
function port_unbind() {
        local target
        while IFS= read -r target; do
                [ -n "${target}" ] || continue
                target=$(printf '%b' "${target}")
                umount -l "${target}" 2>/dev/null &&
                        ${VERBOSE} && log $0 "Unmounted the port bind on ${target}"
        done
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

### Sync and VPN daemons compete with the emulator for CPU, RAM and microSD
### I/O. Stop them on launch and restart only the ones that were running on
### exit (so we never enable a service the user had off). The web file
### server follows Settings › System › During a game (archr-game-services).
GAMEPLAY_PAUSE_SERVICES="syncthing tailscaled zerotier-one"
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
  local list inner ext source need free work disc rc total
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
  # The screen before the game counts the bytes landing in the folder.
  PREP_STEPS=disc
  PREP_TITLE=${BASEROMNAME%.*}
  total=$(sed -n 's/^Size = //p' <<<"${list}" | awk '{s += $1} END {printf "%d", s}')
  prep_run disc --watch "${work}" --total "${total:-0}" -- \
    "${SEVENZIP}" x -y -o"${work}" -- "${ROMNAME}" >/dev/null 2>&1
  rc=$?
  prep_end
  PREP_STEPS=""
  if [ "${rc}" = 130 ]; then
    log $0 "Disc in archive: extraction cancelled"
    rm -rf "${DISC_CACHE}"
    exit 0
  fi
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
        # B on the screen while the files come down: back to the launcher.
        /usr/bin/easyrpg.sh "${BASEROMNAME%.*}"
        [ $? = 130 ] && quit 0
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

    ### EasyRPG closes through the frontend (its title's Exit, and a game
    ### that cannot load): back to the launcher, not RetroArch's own menu.
    ### Lent like the rest: archr-retroarch-unappend puts it back after.
    case ${CORE} in
      easyrpg)
        echo 'load_dummy_on_core_shutdown = "false"' >>"${RETROARCH_APPEND_CONFIG}"
      ;;
    esac

    ### NPU upscale (npu-upscale, the RK3562's NPU; dArkOS's NPU UPSCALE):
    ### the frame shown x3, integer scale, square pixels, nearest, and
    ### enlarged on the NPU (PS1 and the 16-bit consoles: 960x720 at most).
    ### Setting npu_upscale (off, auto, x2, x3), per game or platform; the
    ### append config's lines go back after the game with the rest of it.
    ### Nothing happens where "npu-upscale supported" fails.
    NPU_SPEC=""
    if command -v npu-upscale >/dev/null 2>&1 && npu-upscale supported; then
      NPU_SPEC=$(npu-upscale spec "${PLATFORM}" "$(get_setting npu_upscale "${PLATFORM}" "${ROMNAME##*/}")")
      if [ -n "${NPU_SPEC}" ]; then
        ${VERBOSE} && log $0 "NPU upscale ${NPU_SPEC}"
        npu-upscale retroarch-append "${RETROARCH_APPEND_CONFIG}"
        NPU_LIB32=""
        [ "${RABIN}" = "retroarch32" ] && NPU_LIB32="--lib32"
        RUNTHIS=$(echo "${RUNTHIS}" | sed "s|/usr/bin/\${RABIN}|/usr/bin/npu-upscale exec ${NPU_LIB32} ${NPU_SPEC} -- /usr/bin/\${RABIN}|")
      fi
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
        # No emulator name for the exit shortcut to kill: archr-port-stop
        # finds the port's script and closes it with what it started.
        set_kill set "@port"
        # A port's own "systemctl restart emustation" (PortMaster's installer)
        # must not fail: the shim answers it, the launcher re-reads the list.
        export PATH="/usr/lib/archr/port-shims:${PATH}"
        port_binds dead | port_unbind
        PORT_BINDS_BEFORE=$(port_binds)
        if [[ "${ROMNAME,,}" == *".appimage" ]]; then
          RUNTHIS='${EMUPERF} "${ROMNAME}"'
        else
          RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        fi
        chmod +x "${ROMNAME}"
        port_exec_bits "${ROMNAME}"
        port_prep_plan "${ROMNAME}"
        port_runtime_ready "${ROMNAME}" || { prep_end; quit 0; }
        # dArkOS tools live in /roms/tools (= /opt/system/Tools).
        if portmaster_installer "${ROMNAME}"; then
          rm -rf "${TOOLS_VIEW}"
        elif grep -qE '/roms2?/tools|/opt/system/Tools' "${ROMNAME}" 2>/dev/null; then
          tools_view
        fi
        port_render_driver
        if port_compat_wanted "${ROMNAME}"; then
          port_compat_ready "${ROMNAME}" || { prep_end; quit 0; }
          PORT_COMPAT=1
          log $0 "Running ${ROMNAME##*/} in the dArkOS compatibility mode"
          RUNTHIS='${EMUPERF} ${COMPAT} run -- ${RUN_SHELL} "${ROMNAME}"'
        fi
        prep_end
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
        # The Debian mode has none of the pad tools mapper.txt uses: the
        # mapping is made here, and control.txt in there reuses it.
        if [ "${PORT_COMPAT}" = 1 ]; then
          rm -f /tmp/gamecontrollerdb.txt
          /storage/.config/PortMaster/mapper.txt /tmp/gamecontrollerdb.txt /storage/roms/ports/PortMaster >/dev/null 2>>${OUTPUT_LOG}
        fi
      ;;
      "windows")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        portmaster_ready
        set_kill set "@port"
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
    if [ "${RABIN}" = "retroarch32" ] && [ -f /usr/lib32/mangohud/libMangoHud_shim.so ]; then
      # 32-bit RetroArch: /usr/bin/mangohud preloads /usr/$LIB/mangohud,
      # which is lib, the 64-bit one, for both; use the 32-bit build.
      RUNTHIS="env MANGOHUD=1 LD_PRELOAD=/usr/lib32/mangohud/libMangoHud_shim.so ${RUNTHIS}"
    else
      RUNTHIS="/usr/bin/mangohud ${RUNTHIS}"
    fi
    ${VERBOSE} && log $0 "Enabling MangoHud"
  fi
fi

### Where this run's output starts in exec.log and when it started, for an
### error report (archr-error-report) if it fails.
RUN_OFFSET=$(stat -c %s "${OUTPUT_LOG}" 2>/dev/null || echo 0)
RUN_START=${SECONDS}

### Settings › System › During a game: the services the player chose stop
### (archr-game-services) and the memory guard watches beside the game
### (archr-memory-guard), in this scope. Both end with the game below.
archr-game-services pause >/dev/null 2>&1 &
GAME_SERVICES=$!
MEMORY_GUARD=""
if [ "$(get_setting game.memory_guard)" != 0 ]; then
  archr-memory-guard $$ "${ROMNAME##*/}" >/dev/null 2>&1 &
  MEMORY_GUARD=$!
fi

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

[ -n "${MEMORY_GUARD}" ] && kill "${MEMORY_GUARD}" 2>/dev/null
[ -n "${NPU_SPEC}" ] && npu-upscale down
# After the pause (a game that ends at once), and in the background: Wi-Fi
# coming back must not hold the menu.
wait "${GAME_SERVICES}" 2>/dev/null
setsid archr-game-services resume >/dev/null 2>&1 </dev/null &

if [ "${PLATFORM}" = "ports" ]; then
  comm -13 <(printf '%s\n' "${PORT_BINDS_BEFORE}") <(port_binds) | port_unbind
  port_compat_learn "${ROMNAME}" "${RUN_OFFSET}"
fi

### A failed run is reported, unless reports are off. Its own unit: this
### game's scope is stopped as soon as runemu.sh returns, and the report
### must not hold the launcher back. archr-error-report leaves out exits
### that come from outside (the exit hotkey, a shutdown).
### A port's script usually exits 0 even when the game inside it failed:
### every port run goes, and its output decides. It goes with reports off
### too: a port that failed for a reason the user can fix (no game files,
### no network) gets a toast saying so, and only the report waits on the
### setting.
case "${PLATFORM}" in
  ports | windows) REPORT=(port "${ret_error}" "$((SECONDS - RUN_START))" "${RUN_OFFSET}" "${ROMNAME}") ;;
  *) REPORT=(game "${ret_error}" "$((SECONDS - RUN_START))" "${RUN_OFFSET}" "${PLATFORM}" "${EMULATOR}" "${CORE}") ;;
esac
if [ "${REPORT[0]}" = port ] ||
   { [ "${ret_error}" != 0 ] && [ "$(get_setting system.error_reports)" != 0 ]; }; then
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

### Save sync (archr-savesync): this game's system, in the background so
### the menu is back at once; the folder under /storage/roms names it.
if [ "$(get_setting savesync.enabled)" = "1" ]; then
  SYNC_SYSTEM=${ROMNAME#/storage/roms/}
  [ "${SYNC_SYSTEM}" = "${ROMNAME}" ] && SYNC_SYSTEM="" || SYNC_SYSTEM=${SYNC_SYSTEM%%/*}
  setsid /usr/bin/archr-savesync sync --exit ${SYNC_SYSTEM:+--system "${SYNC_SYSTEM}"} \
    >/dev/null 2>&1 </dev/null &
fi

${VERBOSE} && log $0 "Checking errors: ${ret_error} "
if [ "${ret_error}" == "0" ]
then
        quit 0
else
        log $0 "exiting with ${ret_error}"
        quit 1
fi
