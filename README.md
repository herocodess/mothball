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

## What it covers

Each stack is a small rule pack, so adding a new one is a single pull request. 23 packs ship today, and every one is tested automatically against a same-named source folder.

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
| Global caches | Xcode, simulators, npm, pnpm, yarn, bun, pip, uv, Gradle, CocoaPods, Homebrew, Go, Electron app caches |

Docker, Android emulators and local AI models are reported, never removed without asking.

## Install

> Mothball is in early development. Nothing is released yet.

Planned: a Homebrew cask and formula on macOS, Scoop and winget on Windows, and packages for Linux. Until then, build the CLI from source:

```sh
go install github.com/herocodess/mothball/cli/mothball@latest
```

## Repository layout

| Folder | What lives there |
| --- | --- |
| `core/` | The Go engine: scanning, rule matching, verification, Trash, wake, autopilot |
| `cli/` | The `mothball` command, a thin layer over `core` |
| `rules/` | Rule packs, one YAML file per stack |
| `app/` | The Flutter desktop app for macOS, Windows and Linux |
| `assets/` | Logo, icons and the menu bar glyph |
| `docs/` | Rule pack format and design notes |

Only `core` ever touches files. The CLI, the background service and the desktop app all go through it.

## CLI

Available now: `scan`, `clean`, `wake` and `empty`.

```sh
mothball scan                # what is reclaimable, by project
mothball clean --dry-run     # preview exactly what would move to the Trash
mothball clean               # do it
mothball wake                # list mothballed projects
mothball wake ~/dev/my-app   # restore one, with its stack's install command
mothball empty               # permanently empty only what Mothball put in the Trash
```

Keep a project out of it forever by adding a `.mothballignore` file to its root.

## Contributing

New stack? Add a rule pack with its detect file, output folders, verification check and wake command, plus a fixture project that proves it never touches source. See `CONTRIBUTING.md`.

## License

MIT
