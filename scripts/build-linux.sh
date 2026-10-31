#!/bin/sh
# Builds Mothball for Linux and packs it as an AppImage, a .deb and an .rpm.
#
#   scripts/build-linux.sh
#
# Flutter builds for the machine it runs on, so run it on an x64 machine for
# x64 packages and on an Arm64 machine for Arm64 ones. Build on the oldest
# distro you support (CI uses Ubuntu 22.04) so the app runs on newer ones too.
#
# Needs Go, Flutter's Linux toolchain (clang, cmake, ninja, pkg-config,
# libgtk-3-dev), nfpm, and appimagetool (APPIMAGETOOL, or downloaded).
#
# Output, in build/linux-release:
#   Mothball-<v>-linux-<x86_64|aarch64>.AppImage
#   mothball_<v>-1_<amd64|arm64>.deb
#   mothball-<v>-1.<x86_64|aarch64>.rpm
#   mothball-<v>-linux-<amd64|arm64>        the command line tool on its own
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

case "$(uname -m)" in
  x86_64) FLUTTER_ARCH=x64; GOARCH=amd64; AI_ARCH=x86_64 ;;
  aarch64|arm64) FLUTTER_ARCH=arm64; GOARCH=arm64; AI_ARCH=aarch64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/version: *//; s/+.*//')
echo "Building Mothball $VERSION for Linux $AI_ARCH"

OUT="$ROOT/build/linux-release"
rm -rf "$OUT"
mkdir -p "$OUT"

# 1. The command line tool (also the background service).
CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -trimpath \
  -ldflags "-s -w -X main.version=$VERSION" -o "$OUT/mothball-$VERSION-linux-$GOARCH" ./cli/mothball

# 2. The desktop app, with the service in bin/ and the icon in data/.
(cd app && flutter build linux --release)
BUNDLE="$ROOT/app/build/linux/$FLUTTER_ARCH/release/bundle"
test -x "$BUNDLE/mothball-app" || { echo "no mothball-app in $BUNDLE" >&2; exit 1; }
mkdir -p "$BUNDLE/bin"
cp "$OUT/mothball-$VERSION-linux-$GOARCH" "$BUNDLE/bin/mothball"
cp packaging/linux/icons/256.png "$BUNDLE/data/mothball.png"

# AppStream metadata with this version and today's date.
METAINFO="$OUT/dev.mothball.mothball.metainfo.xml"
sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$(date -u +%Y-%m-%d)/" \
  packaging/linux/dev.mothball.mothball.metainfo.xml > "$METAINFO"

# 3. .deb and .rpm.
#    nfpm expands variables in fields like version and arch, but not in the
#    file list, so the paths are written into a copy of the config.
NFPM=${NFPM:-nfpm}
CONF="$OUT/nfpm.yaml"
sed -e "s|\${BUNDLE}|$BUNDLE|g" -e "s|\${METAINFO}|$METAINFO|g" -e "s| packaging/linux/| $ROOT/packaging/linux/|g" packaging/linux/nfpm.yaml > "$CONF"
for packager in deb rpm; do
  VERSION=$VERSION ARCH=$GOARCH "$NFPM" package --config "$CONF" --packager $packager --target "$OUT/"
done
rm "$CONF"

# 4. AppImage: the same bundle under opt/mothball, with AppRun choosing
#    between the app and the command line tool.
APPDIR="$OUT/AppDir"
mkdir -p "$APPDIR/opt" "$APPDIR/usr/share/metainfo"
cp -a "$BUNDLE" "$APPDIR/opt/mothball"
cp packaging/linux/AppRun "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
sed 's|^Exec=.*|Exec=mothball-app|' packaging/linux/dev.mothball.mothball.desktop > "$APPDIR/dev.mothball.mothball.desktop"
cp packaging/linux/icons/256.png "$APPDIR/dev.mothball.mothball.png"
ln -s dev.mothball.mothball.png "$APPDIR/.DirIcon"
cp "$METAINFO" "$APPDIR/usr/share/metainfo/dev.mothball.mothball.appdata.xml"

TOOL=${APPIMAGETOOL:-}
if [ -z "$TOOL" ]; then
  TOOL="$OUT/appimagetool"
  curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$AI_ARCH.AppImage"
  chmod +x "$TOOL"
fi
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=$AI_ARCH "$TOOL" --no-appstream "$APPDIR" "$OUT/Mothball-$VERSION-linux-$AI_ARCH.AppImage"
rm -rf "$APPDIR" "$OUT/appimagetool"

cd "$OUT"
for f in *.AppImage *.deb *.rpm mothball-*-linux-*; do
  printf '%s  %s  (%s)\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f" "$(du -h "$f" | cut -f1)"
done
