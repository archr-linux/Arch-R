#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025 ArchR (https://github.com/archr-linux/Arch-R)

source /etc/profile

set_kill set "flycast"

sway_fullscreen "flycast" &

/usr/bin/flycast >/dev/null 2>&1
