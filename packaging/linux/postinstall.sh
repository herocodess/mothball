#!/bin/sh
# Refresh the app menu and icon caches so Mothball shows up straight away.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
# A running Mothball service notices its program was replaced and restarts
# itself on the new version within a minute.
exit 0
