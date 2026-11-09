#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile
. /etc/os-release
set_kill set "PortMaster"

# Unpack and refresh PortMaster (shared with archr-port-install).
. /usr/bin/portmaster_prepare

#Start PortMaster
cd /storage/roms/ports/PortMaster
./PortMaster.sh 2>/dev/null
