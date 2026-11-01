# Roadmap

Where Mothball is going, roughly in order. Versions and timing are a guide,
not a promise. If something here matters to you, say so on the issue, or pick
it up: items marked **(good first issue)** are small and well contained.

## The goal

The disk cleaner developers trust enough to leave running.

Most cleaners compete on how much they delete. Mothball competes on knowing
what is safe: it understands each stack, only takes what can be rebuilt, and
can always put things back. Every feature below has to keep that true.

### Always

- Only touch things that can be rebuilt or downloaded again.
- Prove it from the project's own files, never from a folder name alone.
- Leave anything git tracks, and any project with uncommitted work, alone.
- Move to the Trash and log it, so every action can be undone.
- Work offline. Send nothing about the user anywhere.

### Never

- Delete personal files: photos, documents, downloads, mail.
- Telemetry, ads, accounts or upsells.
- "Speed up your computer" claims, scare numbers or fake urgency.
- Root or admin access for normal use.

## Now: 0.2, trust and polish

- **Windows trust.** Get the winget package approved; lead the Windows
  download with winget and Scoop (no SmartScreen warning); code-sign the
  installer once SignPath or a certificate is in place.
- **Undo from the app.** A "Put back" button on each history entry that
  restores the folders from the Trash, and a `mothball restore` command.
- **Where your space went.** A breakdown by stack and by project, with the
  biggest single folders, so people see why before they clean.
- **More tool caches:** Maven (`~/.m2`), NuGet, Composer, JetBrains IDE
  caches, Xcode Archives, old Android SDK build tools and platforms, ccache
  and sccache, Bazel. **(good first issue, one each)**
- **Find projects without setup.** Suggest common roots on first run
  (`~/dev`, `~/Projects`, `~/code`, `~/StudioProjects`, `~/source/repos`)
  instead of asking people to type paths.

## Next: 0.3, simulators, emulators and containers

The biggest space hogs on a developer's machine often aren't in any project.

- **iOS simulator runtimes.** List installed runtimes and offer to remove
  ones no installed Xcode uses (`xcrun simctl runtime`).
- **Android emulators and system images.** Show each virtual device's size
  and when it was last started, and offer to remove system images no
  virtual device uses.
- **Test phones.** For a plugged-in Android phone, list debug builds of your
  own apps that are still installed, and offer to uninstall them.
- **Docker, carefully.** Report build cache, dangling images and stopped
  containers, and clean only with a clear prompt. Never touch volumes.

## Next: 0.4, smarter wake

- **Wake before you need it.** Notice when a mothballed project is opened in
  VS Code, Cursor, Xcode, Android Studio or a JetBrains IDE, and start the
  restore step in the background.
- **Wake progress in the app,** with the real command output and a clear
  error if a restore fails.
- **Monorepos.** Understand workspaces (npm, pnpm, Yarn, Nx, Turborepo,
  Cargo, Go) so one wake restores the whole repo correctly.
- **Pin a project.** Mark a project "never put away" from the app.

## Next: 0.5, see the difference

- **Lifetime savings.** Total space given back, and a small chart over time.
- **Weekly summary** notification, off by default: "Mothball kept 12 GB
  free this week."
- **Tray at a glance.** Free space and what can be freed, in the menu bar or
  system tray without opening the app.

## Later: 1.0 and beyond

- **Deep archive.** For projects untouched for a year or more, compress the
  whole project into one archive, with an exact restore. Opt in, per project.
- **External and network drives.** Projects on external disks, with care for
  drives that aren't always connected.
- **Build servers and CI runners.** A headless mode for self-hosted runners
  and build machines, where disks fill up fastest.
- **Community rule packs.** A pack checker (`mothball pack test`) and a
  test kit of trap fixtures, so a new stack can be added safely in one PR.
- **More places to install:** Flathub, a Homebrew core formula, the
  Microsoft Store, apt and dnf repositories.
- **Languages.** Translate the app, starting with the most requested.

## Always ongoing

- New stacks and caches, each with fixtures that prove what must not be
  touched.
- Safety tests: every rule pack runs against projects designed to trick it.
- Accessibility: keyboard use, screen readers and reduced motion.
- Speed: scanning large disks quickly without heavy CPU use.

## Suggesting something

Open an issue saying what takes space on your machine, roughly how much, and
how it can be rebuilt. That is everything needed to judge whether it fits.
For a new stack, see [docs/rule-packs.md](docs/rule-packs.md).
