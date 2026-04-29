#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Remove duplicate variable assignments from cloud_sync.conf, keeping only the first occurrence.
# Usage: ./cloud_sync_cleanup_duplicates.sh /path/to/cloud_sync.conf

CONF_FILE="${1:-/storage/.config/cloud_sync.conf}"
TMP_FILE="${CONF_FILE}.cleaned"

awk '
  /^[[:space:]]*#/ { print; next }
  /^[[:space:]]*$/ { print; next }
  /^[A-Za-z0-9_]+=.*$/ {
    var=gensub(/=.*/, "", 1)
    if (!(var in seen)) {
      print
      seen[var]=1
    }
    next
  }
  { print }
' "$CONF_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONF_FILE"

echo "Duplicate variable assignments removed from $CONF_FILE."
