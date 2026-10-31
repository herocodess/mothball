# Mothball desktop app

The Flutter app for macOS, Windows and Linux. It is a window only: it never touches files. Everything goes through the Mothball background service's local API, the same engine the CLI uses, so autopilot keeps running when the window is closed.

What it shows:

- Free space, the autopilot switch and your target
- Build output in idle projects, with "Put away" per folder or all at once
- Mothballed projects, with "Wake" (highlighted when you're back on one)
- Recent autopilot activity
- Settings: idle threshold, free space target, auto-empty, folders to watch
- On macOS, a first-run screen that asks once for Full Disk Access, so Desktop, Documents and Downloads can be scanned without a prompt per folder

The app has no third-party packages; the logo is drawn in code.

## Run it

You need Flutter and the `mothball` CLI on your PATH.

```sh
go install github.com/herocodess/mothball/cli/mothball@latest   # or build from the repo root
mothball service install                                        # start the background service
cd app
sh setup.sh                                                     # once: creates the platform folders
flutter run -d macos                                            # or windows, linux
```

`setup.sh` turns off the macOS App Sandbox and allows local network access, because the app reads the service's private endpoint file in `~/Library/Application Support/mothball` and talks to it on 127.0.0.1.
