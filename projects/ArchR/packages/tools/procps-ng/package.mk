# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/tools/procps-ng/package.mk

PKG_MAKE_OPTS_TARGET="src/free src/top/top src/ps/pscommand library/libproc2.la library/libproc2.pc"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -P ${PKG_BUILD}/.${TARGET_NAME}/src/free ${INSTALL}/usr/bin
    cp -P ${PKG_BUILD}/.${TARGET_NAME}/src/top/top ${INSTALL}/usr/bin
    cp -P ${PKG_BUILD}/.${TARGET_NAME}/src/ps/pscommand ${INSTALL}/usr/bin/ps

  make DESTDIR=${SYSROOT_PREFIX} -j1 ${PKG_MAKEINSTALL_OPTS_TARGET}

  sed 's@proc/misc.h@procps/misc.h@' \
    ${PKG_BUILD}/library/include/readproc.h \
    >${SYSROOT_PREFIX}/usr/include/libproc2/readproc.h
}
