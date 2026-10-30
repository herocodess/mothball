#!/bin/sh
# Generates the macOS, Windows and Linux runner folders for the app, then
# adjusts macOS so the app can reach the local Mothball service.
# Run once from the app folder:  sh setup.sh
set -e
cd "$(dirname "$0")"

flutter create --platforms=macos,windows,linux --org dev.mothball --project-name mothball .

# Mothball ships outside the App Store and must read its state folder in
# ~/Library/Application Support, so the App Sandbox is turned off, and the
# app needs to open a local network connection to the service.
if [ -d macos/Runner ]; then
  for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    /usr/libexec/PlistBuddy -c "Set :com.apple.security.app-sandbox false" "$f" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$f" 2>/dev/null ||
      /usr/libexec/PlistBuddy -c "Set :com.apple.security.network.client true" "$f" 2>/dev/null || true
  done
fi

flutter pub get
echo "Done. Start the service with 'mothball service install', then run 'flutter run -d macos'."
