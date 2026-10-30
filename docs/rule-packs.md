# Rule packs

Each stack Mothball understands is one JSON file in `rules/`. Packs are data, not code, and are compiled into the binary.

```json
{
  "id": "flutter",
  "name": "Flutter and Dart",
  "detect": ["pubspec.yaml"],
  "outputs": [
    { "path": ".dart_tool", "requireAny": ["package_config.json"] },
    { "path": "build", "requireAny": [".last_build_id", "flutter_assets", "app"] }
  ],
  "wake": [
    { "run": "flutter pub get" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Short unique name, lower case |
| `name` | What people see |
| `detect` | File names that mark a project folder. Plain names only |
| `outputs[].path` | A folder the stack generates, relative to the project folder. Must stay inside it |
| `outputs[].requireAny` | Names, at least one of which must sit directly inside the folder. Required: it is what stops a source folder that happens to be called `build` from matching |
| `outputs[].requireSibling` | Optional names, at least one of which must sit next to the folder |
| `wake` | Restore commands. The first entry whose `when` file exists in the project wins; an entry without `when` is the fallback |

## Checks every output must pass

A folder is only a candidate when all of these hold:

1. Its project folder contains one of the pack's `detect` files.
2. It is a real folder, not a symlink.
3. It contains at least one `requireAny` name.
4. Git tracks nothing inside it.
5. It is not inside a protected location: package caches, toolchains, app data, the Trash.
6. Its project has no `.mothballignore` file.

A project with uncommitted changes is always reported as in use.

`mothball clean` runs every check again on each folder immediately before moving it, with fresh git facts. Anything that changed since the scan means the folder is left alone. Every move is recorded in a history file so the project can be woken later.

## Adding a pack

1. Add `rules/<id>.json`.
2. Add a test in `core/scan/scan_test.go` that builds a fixture project for the stack and checks both that real output is found and that a same-named source folder is not.
3. Run `go test ./...`.
