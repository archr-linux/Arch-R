#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ArchR (https://github.com/archr-linux/Arch-R)

### setup is the same
. $(dirname $0)/es_settings

emulationstation --log-path /var/log --no-splash
