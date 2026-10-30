package clean

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/scan"
	"github.com/herocodess/mothball/rules"
)

// fakeTrash moves folders into a temp dir instead of the real Trash.
type fakeTrash struct{ dir string }

func (f fakeTrash) Trash(p string) (string, error) {
	dest := filepath.Join(f.dir, filepath.Base(filepath.Dir(p))+"-"+filepath.Base(p))
	return dest, os.Rename(p, dest)
}

type failRecorder struct{}

func (failRecorder) Append(history.Entry) error { return errors.New("disk full") }

func touch(t *testing.T, files ...string) {
	t.Helper()
	for _, f := range files {
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func setup(t *testing.T) (*scan.Scanner, string) {
	t.Helper()
	ps, err := pack.Load(rules.Files)
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	return scan.New(ps, home), home
}

func TestCleanMovesAndRecords(t *testing.T) {
	s, home := setup(t)
	app := filepath.Join(home, "app")
	touch(t, filepath.Join(app, "pubspec.yaml"), filepath.Join(app, "build", "flutter_assets", "a"))

	res := s.Scan(scan.Options{Roots: []string{home}, Home: home})
	plan := Plan(res.Candidates, 0)
	if len(plan) != 1 {
		t.Fatalf("plan = %v", plan)
	}
	log, err := history.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	out := Run(plan, 0, s, fakeTrash{t.TempDir()}, log, time.Now())
	if out[0].Err != nil {
		t.Fatal(out[0].Err)
	}
	if _, err := os.Stat(filepath.Join(app, "build")); !os.IsNotExist(err) {
		t.Fatal("build folder still there")
	}
	if _, err := os.Stat(filepath.Join(app, "pubspec.yaml")); err != nil {
		t.Fatal("source was touched:", err)
	}
	entries, _ := log.All()
	if len(entries) != 1 || entries[0].Wake != "flutter pub get" || entries[0].Original != filepath.Join(app, "build") {
		t.Fatalf("history = %+v", entries)
	}
}

// Something changes between scan and clean: the folder now holds source.
func TestRecheckCatchesChangesSinceScan(t *testing.T) {
	s, home := setup(t)
	app := filepath.Join(home, "app")
	marker := filepath.Join(app, "build", "flutter_assets")
	touch(t, filepath.Join(app, "pubspec.yaml"), filepath.Join(marker, "a"))
	plan := Plan(s.Scan(scan.Options{Roots: []string{home}, Home: home}).Candidates, 0)

	if err := os.RemoveAll(marker); err != nil {
		t.Fatal(err)
	}
	touch(t, filepath.Join(app, "build", "keep_me.dart"))

	log, _ := history.Open(t.TempDir())
	out := Run(plan, 0, s, fakeTrash{t.TempDir()}, log, time.Now())
	var skip *SkipError
	if !errors.As(out[0].Err, &skip) {
		t.Fatalf("want skip, got %v", out[0].Err)
	}
	if _, err := os.Stat(filepath.Join(app, "build", "keep_me.dart")); err != nil {
		t.Fatal("folder was moved despite failing the re-check")
	}
}

func TestRecheckCatchesNewWork(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	s, home := setup(t)
	app := filepath.Join(home, "app")
	touch(t, filepath.Join(app, "package.json"), filepath.Join(app, "node_modules", ".package-lock.json"))
	if err := os.WriteFile(filepath.Join(app, ".gitignore"), []byte("node_modules/\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitRun := func(env []string, args ...string) {
		cmd := exec.Command("git", append([]string{"-C", app}, args...)...)
		cmd.Env = append(append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t"), env...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	old := time.Now().AddDate(0, 0, -90).Format(time.RFC3339)
	gitRun(nil, "init", "-q")
	gitRun(nil, "add", "-A")
	gitRun([]string{"GIT_AUTHOR_DATE=" + old, "GIT_COMMITTER_DATE=" + old}, "commit", "-qm", "old")

	plan := Plan(s.Scan(scan.Options{Roots: []string{home}, Home: home}).Candidates, 60)
	if len(plan) != 1 {
		t.Fatalf("plan = %v", plan)
	}
	// The user starts working again before the clean runs.
	if err := os.WriteFile(filepath.Join(app, "package.json"), []byte(`{"name":"back"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	log, _ := history.Open(t.TempDir())
	out := Run(plan, 60, s, fakeTrash{t.TempDir()}, log, time.Now())
	if out[0].Err == nil {
		t.Fatal("moved output of a project with uncommitted work")
	}
}

func TestStopsWhenHistoryCannotBeSaved(t *testing.T) {
	s, home := setup(t)
	for _, name := range []string{"a", "b"} {
		app := filepath.Join(home, name)
		touch(t, filepath.Join(app, "pubspec.yaml"), filepath.Join(app, "build", "flutter_assets", "x"))
	}
	plan := Plan(s.Scan(scan.Options{Roots: []string{home}, Home: home}).Candidates, 0)
	out := Run(plan, 0, s, fakeTrash{t.TempDir()}, failRecorder{}, time.Now())
	var he *HistoryError
	if !errors.As(out[0].Err, &he) {
		t.Fatalf("want history error first, got %v", out[0].Err)
	}
	var skip *SkipError
	if !errors.As(out[1].Err, &skip) {
		t.Fatalf("want the rest stopped, got %v", out[1].Err)
	}
	moved := 0
	for _, name := range []string{"a", "b"} {
		if _, err := os.Stat(filepath.Join(home, name, "build")); os.IsNotExist(err) {
			moved++
		}
	}
	if moved != 1 {
		t.Fatalf("want exactly one moved before stopping, got %d", moved)
	}
}
