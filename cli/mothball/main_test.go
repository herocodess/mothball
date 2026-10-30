package main

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func fixture(t *testing.T) (root, build string) {
	t.Helper()
	root = t.TempDir()
	app := filepath.Join(root, "app")
	build = filepath.Join(app, "build")
	for _, f := range []string{filepath.Join(app, "pubspec.yaml"), filepath.Join(build, "flutter_assets", "a")} {
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root, build
}

func TestCleanDryRunChangesNothing(t *testing.T) {
	root, build := fixture(t)
	var out, errb bytes.Buffer
	code := run([]string{"clean", "--dry-run", "--idle-days", "1", root}, strings.NewReader(""), &out, &errb)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	// A brand-new project is not idle, so nothing is even listed.
	if _, err := os.Stat(build); err != nil {
		t.Fatal("dry run touched files")
	}
}

func TestCleanAsksAndRespectsNo(t *testing.T) {
	root, build := fixture(t)
	mustOld(t, filepath.Join(root, "app", "pubspec.yaml"))
	var out, errb bytes.Buffer
	code := run([]string{"clean", "--idle-days", "30", root}, strings.NewReader("n\n"), &out, &errb)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if !strings.Contains(out.String(), "Nothing was moved") {
		t.Fatalf("output:\n%s", out.String())
	}
	if _, err := os.Stat(build); err != nil {
		t.Fatal("moved after the user said no")
	}
}

func TestCleanYesMovesToTrash(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("uses the freedesktop Trash in a temp folder")
	}
	root, build := fixture(t)
	mustOld(t, filepath.Join(root, "app", "pubspec.yaml"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	t.Setenv("MOTHBALL_STATE_DIR", filepath.Join(root, "state"))

	var out, errb bytes.Buffer
	code := run([]string{"clean", "--yes", "--idle-days", "30", filepath.Join(root, "app")}, strings.NewReader(""), &out, &errb)
	if code != 0 {
		t.Fatalf("exit %d: %s\n%s", code, errb.String(), out.String())
	}
	if _, err := os.Stat(build); !os.IsNotExist(err) {
		t.Fatalf("build still in place:\n%s", out.String())
	}
	if _, err := os.Stat(filepath.Join(root, "app", "pubspec.yaml")); err != nil {
		t.Fatal("source touched")
	}
	hist, err := os.ReadFile(filepath.Join(root, "state", "history.jsonl"))
	if err != nil || !strings.Contains(string(hist), "flutter pub get") {
		t.Fatalf("history missing: %v %s", err, hist)
	}
}

// mustOld backdates a file so a project without git looks idle.
func mustOld(t *testing.T, path string) {
	t.Helper()
	old := time.Now().AddDate(0, 0, -90)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
}
