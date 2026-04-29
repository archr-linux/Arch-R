# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/tools/populatefs/package.mk

post_unpack() {
  # Fix major/minor: add missing include and rename variables conflicting with glibc macros
  sed -i '1i #include <sys/sysmacros.h>' ${PKG_BUILD}/src/mod_path.c
  sed -i 's/unsigned long major = 0, minor = 0;/unsigned long dev_major = 0, dev_minor = 0;/' ${PKG_BUILD}/src/mod_path.c
  sed -i 's/major = (long)major/dev_major = (long)major/' ${PKG_BUILD}/src/mod_path.c
  sed -i 's/minor = (long)minor/dev_minor = (long)minor/' ${PKG_BUILD}/src/mod_path.c
  sed -i 's/type, major, minor/type, dev_major, dev_minor/' ${PKG_BUILD}/src/mod_path.c
}

makeinstall_host() {
  ${STRIP} src/populatefs

  mkdir -p ${TOOLCHAIN}/sbin ${TOOLCHAIN}/bin
  cp src/populatefs ${TOOLCHAIN}/sbin
  ln -sf ../sbin/populatefs ${TOOLCHAIN}/bin/populatefs
}
