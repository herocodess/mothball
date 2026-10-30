package trash

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLinuxTrashWritesRestoreInfo(t *testing.T) {
	root := t.TempDir()
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	src := filepath.Join(root, "my app", "node_modules")
	if err := os.MkdirAll(filepath.Join(src, "react"), 0o755); err != nil {
		t.Fatal(err)
	}

	dest, err := Default().Trash(src)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatal("folder still in place")
	}
	if _, err := os.Stat(filepath.Join(dest, "react")); err != nil {
		t.Fatal("contents not in the Trash:", err)
	}
	info, err := os.ReadFile(filepath.Join(root, "data", "Trash", "info", filepath.Base(dest)+".trashinfo"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(info), "Path="+encodePath(src)) {
		t.Errorf("trashinfo has wrong path:\n%s", info)
	}

	// A second folder with the same label gets its own name.
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	dest2, err := Default().Trash(src)
	if err != nil {
		t.Fatal(err)
	}
	if dest2 == dest {
		t.Fatal("second trash overwrote the first")
	}
}
