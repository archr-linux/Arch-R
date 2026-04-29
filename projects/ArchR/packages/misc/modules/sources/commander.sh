#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025 ArchR (https://github.com/archr-linux/Arch-R)

. /etc/profile
set_kill set "commander"

sway_fullscreen "commander" &

/usr/bin/commander
