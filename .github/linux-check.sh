#!/bin/sh
# Checks for the Linux packages in CI. Usage:
#   linux-check.sh installed                 files, menu entry, icons, CLI
#   linux-check.sh app <command> <shot.png>  open the app, screenshot, open it again
#   linux-check.sh service <command>         start at login and the background service
#   linux-check.sh removed                   nothing left after uninstalling
set -eu
ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO=sudo
VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/version: *//; s/+.*//')

case "$1" in
installed)
  for f in /opt/mothball/mothball-app /opt/mothball/bin/mothball /opt/mothball/lib/libapp.so /opt/mothball/data/mothball.png \
           /usr/share/applications/dev.mothball.mothball.desktop /usr/share/metainfo/dev.mothball.mothball.metainfo.xml \
           /usr/share/icons/hicolor/256x256/apps/dev.mothball.mothball.png /usr/share/icons/hicolor/16x16/apps/dev.mothball.mothball.png; do
    [ -e "$f" ] && ok "installed $f" || fail "missing $f"
  done
  [ "$(readlink -f /usr/bin/mothball)" = /opt/mothball/bin/mothball ] && ok "/usr/bin/mothball" || fail "/usr/bin/mothball"
  [ "$(readlink -f /usr/bin/mothball-app)" = /opt/mothball/mothball-app ] && ok "/usr/bin/mothball-app" || fail "/usr/bin/mothball-app"
  desktop-file-validate /usr/share/applications/dev.mothball.mothball.desktop && ok "menu entry is valid"
  v=$(mothball version)
  [ "$v" = "mothball $VERSION" ] && ok "$v" || fail "mothball version says '$v'"
  ;;

app)
  # One D-Bus session (for one-instance-at-a-time) and one virtual screen.
  cmd=$2 shot=$3
  mkdir -p "$(dirname "$shot")"
  dbus-run-session -- xvfb-run -a -s "-screen 0 1280x900x24" sh -c '
    set -e
    "$1" > /tmp/app.log 2>&1 &
    first=$!
    sleep 25
    kill -0 $first 2>/dev/null || { echo "FAIL  the app exited"; cat /tmp/app.log; exit 1; }
    import -window root "$2"
    echo "ok    app opened, screenshot $2"
    # A second launch must hand over to the first window and exit.
    "$1" > /tmp/app2.log 2>&1 &
    second=$!
    i=0
    while kill -0 $second 2>/dev/null; do
      i=$((i+1)); [ $i -gt 15 ] && { echo "FAIL  a second copy of the app stayed open"; exit 1; }
      sleep 1
    done
    n=$(pgrep -xc mothball-app || true)
    [ "$n" -eq 1 ] || { echo "FAIL  $n app processes, want 1"; pgrep -xa mothball-app; exit 1; }
    echo "ok    single instance"
    kill $first
  ' sh "$cmd" "$shot"
  ;;

service)
  cmd=$2
  "$cmd" service install
  if [ -f ~/.config/systemd/user/mothball.service ]; then ok "starts at login (systemd)"
  elif [ -f ~/.config/autostart/mothball-service.desktop ]; then ok "starts at login (autostart)"
  else fail "no start at login entry"; fi
  i=0
  until "$cmd" status 2>&1 | grep -q running; do
    i=$((i+1)); [ $i -gt 30 ] && { "$cmd" status || true; fail "background service is not running"; }
    sleep 1
  done
  ok "background service is running"
  # Count by program name: an AppImage keeps a small launcher process alive
  # above the real one, and both have "service run" on their command line.
  n=$(pgrep -xc mothball || true)
  [ "$n" -eq 1 ] && ok "exactly one service" || { pgrep -a mothball; fail "$n service processes"; }
  ;;

removed)
  for f in /opt/mothball /usr/bin/mothball /usr/bin/mothball-app /usr/share/applications/dev.mothball.mothball.desktop \
           /usr/share/icons/hicolor/256x256/apps/dev.mothball.mothball.png; do
    [ -e "$f" ] && fail "still there: $f" || ok "removed $f"
  done
  [ -f ~/.config/systemd/user/mothball.service ] && fail "systemd unit left behind" || ok "no systemd unit"
  [ -f ~/.config/autostart/mothball-service.desktop ] && fail "autostart entry left behind" || ok "no autostart entry"
  if pgrep -fa '/opt/mothball/' >/dev/null; then pgrep -fa '/opt/mothball/'; fail "still running"; fi
  ok "nothing running"
  ;;
esac
