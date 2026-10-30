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
