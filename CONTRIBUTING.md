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
