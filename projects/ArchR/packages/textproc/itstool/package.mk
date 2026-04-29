# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/textproc/itstool/package.mk

pre_configure_host() {
  export PYTHONPATH="${TOOLCHAIN}/python:${PYTHONPATH}"
}
