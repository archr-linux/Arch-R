# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/devel/elfutils/package.mk

pre_configure_host() {
  # GCC 15 treats discarded-qualifiers as error with -Werror
  export CFLAGS="${CFLAGS} -Wno-error=discarded-qualifiers"
  # Fix -std=gnu17 invalid for C++ and same warning for C++ files
  export CXXFLAGS="${CXXFLAGS//-std=gnu17/-std=gnu++17} -Wno-error=discarded-qualifiers"
}
