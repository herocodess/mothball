<p align="center">
  <img src="assets/logo.svg" width="96" alt="Mothball logo">
</p>

<h1 align="center">mothball</h1>

<p align="center"><b>Put idle projects away, get your disk back.</b></p>

<p align="center">Clears your build junk, never your code. macOS, Windows, Linux and a CLI.</p>

---

Every project you clone, build and forget keeps its `node_modules`, `build`, `.dart_tool`, `Pods`, `target` and friends on your disk. On one working Mac that added up to **56 GB in projects nobody had touched in 60+ days**. Mothball finds that output, proves it is safe to remove, and clears it automatically when you run low on space.

## Why Mothball

**Free-space autopilot.** Set a target like "keep 50 GB free". When your disk drops below it, Mothball clears the longest idle projects first and stops as soon as you are back above the line. No scans to remember.

**Idle, not just old.** Mothball reads each repo's last commit instead of file timestamps, and only removes a folder it can prove is build output: untracked by git, sitting next to its project file, and matching that stack's known output layout. Your source is never touched.

**Unmothball.** Come back to a project and Mothball offers to wake it up, running the right restore step for its stack (`flutter pub get`, `npm install`, `pod install`, `cargo fetch` and so on). Clearing a project costs you nothing to undo.

## Safety first

- Never removes anything tracked by git
- Never trusts a folder name alone
- Never deletes inside package caches; those are cleaned with their own tool's command
- Moves everything to the Trash with a record of where it came from, so nothing is gone until it is emptied
- Optional auto-empty after a grace period (7 days by default), only ever for folders Mothball itself put in the Trash, each checked against its record
- Skips projects with uncommitted changes or recent activity
- Runs entirely on your machine. No network, no telemetry
- On macOS, asks once for Full Disk Access instead of a prompt per folder; until then it skips the folders macOS keeps private

## What it covers

Each stack is a small rule pack, so adding a new one is a single pull request. 22 packs ship today, and every one is tested automatically against a same-named source folder.

| Area | Stacks |
| --- | --- |
| Web | JavaScript, TypeScript, Next.js, Nuxt, SvelteKit, Astro, Turbo, Parcel, Angular |
| Mobile | Flutter, React Native, Expo, iOS and macOS (CocoaPods, Swift Package Manager), Android (Gradle) |
| JVM | Java, Kotlin, Scala (Gradle, Maven, sbt) |
| Systems | Rust, Zig, C and C++ (CMake) |
| Scripting | Python (venv, pytest, mypy, ruff, tox, nox), Ruby, PHP |
| .NET and functional | C#, F#, VB, Elixir, Erlang, Haskell |
| Games | Unity, Unreal Engine, Godot |
| Infra | Terraform |
| Global caches | Xcode DerivedData, simulators, device support, npm, pnpm, yarn, bun, pip, uv, CocoaPods, Homebrew, Gradle, Go modules, Dart and Flutter packages, VS Code, Cursor and Slack caches |

Caches are cleaned through each tool's own command where there is one (`npm cache clean`, `pod cache clean`, `brew cleanup`), otherwise moved to the Trash, and never while the tool that owns them is running. Cargo and Android emulators are shown for information only.

## Install

**macOS** (Apple silicon and Intel, macOS 11 or later). Download `Mothball-<version>.dmg` from the [latest release](https://github.com/herocodess/mothball/releases/latest), open it and drag Mothball to Applications. It is signed and notarised, includes the `mothball` command, and updates itself.

Or with Homebrew:

```sh
brew tap herocodess/tap
brew trust herocodess/tap
brew install --cask mothball
```

**Windows** (10 and 11, x64 and Arm). Download the installer for your PC from the [latest release](https://github.com/herocodess/mothball/releases/latest):

- `Mothball-<version>-windows-x64-setup.exe` for Intel and AMD PCs
- `Mothball-<version>-windows-arm64-setup.exe` for Arm PCs (Snapdragon, Surface Pro with an Arm chip)

It installs for your account only, with no admin prompt, adds `mothball` to your PATH, runs in the background from your startup apps, and updates itself. Not sure which one you need? Settings > System > About > System type.

Or with [Scoop](https://scoop.sh) (the portable build; run `mothball service install` once to start it at login):

```powershell
scoop bucket add mothball https://github.com/herocodess/scoop-bucket
scoop install mothball/mothball
```

The installer is not code signed yet, so Windows SmartScreen may say it "protected your PC". Choose **More info**, then **Run anyway**. Each release lists SHA-256 checksums so you can check the download.

**Linux** (x64 and Arm64). Download from the [latest release](https://github.com/herocodess/mothball/releases/latest):

- **Any distro:** `Mothball-<version>-linux-x86_64.AppImage` (or `-aarch64` on Arm). Make it executable and run it; it updates itself.

  ```sh
  chmod +x Mothball-*.AppImage
  ./Mothball-*.AppImage
  ```

- **Ubuntu, Debian and friends:** `mothball_<version>-1_amd64.deb` (or `_arm64`)

  ```sh
  sudo apt install ./mothball_*.deb
  ```

- **Fedora, RHEL and friends:** `mothball-<version>-1.x86_64.rpm` (or `.aarch64`)

  ```sh
  sudo dnf install ./mothball-*.rpm
  ```

Each one adds Mothball to your app menu and the `mothball` command to your terminal (for the AppImage, run `./Mothball-*.AppImage scan` and so on). Mothball starts in the background the first time you open it, through systemd when your desktop has it and the autostart folder when it does not. A tray icon shows where your desktop supports one (on GNOME, with the AppIndicator extension).

**Command line only** (macOS, Linux, Windows):

```sh
brew install herocodess/tap/mothball                      # macOS and Linux
go install github.com/herocodess/mothball/cli/mothball@latest
```

or download the binary for your system from the [latest release](https://github.com/herocodess/mothball/releases/latest).

## Code signing

- **macOS:** signed with an Apple Developer ID (Herodion Momoh, 4N7797Q7D2) and notarised by Apple.
- **Windows:** free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org) (application in progress; until then the installer is unsigned and every file is listed with its SHA-256 checksum in the release).

Code signing policy: release builds are made only by this repository's GitHub Actions workflows from tagged commits on `main`, which is protected and needs passing checks and a maintainer review. Committers, reviewers and release approvers: [Hero Momoh](https://github.com/herocodess).

## Privacy

Mothball runs on your computer and collects nothing. It does not send any information about you, your files or your projects anywhere. The only network request it makes on its own is a daily check of this repository's latest release on GitHub, which you can turn off in Settings. Commands it runs for you (such as `npm install` when you wake a project) talk to their own servers as they normally would.

## Repository layout

| Folder | What lives there |
| --- | --- |
| `core/` | The Go engine: scanning, rule matching, verification, Trash, wake, autopilot |
| `cli/` | The `mothball` command, a thin layer over `core` |
| `rules/` | Rule packs, one JSON file per stack |
| `app/` | The Flutter desktop app for macOS, Windows and Linux (see [app/README.md](app/README.md)) |
| `installer/` | The Windows installer (Inno Setup) and winget manifests |
| `packaging/` | Linux packaging: desktop entry, AppStream metadata, icons, AppRun, deb and rpm |
| `assets/` | Logo, icons and the menu bar glyph |
| `docs/` | Rule pack format and design notes |

Only `core` ever touches files. The CLI, the background service and the desktop app all go through it.

## CLI

Available now: everything below.

```sh
mothball scan                # what is reclaimable, by project
mothball clean --dry-run     # preview exactly what would move to the Trash
mothball clean               # do it
mothball caches              # shared tool caches and their sizes
mothball caches clean --safe # clean every cache that only costs a re-download
mothball wake                # list mothballed projects
mothball wake ~/dev/my-app   # restore one, with its stack's install command
mothball empty               # permanently empty only what Mothball put in the Trash
mothball status              # free space, autopilot, reclaimable space
mothball service install     # run in the background and start at login
```

Keep a project out of it forever by adding a `.mothballignore` file to its root.

## Contributing

New stack? Add a rule pack with its detect file, output folders, verification check and wake command, plus a fixture project that proves it never touches source. See `CONTRIBUTING.md`.

## License

MIT
