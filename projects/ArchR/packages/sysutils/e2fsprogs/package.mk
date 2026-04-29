# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

# Use base e2fsprogs without disabling libblkid/libuuid (causes link errors with GCC 15)
. ${ROOT}/packages/sysutils/e2fsprogs/package.mk
