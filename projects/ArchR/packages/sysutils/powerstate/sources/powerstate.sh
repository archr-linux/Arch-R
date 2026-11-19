#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

###
### Normally this would be a udev rule, but some devices like the AyaNeo Air
### do not properly report the applied power state to udev, and we can't use
### inotifyd to watch the status in /sys.
###

. /etc/profile

BATCNT=0
unset CURRENT_MODE
unset AC_STATUS
ledcontrol $(get_setting led.color)

# The status a change has to hold before it counts, and for how many polls.
# On boards that charge through their own IC (R36S and clones) the status
# comes from the pack's net current, which crosses zero over and over while
# a game is played on the charger: without the wait the GPU level flipped
# every two seconds and undid the level runemu set for the game.
PENDING=""
HELD=0
SETTLE=3

while true; do
  AC_STATUS="$(cat /sys/class/power_supply/[bB][aA][tT]*/status 2>/dev/null)"
  if [ "${AC_STATUS}" = "${PENDING}" ]; then
    HELD=$(( HELD + 1 ))
  else
    PENDING="${AC_STATUS}"
    HELD=1
  fi
  if [ -n "${CURRENT_MODE}" ] && (( HELD < SETTLE )); then
    AC_STATUS="${CURRENT_MODE}"
  fi
  if [[ ! "${CURRENT_MODE}" =~ ${AC_STATUS} ]]; then
    case ${AC_STATUS} in
      Disch*)
        log $0 "Switching to battery mode."
        if [ -e "/tmp/.gpu_performance_level" ]; then
          GPUPROFILE=$(cat /tmp/.gpu_performance_level)
        else
          GPUPROFILE=$(get_setting system.gpuperf)
        fi
        if [ -z "${GPUPROFILE}" ]; then
          GPUPROFILE="auto"
        fi
        gpu_performance_level ${GPUPROFILE}
        if [ "${DEVICE_LED_CHARGING}" = "true" ]; then
          ledcontrol discharging
        fi
      ;;
      *)
        log $0 "Switching to performance mode."
        gpu_performance_level auto
        if [ "${DEVICE_LED_CHARGING}" = "true" ]; then
          ledcontrol charging
        fi
      ;;
    esac
    CURRENT_MODE="${AC_STATUS}"
  fi
  ### Until we have an overlay. :rofl:
  BATLEFT=$(battery_percent)
  if (( "${BATCNT}" >= "20" )) && [[ "${AC_STATUS}" =~ Disch ]]; then
    AUDIBLEALERT=$(get_setting system.battery.warning)
    AUDIBLEALERT_THRESHOLD=$(get_setting system.battery.warning_threshold)
    [[ -z $AUDIBLEALERT_THRESHOLD ]] && AUDIBLEALERT_THRESHOLD=25

    if [[ ${BATLEFT} -le ${AUDIBLEALERT_THRESHOLD} ]]; then
      if [ "${DEVICE_LED_CONTROL}" = "true" ] && [ ! "${DEVICE_BATTERY_LED_STATUS}" = "true" ]; then
        # Flash the RGB or power LED if available.
        led_flash
        BATCNT=0
      elif [ "${AUDIBLEALERT}" = "1" ]; then
        say "BATTERY AT ${BATLEFT}%"
        BATCNT=0
      fi
    fi
  elif (( "${BATLEFT}" > "97" )); then
    if [ "${DEVICE_LED_CHARGING}" = "true" ]; then
      # Reset the LED as if the battery was full.
      ledcontrol discharging
    fi
  fi
  BATCNT=$(( ${BATCNT} + 1 ))
  sleep 2
done
