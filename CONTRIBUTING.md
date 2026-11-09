# Contributing

Thanks for helping. The most useful contribution is a rule pack for a stack you use: see [docs/rule-packs.md](docs/rule-packs.md).

## Ground rules

- Safety beats coverage. A pack that misses some output is fine; a pack that could match source is not.
- Every pack ships with a test that proves a same-named source folder is left alone.
- The core has no third-party dependencies. Please keep it that way.

## Working on the code

```sh
go test ./...
go run ./cli/mothball scan ~/dev
```

CI runs the tests on macOS, Windows and Linux.

The end to end tests run the real binary against fake projects and move folders to the Trash. CI runs them on Windows, Linux and macOS, on x64 and Arm:

```sh
go test -tags e2e ./e2e
```

## Pull requests

`main` is protected. Every change, including the maintainer's, goes through a pull request that:

- passes every check on all systems (unit tests, end to end tests, desktop app builds)
- is reviewed and approved by the maintainer
- is up to date with `main` before it merges

Fork the repo, push a branch to your fork, and open a pull request. For a first-time contributor, CI waits until the maintainer starts it, so nobody's code runs on the project's machines unseen.

## Translations

Mothball's app speaks English, Arabic, Chinese (Simplified), French, Japanese, Portuguese (Brazil) and Spanish. The translations are new, so if you speak one of them, your eye is the most useful thing you can give.

Each language is one file in [`app/lib/l10n`](app/lib/l10n): `app_fr.arb` for French, `app_ar.arb` for Arabic, and so on. English, `app_en.arb`, is the source; its `@` entries say where each piece of text appears and what it means.

To fix a translation, change the text in that language's file and open a pull request. Keep these intact:

- Words in braces, like `{size}` or `{toTrash}`. The app fills them in.
- Plural forms, like `{count, plural, =1{...} other{...}}`. Change the words inside, keep the shape.
- Product names: Mothball, GitHub, git, macOS, Windows.

Some terms are Mothball's own, and their meaning matters more than a word-for-word match:

| English | Means |
|---|---|
| Put away | Move a project's build output (node_modules, build, Pods) to the Trash. Not "save" and not "delete". |
| Wake | Bring a put-away project back by running its install command. |
| Mothballed | Projects whose output has been put away and are resting. |
| Autopilot | Puts idle projects away by itself when free space runs low. |

Not comfortable with a pull request? [Open a translation issue](https://github.com/herocodess/mothball/issues/new?template=translation.yml) instead, or use **Settings → Language → Help improve this translation** in the app.

To see your change, run the app in that language from **Settings → Language**, or render every screen in every language (on macOS):

```sh
cd app
flutter test --run-skipped --update-goldens --tags screenshots --plain-name languages test/screenshots_test.dart
```

The images land in `app/test/screenshots/languages/`.

**A new language:** copy `app_en.arb` to `app_xx.arb` (the two-letter code), translate the text, set `"@@locale": "xx"`, delete the `@` entries, and add the language to the list in `app/lib/language.dart`. Right-to-left languages already work; Arabic is the example.
