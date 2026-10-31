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
- [ ] Homebrew cask; the cask also links the CLI
- [ ] Folders on external disks: trash to that disk's own `.Trashes` folder instead of skipping

## Windows

- [ ] Tray icon owned by the background service
- [ ] Signed installer; winget and Scoop manifests
- [ ] Auto-empty for the Recycle Bin (off until Mothball can find its own items there safely)

## Linux

- [ ] Tray icon where the desktop supports it
- [ ] AppImage plus .deb and .rpm; CLI on Homebrew for Linux

## Everywhere

- [x] Global caches (Xcode, simulators, npm, pnpm, yarn, pip, uv, Gradle, CocoaPods, Homebrew) cleaned through each tool's own command
- [ ] Version tags (`v0.1.0` and up) so `go install ...@latest` resolves to a release
- [ ] Release builds from CI on a tag, with checksums
