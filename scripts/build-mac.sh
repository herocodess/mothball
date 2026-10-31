#!/bin/sh
# Builds Mothball.app with the background service inside it.
#
#   scripts/build-mac.sh                 release build, signed for this Mac
#   scripts/build-mac.sh --debug         debug build
#   scripts/build-mac.sh --dmg           release build, Developer ID signed,
#                                        packed into a DMG, notarised, stapled
#
# The service is packaged as a small hidden app, "Mothball Agent.app", inside
# Mothball.app/Contents/Library/LoginItems. Giving it its own bundle, name and
# icon is what makes macOS show "Mothball" with the logo in Full Disk Access
# and Login Items, instead of a bare "mothball" file.
#
# Environment:
#   SIGN_ID          signing identity. Required for --dmg: a
#                    "Developer ID Application: ..." identity. Otherwise the
#                    identity Xcode used for the app is reused.
#   NOTARY_PROFILE   keychain profile from `xcrun notarytool store-credentials`
#                    (default: mothball-notary). Used by --dmg.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

MODE=release
CONFIG=Release
DMG=0
case "$1" in
  --debug) MODE=debug; CONFIG=Debug ;;
  --dmg) DMG=1 ;;
esac
NOTARY_PROFILE=${NOTARY_PROFILE:-mothball-notary}
VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/version: *//; s/+.*//')

if [ "$DMG" = 1 ]; then
  case "$SIGN_ID" in
    "Developer ID Application:"*) ;;
    *) echo "--dmg needs SIGN_ID set to a \"Developer ID Application: ...\" identity" >&2; exit 1 ;;
  esac
fi

echo "Building the service ($VERSION, Apple silicon and Intel)..."
mkdir -p build
LDFLAGS="-s -w -X main.version=$VERSION"
for arch in arm64 amd64; do
  CC="clang -arch $( [ $arch = amd64 ] && echo x86_64 || echo arm64 )" \
    CGO_ENABLED=1 GOOS=darwin GOARCH=$arch MACOSX_DEPLOYMENT_TARGET=11.0 \
    go build -trimpath -ldflags "$LDFLAGS" -o build/mothball-$arch ./cli/mothball
done
lipo -create -output build/mothball build/mothball-arm64 build/mothball-amd64

echo "Building the app ($MODE)..."
(cd app && flutter build macos --$MODE >/dev/null)
APP="$ROOT/app/build/macos/Build/Products/$CONFIG/Mothball.app"

AGENT="$APP/Contents/Library/LoginItems/Mothball Agent.app"
rm -rf "$AGENT"
mkdir -p "$AGENT/Contents/MacOS" "$AGENT/Contents/Resources"
cp build/mothball "$AGENT/Contents/MacOS/mothball"
cp "$APP/Contents/Resources/AppIcon.icns" "$AGENT/Contents/Resources/AppIcon.icns"
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
TS="--timestamp=none"
[ "$SIGN" != "-" ] && OPTS="--options runtime"
[ "$DMG" = 1 ] && TS="--timestamp" # notarisation needs a secure timestamp
echo "Signing with: $( [ "$SIGN" = "-" ] && echo "ad hoc" || echo "$SIGN" )"
# Inside out: frameworks, the agent, then the app, all with one identity.
for f in "$APP"/Contents/Frameworks/*.framework "$APP"/Contents/Frameworks/*.dylib; do
  [ -e "$f" ] && codesign --force $OPTS $TS --sign "$SIGN" "$f"
done
codesign --force $OPTS $TS --sign "$SIGN" "$AGENT"
codesign --force $OPTS $TS --sign "$SIGN" --preserve-metadata=identifier,entitlements,requirements,flags "$APP"
codesign --verify --deep --strict "$APP"

if [ "$DMG" = 1 ]; then
  OUT="$ROOT/build/Mothball-$VERSION.dmg"
  STAGE="$ROOT/build/dmg"
  echo "Packing $OUT..."
  rm -rf "$STAGE" "$OUT"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "Mothball" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT"
  codesign --force --timestamp --sign "$SIGN" "$OUT"

  echo "Notarising (this usually takes a few minutes)..."
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
  xcrun stapler staple "$APP"

  echo "Checking Gatekeeper accepts it..."
  spctl --assess --type open --context context:primary-signature -v "$OUT"
  spctl --assess --type execute -v "$APP"

  cp build/mothball "$ROOT/build/mothball-$VERSION-macos-universal"
  (cd build && shasum -a 256 "Mothball-$VERSION.dmg" "mothball-$VERSION-macos-universal" > "checksums-$VERSION-macos.txt")
  echo
  echo "Release files in build/:"
  echo "  Mothball-$VERSION.dmg"
  echo "  mothball-$VERSION-macos-universal   (the CLI on its own)"
  echo "  checksums-$VERSION-macos.txt"
  exit 0
fi

echo
echo "Built: $APP"
echo "Start the service from inside it:"
echo "  \"$AGENT/Contents/MacOS/mothball\" service install"
