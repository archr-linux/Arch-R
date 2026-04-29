#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025 ArchR (https://github.com/archr-linux/Arch-R)

. /etc/profile
set_kill set "qterminal"

if [ ! -d "/storage/.config/qterminal.org" ]; then
     cp -r "/usr/config/qterminal.org" "/storage/.config/"
fi

sway_fullscreen "qterminal" &

cd ~/
/usr/bin/qterminal
