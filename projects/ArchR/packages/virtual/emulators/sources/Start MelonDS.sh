
#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. /etc/profile

set_kill set "-9 melonDS"

sway_fullscreen "net.kuribo64.melonDS" &

# QT platform - use wayland on Wayland compositors, xcb otherwise
if [ -n "${WAYLAND_DISPLAY}" ]; then
    export QT_QPA_PLATFORM=wayland
else
    export QT_QPA_PLATFORM=xcb
fi

/usr/bin/melonDS
