# Release checklist

What has to be true before a public release, by platform. Items are ticked as they land.

## Permissions (macOS)

macOS names whichever program asks for access. During development that is your terminal (or whatever started the process), which is why prompts say "Terminal" or "node". In a release every prompt and every Settings entry must say **Mothball**.

- [x] Mothball checks for Full Disk Access without triggering a prompt
- [x] Without it, scans skip Desktop, Documents, Downloads, Pictures, Movies and Music instead of prompting; a folder you name yourself is still scanned
- [x] First-run screen in the app explains why, opens Settings at Full Disk Access, and shows the program to add in Finder
- [x] Reminder card while access is missing; "Check again" rescans once access is granted
- [x] Ship the service inside `Mothball.app` as Mothball Agent.app, so the Full Disk Access entry is "Mothball" with its icon
- [x] Developer ID Application certificate on a personal team, and notarisation
- [x] `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription` and `NSDownloadsFolderUsageDescription` in Info.plist, in case a prompt is ever shown
- [ ] Check on a clean Mac that the background service picks up access after it is granted, and restarts itself if it does not

## macOS

- [x] Menu bar icon owned by the background service, as a template image
- [x] Hardened runtime, Developer ID signing and notarisation for the app and both binaries
- [x] Universal build (Apple silicon and Intel)
- [x] Signed, notarised, stapled DMG (`scripts/build-mac.sh --dmg`)
- [x] Homebrew cask and formula in herocodess/tap; the cask also links the CLI
- [ ] Folders on external disks: trash to that disk's own `.Trashes` folder instead of skipping

## Windows

- [x] Tray icon owned by the background service, readable on light and dark taskbars
- [x] Installer for x64 and Arm64 (Inno Setup): per user, no admin prompt, PATH, startup app, clean upgrade and uninstall
- [x] No console windows: the service runs as `mothballw.exe`, and the programs it starts are hidden
- [x] Self-update: download the installer for this architecture, check its checksum, run it silently
- [x] CI installs, opens, updates and uninstalls on Windows x64 and Arm64 for every change
- [ ] Code signing (SignPath Foundation, free for open source), so SmartScreen stops warning
- [x] Scoop bucket (herocodess/scoop-bucket), updated from the release checksums
- [ ] winget manifest
- [ ] Auto-empty for the Recycle Bin (off until Mothball can find its own items there safely)

## Linux

- [ ] Tray icon where the desktop supports it
- [ ] AppImage plus .deb and .rpm; CLI on Homebrew for Linux

## Everywhere

- [x] Global caches (Xcode, simulators, npm, pnpm, yarn, pip, uv, Gradle, CocoaPods, Homebrew) cleaned through each tool's own command
- [x] Version tags (`v0.1.0` and up) so `go install ...@latest` resolves to a release
- [x] Release with checksums (built on the Mac for now)
- [x] Update check and in-place update for the macOS app; `update.json` to require one
- [ ] Release builds from CI on a tag

## Publishing a release

1. Bump `version:` in `app/pubspec.yaml`.
2. On the Mac: `SIGN_ID="Developer ID Application: ..." scripts/build-mac.sh --dmg`.
3. Build the Linux CLIs (`GOOS=linux`, amd64 and arm64, `-X main.version=...`). The Windows installers, zips and CLIs are built by the `windows` workflow when the tag is pushed, and attached to the release with their checksums.
4. Write `checksums-<version>.txt` covering every file (`shasum -a 256`). The in-app updater refuses a DMG that is not listed in it.
5. Tag `v<version>`, then `gh release create v<version>` with the DMG, the CLIs and the checksums file.
6. Update the cask and formula in `herocodess/homebrew-tap` (version and sha256), and `bucket/mothball.json` in `herocodess/scoop-bucket` (version and the two zip hashes from the checksums file). From 0.1.1 on, the cask carries `auto_updates true`, since the app updates itself.

### Updates

The service checks `releases/latest` once a day (users can turn this off). The macOS app downloads the DMG, checks its checksum, checks that it is signed by the same developer team and accepted by Gatekeeper, then swaps itself in and restarts. Windows, Linux and the CLI on its own show where to get the update.

To make older versions stop moving files until they update (only for a bug that could put away the wrong thing), attach an `update.json` asset to the release:

```json
{"minimum": "0.1.3", "message": "0.1.2 could misread some Gradle projects. 0.1.3 fixes it."}
```

Versions below `minimum` pause autopilot, cleaning and auto-empty, and the app shows an update screen.
