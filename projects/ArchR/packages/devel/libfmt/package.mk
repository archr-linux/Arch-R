# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/devel/libfmt/package.mk

case ${DEVICE} in
  SM8250|SM8550|SDM845)
    ;;
  *)
    PKG_VERSION="9.1.0"
    PKG_SHA256=""
    PKG_URL="https://github.com/fmtlib/fmt/archive/${PKG_VERSION}.tar.gz"
    ;;
esac
