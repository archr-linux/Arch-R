# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="json-glib"
PKG_VERSION="1.10.6"
PKG_SHA256="d23cbd4094a32cc05cf22cd87a83da1f799e182e286133b49fde3c9241a32006"
PKG_LICENSE="LGPL-2.1"
PKG_SITE="https://github.com/GNOME/json-glib"
PKG_URL="https://github.com/GNOME/json-glib/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain glib"
PKG_LONGDESC="JSON-GLib implements a full suite of JSON-related tools using GLib and GObject."

PKG_MESON_OPTS_TARGET="-Dintrospection=disabled \
                       -Dgtk_doc=disabled \
                       -Dman=false \
                       -Dtests=false"
