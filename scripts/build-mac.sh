#!/bin/sh
# Builds Mothball.app with the background service inside it.
#
#   scripts/build-mac.sh            release build
#   scripts/build-mac.sh --debug    debug build
#
# The service is packaged as a small hidden app, "Mothball Agent.app", inside
# Mothball.app/Contents/Library/LoginItems. Giving it its own bundle, name and
# icon is what makes macOS show "Mothball" with the logo in Full Disk Access
# and Login Items, instead of a bare "mothball" file.
#
# Signing: set SIGN_ID to a "Developer ID Application: ..." identity to sign
# for distribution. Without it, the agent is signed with the same identity
# Xcode used for the app, so the frameworks inside still load.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

MODE=release
CONFIG=Release
if [ "$1" = "--debug" ]; then MODE=debug; CONFIG=Debug; fi

echo "Building the service..."
mkdir -p build
CGO_ENABLED=1 go build -trimpath -ldflags "-s -w" -o build/mothball ./cli/mothball

echo "Building the app ($MODE)..."
(cd app && flutter build macos --$MODE >/dev/null)
APP="$ROOT/app/build/macos/Build/Products/$CONFIG/Mothball.app"

AGENT="$APP/Contents/Library/LoginItems/Mothball Agent.app"
rm -rf "$AGENT"
mkdir -p "$AGENT/Contents/MacOS" "$AGENT/Contents/Resources"
cp build/mothball "$AGENT/Contents/MacOS/mothball"
cp "$APP/Contents/Resources/AppIcon.icns" "$AGENT/Contents/Resources/AppIcon.icns"
VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/version: *//; s/+.*//')
cat > "$AGENT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.mothball.agent</string>
  <key>CFBundleName</key><string>Mothball</string>
  <key>CFBundleDisplayName</key><string>Mothball</string>
  <key>CFBundleExecutable</key><string>mothball</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Mothball looks for build output in projects on your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Mothball looks for build output in projects in Documents.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Mothball looks for build output in projects in Downloads.</string>
</dict>
</plist>
PLIST

SIGN=${SIGN_ID:-$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)}
SIGN=${SIGN:--}
OPTS=""
[ "$SIGN" != "-" ] && OPTS="--options runtime"
echo "Signing with: $( [ "$SIGN" = "-" ] && echo "ad hoc" || echo "$SIGN" )"
# Inside out: frameworks, the agent, then the app, all with one identity.
for f in "$APP"/Contents/Frameworks/*.framework "$APP"/Contents/Frameworks/*.dylib; do
  [ -e "$f" ] && codesign --force $OPTS --timestamp=none --sign "$SIGN" "$f"
done
codesign --force $OPTS --timestamp=none --sign "$SIGN" "$AGENT"
codesign --force $OPTS --timestamp=none --sign "$SIGN" --preserve-metadata=identifier,entitlements,requirements,flags "$APP"
codesign --verify --deep --strict "$APP"

echo
echo "Built: $APP"
echo "Start the service from inside it:"
echo "  \"$AGENT/Contents/MacOS/mothball\" service install"
