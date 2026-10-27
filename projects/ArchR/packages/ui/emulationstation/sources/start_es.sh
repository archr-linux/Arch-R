#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ArchR (https://github.com/archr-linux/Arch-R)

### setup is the same
. $(dirname $0)/es_settings

### sway.service counts as started the moment sway forks, long before it
### has a Wayland socket and an enabled output. Launched too early,
### EmulationStation fails ("wayland not available", then "did not add
### any displays") and systemd retries every 2s: on an R36S that was one
### boot in three reaching the menu 3 to 19s late. Wait until sway can
### actually take a window; it costs nothing when sway is already ready.
for i in $(seq 1 100); do
  SOCK=$(ls ${XDG_RUNTIME_DIR}/sway-ipc.*.sock 2>/dev/null | head -n 1)
  if [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] && [ -n "${SOCK}" ] && \
     swaymsg -s "${SOCK}" -t get_outputs 2>/dev/null | grep -q '"active": true'; then
    break
  fi
  sleep 0.1
done

emulationstation --log-path /var/log --no-splash
