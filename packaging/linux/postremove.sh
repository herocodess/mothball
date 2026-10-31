#!/bin/sh
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
# On removal (not an upgrade), stop any Mothball still running from the
# removed files. Each user's settings and history are left in ~/.config.
case "$1" in
  remove|purge|0) pkill -f '^/opt/mothball/' 2>/dev/null || true ;;
esac
exit 0
