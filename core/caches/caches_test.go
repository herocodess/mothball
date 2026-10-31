package caches

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/history"
)

type fakeTrash struct{ dir string }

func (f fakeTrash) Trash(p string) (string, error) {
	dest := filepath.Join(f.dir, filepath.Base(filepath.Dir(p))+"-"+filepath.Base(p))
	return dest, os.Rename(p, dest)
}

func file(t *testing.T, p string, size int, mod time.Time) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
	if !mod.IsZero() {
		_ = os.Chtimes(filepath.Dir(p), mod, mod)
	}
}

type kitT struct {
	*Kit
	ran     [][]string
	running map[string]bool
	tools   map[string]bool
}

func newKit(t *testing.T, goos string) *kitT {
	t.Helper()
	home := t.TempDir()
	log, _ := history.Open(t.TempDir())
	k := &kitT{running: map[string]bool{}, tools: map[string]bool{}}
	k.Kit = &Kit{
		Home: home, GOOS: goos, Getenv: func(string) string { return "" },
		LookTool: func(n string) (string, error) {
			if k.tools[n] {
				return "/bin/" + n, nil
			}
			return "", exec.ErrNotFound
		},
		Running: func(names []string) string {
			for _, n := range names {
				if k.running[n] {
					return n
				}
			}
			return ""
		},
		Run: func(_ context.Context, bin string, args []string) error {
			k.ran = append(k.ran, append([]string{filepath.Base(bin)}, args...))
			return nil
		},
		Trash: fakeTrash{t.TempDir()},
		Log:   log,
		Now:   time.Now,
	}
	return k
}

func find(cs []Cache, id string) (Cache, bool) {
	for _, c := range cs {
		if c.ID == id {
			return c, true
		}
	}
	return Cache{}, false
}

func TestSurveyFindsAndSizes(t *testing.T) {
	k := newKit(t, "darwin")
	file(t, filepath.Join(k.Home, "Library/Developer/Xcode/DerivedData/App-abc/Build/x"), 5000, time.Time{})
	file(t, filepath.Join(k.Home, ".npm/_cacache/content/y"), 3000, time.Time{})
	k.tools["npm"] = true

	cs := k.Survey()
	if len(cs) < 2 || cs[0].ID != "xcode-derived-data" {
		t.Fatalf("want DerivedData first (largest), got %+v", cs)
	}
	if c, _ := find(cs, "npm"); c.Bytes != 3000 || c.Blocked != "" {
		t.Errorf("npm = %+v", c)
	}
	if _, ok := find(cs, "yarn"); ok {
		t.Error("absent cache listed")
	}
}

func TestOtherOSCachesAreSkipped(t *testing.T) {
	k := newKit(t, "linux")
	file(t, filepath.Join(k.Home, "Library/Developer/Xcode/DerivedData/a/x"), 10, time.Time{})
	if _, ok := find(k.Survey(), "xcode-derived-data"); ok {
		t.Fatal("Xcode cache listed on Linux")
	}
}

func TestCommandCachesUseTheTool(t *testing.T) {
	k := newKit(t, "darwin")
	file(t, filepath.Join(k.Home, ".npm/_cacache/content/y"), 3000, time.Time{})
	k.tools["npm"] = true
	c, _ := find(k.Survey(), "npm")
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	if len(k.ran) != 1 || k.ran[0][0] != "npm" || k.ran[0][1] != "cache" {
		t.Fatalf("ran %v", k.ran)
	}
	if _, err := os.Stat(filepath.Join(k.Home, ".npm/_cacache/content/y")); err != nil {
		t.Fatal("a command cache was deleted by Mothball instead of by the tool")
	}
}

func TestMissingToolBlocks(t *testing.T) {
	k := newKit(t, "darwin")
	file(t, filepath.Join(k.Home, ".npm/_cacache/content/y"), 3000, time.Time{})
	c, _ := find(k.Survey(), "npm")
	if c.Blocked == "" {
		t.Fatal("missing tool not reported")
	}
	if _, err := k.Clean(c); err == nil {
		t.Fatal("cleaned without the tool")
	}
}

func TestTrashCachesEmptyTheFolderAndRecord(t *testing.T) {
	k := newKit(t, "darwin")
	dd := filepath.Join(k.Home, "Library/Developer/Xcode/DerivedData")
	file(t, filepath.Join(dd, "App-abc/Build/x"), 5000, time.Time{})
	file(t, filepath.Join(dd, "Other-def/Build/x"), 1000, time.Time{})
	c, _ := find(k.Survey(), "xcode-derived-data")
	moved, err := k.Clean(c)
	if err != nil || moved != 6000 {
		t.Fatalf("moved %d, %v", moved, err)
	}
	if entries, _ := os.ReadDir(dd); len(entries) != 0 {
		t.Fatal("folder not emptied")
	}
	if _, err := os.Stat(dd); err != nil {
		t.Fatal("the DerivedData folder itself should stay")
	}
	all, _ := k.Log.(*history.Log).All()
	if len(all) != 2 || all[0].Pack != "cache:xcode-derived-data" {
		t.Fatalf("history = %+v", all)
	}
}

func TestRunningAppBlocks(t *testing.T) {
	k := newKit(t, "darwin")
	dd := filepath.Join(k.Home, "Library/Developer/Xcode/DerivedData")
	file(t, filepath.Join(dd, "App/x"), 10, time.Time{})
	k.running["Xcode"] = true
	c, _ := find(k.Survey(), "xcode-derived-data")
	if c.Blocked != "Xcode is running" {
		t.Errorf("blocked = %q", c.Blocked)
	}
	if _, err := k.Clean(c); err == nil {
		t.Fatal("cleaned while Xcode was running")
	}
	if _, err := os.Stat(filepath.Join(dd, "App/x")); err != nil {
		t.Fatal("touched DerivedData while Xcode was running")
	}
}

func TestDeviceSupportKeepsNewest(t *testing.T) {
	k := newKit(t, "darwin")
	ds := filepath.Join(k.Home, "Library/Developer/Xcode/iOS DeviceSupport")
	file(t, filepath.Join(ds, "iPhone 26.2/x"), 100, time.Now().AddDate(0, -2, 0))
	file(t, filepath.Join(ds, "iPhone 26.6/x"), 100, time.Now())
	c, _ := find(k.Survey(), "xcode-device-support")
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(ds, "iPhone 26.6")); err != nil {
		t.Fatal("newest version removed")
	}
	if _, err := os.Stat(filepath.Join(ds, "iPhone 26.2")); !os.IsNotExist(err) {
		t.Fatal("older version kept")
	}
}

func TestReportOnlyNeverCleaned(t *testing.T) {
	k := newKit(t, "darwin")
	file(t, filepath.Join(k.Home, ".android/avd/Pixel.avd/x"), 100, time.Time{})
	c, ok := find(k.Survey(), "android-emulators")
	if !ok || c.Policy != Report {
		t.Fatalf("got %+v", c)
	}
	if _, err := k.Clean(c); !errors.Is(err, ErrReportOnly) {
		t.Fatalf("err = %v", err)
	}
}

func TestSafeTarget(t *testing.T) {
	home := "/Users/h"
	roots := []string{"/Users/h/Library/Caches/Yarn"}
	if safeTarget(home, "/Users/h", roots) || safeTarget(home, "/Users/h/Documents", roots) || safeTarget(home, "/", roots) {
		t.Fatal("unsafe target allowed")
	}
	if !safeTarget(home, "/Users/h/Library/Caches/Yarn/v6", roots) {
		t.Fatal("safe target refused")
	}
}
