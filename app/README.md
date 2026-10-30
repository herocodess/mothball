# Mothball desktop app

The Flutter desktop app for macOS, Windows and Linux lives here. It is a window only: it never touches files. It talks to the Mothball background service over a local JSON API, the same one the CLI uses.

The menu bar and tray icon belong to the background service, not this app, so Mothball stays light when the window is closed.

Not started yet. It is milestone 4 in the v1 plan. Create it with:

```sh
flutter create --platforms=macos,windows,linux --org dev.mothball app
```
