package wake

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/rules"
)

func setup(t *testing.T) (*pack.Set, *history.Log, string) {
	t.Helper()
	ps, err := pack.Load(rules.Files)
	if err != nil {
		t.Fatal(err)
	}
	log, err := history.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	app := filepath.Join(t.TempDir(), "app")
	if err := os.MkdirAll(app, 0o755); err != nil {
		t.Fatal(err)
	}
	return ps, log, app
}

func write(t *testing.T, p string, mod time.Time) {
	t.Helper()
	if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(p, mod, mod); err != nil {
		t.Fatal(err)
	}
}

func TestMothballedAndReturned(t *testing.T) {
	ps, log, app := setup(t)
	put := time.Now().Add(-48 * time.Hour)
	write(t, filepath.Join(app, "package.json"), put.Add(-24*time.Hour))
	write(t, filepath.Join(app, "yarn.lock"), put.Add(-24*time.Hour))
	_ = log.Append(history.Entry{Event: history.Trashed, Time: put, Original: filepath.Join(app, "node_modules"), Project: app, Pack: "javascript", Bytes: 100})

	all, _ := log.All()
	got := Mothballed(all, ps)
	if len(got) != 1 {
		t.Fatalf("got %+v", got)
	}
	p := got[0]
	if p.Returned {
		t.Error("project marked returned with no new work")
	}
	if len(p.Commands) != 1 || p.Commands[0] != "yarn install" {
		t.Errorf("commands = %v, want yarn install from the lockfile", p.Commands)
	}

	// Coming back: editing a project file counts as a return.
	write(t, filepath.Join(app, "package.json"), time.Now())
	if !Mothballed(all, ps)[0].Returned {
		t.Error("return not noticed")
	}
}

func TestOutputBackOrWokenIsNotListed(t *testing.T) {
	ps, log, app := setup(t)
	put := time.Now().Add(-time.Hour)
	nm := filepath.Join(app, "node_modules")
	write(t, filepath.Join(app, "package.json"), put)
	_ = log.Append(history.Entry{Event: history.Trashed, Time: put, Original: nm, Project: app, Pack: "javascript"})

	if err := os.MkdirAll(nm, 0o755); err != nil {
		t.Fatal(err)
	}
	all, _ := log.All()
	if got := Mothballed(all, ps); len(got) != 0 {
		t.Fatalf("rebuilt output still listed: %+v", got)
	}

	os.RemoveAll(nm)
	_ = log.Append(history.Entry{Event: history.Woke, Time: time.Now(), Project: app})
	all, _ = log.All()
	if got := Mothballed(all, ps); len(got) != 0 {
		t.Fatalf("woken project still listed: %+v", got)
	}
}

// Commands come from the rule packs, not from whatever the history file says.
func TestCommandsIgnoreHistoryText(t *testing.T) {
	ps, log, app := setup(t)
	write(t, filepath.Join(app, "pubspec.yaml"), time.Now().Add(-time.Hour))
	_ = log.Append(history.Entry{Event: history.Trashed, Time: time.Now(), Original: filepath.Join(app, "build"),
		Project: app, Pack: "flutter", Wake: "rm -rf ~"})
	all, _ := log.All()
	got := Mothballed(all, ps)
	if len(got) != 1 || len(got[0].Commands) != 1 || got[0].Commands[0] != "flutter pub get" {
		t.Fatalf("got %+v", got)
	}
}

func TestRunRecordsWake(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("uses a shell command")
	}
	_, log, app := setup(t)
	p := Project{Path: app, Commands: []string{"touch woke.txt"}}
	var out bytes.Buffer
	if err := Run(p, log, &out, &out); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(app, "woke.txt")); err != nil {
		t.Fatal("command did not run in the project folder")
	}
	all, _ := log.All()
	if len(all) < 1 || all[0].Kind() != history.Woke {
		t.Fatalf("history = %+v", all)
	}

	noop := Project{Path: app}
	if err := Run(noop, log, &out, &out); err != nil {
		t.Fatal("a stack that rebuilds on its own should wake without commands:", err)
	}

	failing := Project{Path: app, Commands: []string{"exit 3"}}
	if err := Run(failing, log, &out, &out); err == nil {
		t.Fatal("failure not reported")
	}
}
