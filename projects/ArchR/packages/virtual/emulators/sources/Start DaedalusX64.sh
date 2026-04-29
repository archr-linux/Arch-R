#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025 ArchR (https://github.com/archr-linux/Arch-R)

source /etc/profile

set_kill set "daedalus"

sway_fullscreen "daedalus" &

cd /storage/.config/DaedalusX64/
/storage/.config/DaedalusX64/daedalus >/dev/null 2>&1
