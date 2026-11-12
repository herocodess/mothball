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
	if c.Blocked == "" || c.MissingTool != "npm" {
		t.Fatalf("missing tool not reported: blocked %q, missing %q", c.Blocked, c.MissingTool)
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
	if c.Blocked != "Xcode is running" || c.BlockedBy != "Xcode" || c.MissingTool != "" {
		t.Errorf("blocked = %q, by %q, missing %q", c.Blocked, c.BlockedBy, c.MissingTool)
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

// mustExist fails when a file that must survive cleaning is gone.
func mustExist(t *testing.T, p string) {
	t.Helper()
	if _, err := os.Stat(p); err != nil {
		t.Fatalf("%s should not have been touched: %v", p, err)
	}
}

func TestChromeCleansOnlyCachesInEveryProfile(t *testing.T) {
	k := newKit(t, "darwin")
	base := filepath.Join(k.Home, "Library/Caches/Google/Chrome")
	file(t, filepath.Join(base, "Default/Cache/Cache_Data/a"), 3000, time.Time{})
	file(t, filepath.Join(base, "Default/Code Cache/js/b"), 2000, time.Time{})
	file(t, filepath.Join(base, "Profile 12/Cache/c"), 1000, time.Time{})
	keep := filepath.Join(base, "Default/Storage/ext/d") // not a cache we name
	file(t, keep, 500, time.Time{})

	c, ok := find(k.Survey(), "chrome")
	if !ok || c.Bytes != 6000 {
		t.Fatalf("chrome = %+v, found %v", c, ok)
	}
	if moved, err := k.Clean(c); err != nil || moved != 6000 {
		t.Fatalf("moved %d, %v", moved, err)
	}
	mustExist(t, keep)
	mustExist(t, filepath.Join(base, "Default/Cache")) // the folder stays, emptied
}

func TestChromeOnWindowsLeavesTheProfileAlone(t *testing.T) {
	k := newKit(t, "windows")
	profile := filepath.Join(k.Home, "AppData/Local/Google/Chrome/User Data/Default")
	file(t, filepath.Join(profile, "Cache/Cache_Data/a"), 4000, time.Time{})
	for _, f := range []string{"Bookmarks", "Login Data", "History", "Preferences"} {
		file(t, filepath.Join(profile, f), 100, time.Time{})
	}
	c, ok := find(k.Survey(), "chrome")
	if !ok || c.Bytes != 4000 {
		t.Fatalf("chrome = %+v, found %v", c, ok)
	}
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"Bookmarks", "Login Data", "History", "Preferences"} {
		mustExist(t, filepath.Join(profile, f))
	}
}

func TestBrowserBlocksWhileOpen(t *testing.T) {
	k := newKit(t, "darwin")
	file(t, filepath.Join(k.Home, "Library/Caches/Google/Chrome/Default/Cache/a"), 10, time.Time{})
	k.running["Google Chrome"] = true
	c, _ := find(k.Survey(), "chrome")
	if c.Blocked != "Google Chrome is running" {
		t.Fatalf("blocked = %q", c.Blocked)
	}
	if _, err := k.Clean(c); err == nil {
		t.Fatal("cleaned while Chrome was open")
	}
}

func TestTeamsKeepsChatsAndSignIn(t *testing.T) {
	k := newKit(t, "darwin")
	lib := filepath.Join(k.Home, "Library/Containers/com.microsoft.teams2/Data/Library")
	web := filepath.Join(lib, "Application Support/Microsoft/MSTeams/EBWebView/WV2Profile_tfw")
	file(t, filepath.Join(web, "Service Worker/CacheStorage/x/a"), 5000, time.Time{})
	file(t, filepath.Join(web, "GPUCache/b"), 100, time.Time{})
	file(t, filepath.Join(lib, "Caches/c"), 200, time.Time{})
	keep := []string{
		filepath.Join(web, "IndexedDB/chats"),
		filepath.Join(web, "Local Storage/leveldb/token"),
		filepath.Join(web, "Service Worker/Database/registrations"),
	}
	for _, p := range keep {
		file(t, p, 50, time.Time{})
	}
	c, ok := find(k.Survey(), "teams")
	if !ok || c.Bytes != 5300 {
		t.Fatalf("teams = %+v, found %v", c, ok)
	}
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	for _, p := range keep {
		mustExist(t, p)
	}
}

func TestFirefoxOnLinux(t *testing.T) {
	k := newKit(t, "linux")
	base := filepath.Join(k.Home, ".cache/mozilla/firefox/abc.default-release")
	file(t, filepath.Join(base, "cache2/entries/a"), 700, time.Time{})
	keep := filepath.Join(base, "startupCache/s")
	file(t, keep, 10, time.Time{})
	c, ok := find(k.Survey(), "firefox")
	if !ok || c.Bytes != 700 {
		t.Fatalf("firefox = %+v, found %v", c, ok)
	}
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	mustExist(t, keep)
}

func TestVSCodeExtensionDownloadsButNotSettings(t *testing.T) {
	k := newKit(t, "darwin")
	code := filepath.Join(k.Home, "Library/Application Support/Code")
	file(t, filepath.Join(code, "CachedExtensionVSIXs/ms-python.python-1.0"), 9000, time.Time{})
	file(t, filepath.Join(code, "Cache/a"), 100, time.Time{})
	keep := filepath.Join(code, "User/settings.json")
	file(t, keep, 10, time.Time{})
	c, ok := find(k.Survey(), "vscode")
	if !ok || c.Bytes != 9100 {
		t.Fatalf("vscode = %+v, found %v", c, ok)
	}
	if _, err := k.Clean(c); err != nil {
		t.Fatal(err)
	}
	mustExist(t, keep)
}

func TestEverydayCachesAreSafeToAutoClean(t *testing.T) {
	for _, id := range []string{"chrome", "edge", "brave", "firefox", "teams", "discord", "notion", "figma", "obsidian", "claude"} {
		var d *def
		for _, x := range defs {
			if x.id == id {
				d = x
			}
		}
		if d == nil {
			t.Fatalf("%s missing", id)
		}
		if !d.emptyOnly || len(d.running) == 0 || d.cmd != nil {
			t.Errorf("%s: must empty folders only, and only while the app is closed", id)
		}
	}
}
