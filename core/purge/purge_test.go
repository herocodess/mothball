package purge

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/trash"
)

func TestPurgeAfterGraceOnly(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("uses the freedesktop Trash in a temp folder")
	}
	root := t.TempDir()
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	log, _ := history.Open(t.TempDir())

	mk := func(name string, age time.Duration) history.Entry {
		src := filepath.Join(root, name, "build")
		if err := os.MkdirAll(src, 0o755); err != nil {
			t.Fatal(err)
		}
		dest, err := trash.Default().Trash(src)
		if err != nil {
			t.Fatal(err)
		}
		e := history.Entry{Event: history.Trashed, Time: time.Now().Add(-age), Original: src, Trashed: dest, Bytes: 10}
		_ = log.Append(e)
		return e
	}
	old := mk("old", 10*24*time.Hour)
	fresh := mk("fresh", time.Hour)

	all, _ := log.All()
	if WaitingBytes(all) != 20 {
		t.Fatalf("waiting = %d", WaitingBytes(all))
	}
	if len(Due(all, 0, time.Now())) != 0 {
		t.Fatal("auto-empty off must mean nothing is due")
	}
	due := Due(all, 7, time.Now())
	if len(due) != 1 || due[0].Original != old.Original {
		t.Fatalf("due = %+v", due)
	}
	freed, errs := Run(due, log, time.Now())
	if freed != 10 || len(errs) != 0 {
		t.Fatalf("freed %d, errs %v", freed, errs)
	}
	if _, err := os.Stat(old.Trashed); !os.IsNotExist(err) {
		t.Fatal("old folder still in the Trash")
	}
	if _, err := os.Stat(fresh.Trashed); err != nil {
		t.Fatal("fresh folder removed before its grace period")
	}
	all, _ = log.All()
	if WaitingBytes(all) != 10 {
		t.Fatalf("after purge waiting = %d", WaitingBytes(all))
	}
}

// A history line pointing at something else in the Trash must not delete it.
func TestTamperedHistoryCannotDeleteOtherThings(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("uses the freedesktop Trash in a temp folder")
	}
	root := t.TempDir()
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	precious := filepath.Join(root, "photos")
	if err := os.MkdirAll(precious, 0o755); err != nil {
		t.Fatal(err)
	}
	log, _ := history.Open(t.TempDir())
	e := history.Entry{Event: history.Trashed, Time: time.Now().AddDate(0, -1, 0),
		Original: filepath.Join(root, "app", "build"), Trashed: precious}
	_, errs := Run([]history.Entry{e}, log, time.Now())
	if len(errs) != 1 {
		t.Fatal("expected a refusal")
	}
	if _, err := os.Stat(precious); err != nil {
		t.Fatal("deleted something Mothball did not trash")
	}
}
