. ${ROOT}/packages/sysutils/dbus/package.mk

post_makeinstall_target() {
  # Ensure /run/dbus is created by the socket unit (not dependent on tmpfiles timing)
  # Add SocketMode and DirectoryMode to dbus.socket
  cat > ${INSTALL}/usr/lib/systemd/system/dbus.socket <<'SOCKET'
[Unit]
Description=D-Bus System Message Bus Socket

[Socket]
ListenStream=/run/dbus/system_bus_socket
SocketMode=0666
DirectoryMode=0755

[Install]
WantedBy=sockets.target
SOCKET

  # Add RuntimeDirectory and let dbus-daemon handle its own privilege dropping
  # Remove User=dbus/Group=dbus so dbus-daemon starts as root and drops to dbus user itself
  # This avoids "Failed to drop supplementary groups: Operation not permitted" warning
  sed -i '/^\[Service\]/a RuntimeDirectory=dbus\nRuntimeDirectoryMode=0755' \
    ${INSTALL}/usr/lib/systemd/system/dbus.service
  sed -i '/^User=dbus/d;/^Group=dbus/d' \
    ${INSTALL}/usr/lib/systemd/system/dbus.service

  # Ensure /run/dbus is also in tmpfiles as backup
  echo 'd /run/dbus 0755 root root -' >> ${INSTALL}/usr/lib/tmpfiles.d/dbus.conf

  # Fix machine-id: remove symlink to /storage (not available at dbus start time)
  # systemd will auto-generate machine-id on first boot if the file is empty
  rm -f ${INSTALL}/etc/machine-id
  touch ${INSTALL}/etc/machine-id
}
