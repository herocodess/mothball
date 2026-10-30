package trash

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDarwinTrashMovesIntoBatchFolder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	src := filepath.Join(home, "dev", "app", "node_modules")
	if err := os.MkdirAll(filepath.Join(src, "react"), 0o755); err != nil {
		t.Fatal(err)
	}
	dest, err := Default().Trash(src)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(dest, filepath.Join(home, ".Trash", "Mothball ")) {
		t.Errorf("unexpected destination %s", dest)
	}
	if filepath.Base(dest) != "app node_modules" {
		t.Errorf("unexpected label %s", filepath.Base(dest))
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatal("folder still in place")
	}
}

func TestRemoveOnlyOwnFolders(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	src := filepath.Join(home, "dev", "app", "build")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	dest, err := Default().Trash(src)
	if err != nil {
		t.Fatal(err)
	}
	if Remove(dest, filepath.Join(home, "dev", "web", "node_modules")) == nil {
		t.Fatal("removed with the wrong original path")
	}
	if Remove(filepath.Join(home, "dev"), src) == nil {
		t.Fatal("removed something outside the Trash")
	}
	if err := Remove(dest, src); err != nil {
		t.Fatal(err)
	}
}
