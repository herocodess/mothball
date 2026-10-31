// Package caches handles shared developer caches that live outside projects:
// package manager downloads, Xcode build data, simulators and the like.
//
// Each cache is cleaned the safest way available: through the tool's own
// command when it has one, otherwise by moving the folder to the Trash with a
// history record. Some are only reported, because they can hold things you
// still use (Docker images, emulators).
package caches

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"github.com/herocodess/mothball/core/proc"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/trash"
)

// Policy says how freely a cache may be cleaned.
type Policy string

const (
	// Auto caches only cost a re-download or rebuild. Autopilot may clean them.
	Auto Policy = "auto"
	// Ask caches are safe but slow or costly to get back. Only on request.
	Ask Policy = "ask"
	// Report caches are shown with their size and never cleaned by Mothball.
	Report Policy = "report"
)

// Cache is one shared cache found on this machine.
type Cache struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Policy Policy `json:"policy"`
	Bytes  int64  `json:"bytes"`
	// How describes what cleaning does, in plain words.
	How string `json:"how"`
	// Blocked says why it cannot be cleaned right now (an app is running, the
	// tool is missing). Empty when it can.
	Blocked string `json:"blocked,omitempty"`

	def *def
}

// def describes how to find, size and clean one cache.
type def struct {
	id, name string
	policy   Policy
	how      string
	// paths are measured for size (and moved to the Trash when there is no command).
	paths func(env) []string
	// cmd, when set, cleans through the tool itself: tool name and arguments.
	cmd []string
	// running lists process names that must not be running while cleaning.
	running []string
	// keepNewest keeps the most recently used entry inside each path and
	// trashes the rest (used for Xcode device support).
	keepNewest bool
	// emptyOnly trashes the folder's contents, not the folder itself.
	emptyOnly bool
	only      string // GOOS this cache exists on, or "" for all
}

type env struct {
	home, goos string
	getenv     func(string) string
}

func (e env) j(parts ...string) string { return filepath.Join(append([]string{e.home}, parts...)...) }

func (e env) local(parts ...string) string { // %LOCALAPPDATA% on Windows
	base := e.getenv("LOCALAPPDATA")
	if base == "" {
		base = e.j("AppData", "Local")
	}
	return filepath.Join(append([]string{base}, parts...)...)
}

func (e env) xdgCache(parts ...string) string {
	base := e.getenv("XDG_CACHE_HOME")
	if base == "" {
		base = e.j(".cache")
	}
	return filepath.Join(append([]string{base}, parts...)...)
}

func (e env) appSupport(parts ...string) string { // per-OS app data folder
	switch e.goos {
	case "darwin":
		return e.j(append([]string{"Library", "Application Support"}, parts...)...)
	case "windows":
		base := e.getenv("APPDATA")
		if base == "" {
			base = e.j("AppData", "Roaming")
		}
		return filepath.Join(append([]string{base}, parts...)...)
	default:
		base := e.getenv("XDG_CONFIG_HOME")
		if base == "" {
			base = e.j(".config")
		}
		return filepath.Join(append([]string{base}, parts...)...)
	}
}

func byOS(e env, mac, linux, windows string) []string {
	switch e.goos {
	case "darwin":
		return []string{mac}
	case "windows":
		return []string{windows}
	default:
		return []string{linux}
	}
}

var defs = []*def{
	{
		id: "xcode-derived-data", name: "Xcode DerivedData", policy: Auto, only: "darwin",
		how:     "Moves Xcode's build data to the Trash. Xcode rebuilds it on the next build.",
		paths:   func(e env) []string { return []string{e.j("Library", "Developer", "Xcode", "DerivedData")} },
		running: []string{"Xcode"}, emptyOnly: true,
	},
	{
		id: "simulator-caches", name: "Simulator caches", policy: Auto, only: "darwin",
		how:     "Moves simulator caches to the Trash. They are rebuilt when a simulator boots.",
		paths:   func(e env) []string { return []string{e.j("Library", "Developer", "CoreSimulator", "Caches")} },
		running: []string{"Simulator"}, emptyOnly: true,
	},
	{
		id: "simulators-unavailable", name: "Simulators for removed iOS versions", policy: Auto, only: "darwin",
		how: "Runs xcrun simctl delete unavailable, which removes simulators whose iOS version is gone.",
		cmd: []string{"xcrun", "simctl", "delete", "unavailable"},
	},
	{
		id: "xcode-device-support", name: "Xcode device support", policy: Ask, only: "darwin",
		how:     "Keeps the newest iOS version and moves older ones to the Trash. Xcode copies it again when a device on that version is plugged in.",
		paths:   func(e env) []string { return []string{e.j("Library", "Developer", "Xcode", "iOS DeviceSupport")} },
		running: []string{"Xcode"}, keepNewest: true,
	},
	{
		id: "npm", name: "npm cache", policy: Auto,
		how: "Runs npm cache clean --force. Packages download again when needed.",
		paths: func(e env) []string {
			return byOS(e, e.j(".npm", "_cacache"), e.j(".npm", "_cacache"), e.local("npm-cache", "_cacache"))
		},
		cmd: []string{"npm", "cache", "clean", "--force"},
	},
	{
		id: "yarn", name: "Yarn cache", policy: Auto,
		how: "Runs yarn cache clean.",
		paths: func(e env) []string {
			return byOS(e, e.j("Library", "Caches", "Yarn"), e.xdgCache("yarn"), e.local("Yarn", "Cache"))
		},
		cmd: []string{"yarn", "cache", "clean"},
	},
	{
		id: "pnpm", name: "pnpm store", policy: Auto,
		how: "Runs pnpm store prune, which removes packages no project uses.",
		paths: func(e env) []string {
			return byOS(e, e.j("Library", "pnpm", "store"), e.j(".local", "share", "pnpm", "store"), e.local("pnpm", "store"))
		},
		cmd: []string{"pnpm", "store", "prune"},
	},
	{
		id: "bun", name: "Bun cache", policy: Auto,
		how:   "Runs bun pm cache rm.",
		paths: func(e env) []string { return []string{e.j(".bun", "install", "cache")} },
		cmd:   []string{"bun", "pm", "cache", "rm"},
	},
	{
		id: "pip", name: "pip cache", policy: Auto,
		how: "Runs pip cache purge.",
		paths: func(e env) []string {
			return byOS(e, e.j("Library", "Caches", "pip"), e.xdgCache("pip"), e.local("pip", "Cache"))
		},
		cmd: []string{"pip3", "cache", "purge"},
	},
	{
		id: "uv", name: "uv cache", policy: Auto,
		how:   "Runs uv cache prune, which removes entries no project uses.",
		paths: func(e env) []string { return byOS(e, e.xdgCache("uv"), e.xdgCache("uv"), e.local("uv", "cache")) },
		cmd:   []string{"uv", "cache", "prune"},
	},
	{
		id: "cocoapods", name: "CocoaPods cache", policy: Auto, only: "darwin",
		how:   "Runs pod cache clean --all. Pods download again on the next pod install.",
		paths: func(e env) []string { return []string{e.j("Library", "Caches", "CocoaPods")} },
		cmd:   []string{"pod", "cache", "clean", "--all"},
	},
	{
		id: "homebrew", name: "Homebrew downloads", policy: Auto,
		how:   "Runs brew cleanup --prune=all, which removes old versions and downloads.",
		paths: func(e env) []string { return byOS(e, e.j("Library", "Caches", "Homebrew"), e.xdgCache("Homebrew"), "") },
		cmd:   []string{"brew", "cleanup", "--prune=all"},
	},
	{
		id: "gradle", name: "Gradle caches", policy: Ask,
		how:     "Moves Gradle's caches to the Trash while no Gradle daemon is running. Dependencies download again on the next build.",
		paths:   func(e env) []string { return []string{e.j(".gradle", "caches")} },
		running: []string{"GradleDaemon", "GradleWrapperMain", "studio"}, emptyOnly: true,
	},
	{
		id: "go-modules", name: "Go module cache", policy: Ask,
		how: "Runs go clean -modcache. Modules download again on the next build.",
		paths: func(e env) []string {
			if v := e.getenv("GOMODCACHE"); v != "" {
				return []string{v}
			}
			return []string{e.j("go", "pkg", "mod")}
		},
		cmd: []string{"go", "clean", "-modcache"},
	},
	{
		id: "pub", name: "Dart and Flutter packages", policy: Ask,
		how:   "Runs dart pub cache clean. Run flutter pub get in a project to fetch its packages again.",
		paths: func(e env) []string { return byOS(e, e.j(".pub-cache"), e.j(".pub-cache"), e.local("Pub", "Cache")) },
		cmd:   []string{"dart", "pub", "cache", "clean", "--force"},
	},
	{
		id: "cargo", name: "Cargo registry", policy: Report,
		how:   "Shown for information. Clean it with cargo-cache if you use it.",
		paths: func(e env) []string { return []string{e.j(".cargo", "registry")} },
	},
	{
		id: "android-emulators", name: "Android emulators", policy: Report,
		how:   "Shown for information. Delete emulators you no longer use in Android Studio's Device Manager.",
		paths: func(e env) []string { return []string{e.j(".android", "avd")} },
	},
	{
		id: "vscode", name: "VS Code caches", policy: Auto,
		how:     "Moves VS Code's web caches to the Trash while VS Code is closed.",
		paths:   func(e env) []string { return electron(e, "Code") },
		running: []string{"Code", "Electron", "code"}, emptyOnly: true,
	},
	{
		id: "cursor", name: "Cursor caches", policy: Auto,
		how:     "Moves Cursor's web caches to the Trash while Cursor is closed.",
		paths:   func(e env) []string { return electron(e, "Cursor") },
		running: []string{"Cursor"}, emptyOnly: true,
	},
	{
		id: "slack", name: "Slack caches", policy: Auto,
		how:     "Moves Slack's web caches to the Trash while Slack is closed.",
		paths:   func(e env) []string { return electron(e, "Slack") },
		running: []string{"Slack", "slack"}, emptyOnly: true,
	},
}

// electron lists the throwaway cache folders of an Electron app.
func electron(e env, app string) []string {
	var out []string
	for _, d := range []string{"Cache", "Code Cache", "GPUCache", "CachedData"} {
		out = append(out, e.appSupport(app, d))
	}
	return out
}

// Kit holds what the package needs from the outside world, so tests can swap it.
type Kit struct {
	Home     string
	GOOS     string
	Getenv   func(string) string
	LookTool func(name string) (string, error)
	Running  func(names []string) string // returns the first running one, or ""
	Run      func(ctx context.Context, bin string, args []string) error
	Trash    trash.Trasher
	Log      interface{ Append(history.Entry) error }
	Now      func() time.Time
}

// DefaultKit uses the real system.
func DefaultKit(home string, log interface{ Append(history.Entry) error }) *Kit {
	return &Kit{
		Home: home, GOOS: runtime.GOOS, Getenv: os.Getenv,
		LookTool: func(n string) (string, error) { return lookTool(home, n) },
		Running:  running,
		Run:      runTool,
		Trash:    trash.Default(),
		Log:      log,
		Now:      time.Now,
	}
}

func (k *Kit) env() env { return env{home: k.Home, goos: k.GOOS, getenv: k.Getenv} }

// Survey finds the caches present on this machine, with sizes, largest first.
// Caches that are empty or absent are left out.
func (k *Kit) Survey() []Cache {
	e := k.env()
	var out []Cache
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, d := range defs {
		if d.only != "" && d.only != k.GOOS {
			continue
		}
		d := d
		wg.Add(1)
		go func() {
			defer wg.Done()
			var paths []string
			if d.paths != nil {
				paths = existing(d.paths(e))
			}
			c := Cache{ID: d.id, Name: d.name, Policy: d.policy, How: d.how, def: d}
			for _, p := range paths {
				c.Bytes += dirSize(p)
			}
			if d.paths != nil && c.Bytes == 0 {
				return
			}
			if d.cmd != nil {
				if _, err := k.LookTool(d.cmd[0]); err != nil {
					if d.paths == nil {
						return // nothing to show without the tool
					}
					c.Blocked = d.cmd[0] + " is not installed"
				}
			}
			if c.Blocked == "" && len(d.running) > 0 {
				if r := k.Running(d.running); r != "" {
					c.Blocked = r + " is running"
				}
			}
			mu.Lock()
			out = append(out, c)
			mu.Unlock()
		}()
	}
	wg.Wait()
	sort.Slice(out, func(i, j int) bool {
		if out[i].Bytes != out[j].Bytes {
			return out[i].Bytes > out[j].Bytes
		}
		return out[i].ID < out[j].ID
	})
	return out
}

// ErrReportOnly is returned for caches Mothball only shows.
var ErrReportOnly = errors.New("this cache is shown for information only")

// Clean cleans one cache from a Survey and returns how much space it freed
// (or moved to the Trash). It checks again that cleaning is allowed now.
func (k *Kit) Clean(c Cache) (int64, error) {
	d := c.def
	if d == nil {
		for _, x := range defs {
			if x.id == c.ID {
				d = x
			}
		}
	}
	if d == nil {
		return 0, fmt.Errorf("unknown cache %q", c.ID)
	}
	if d.policy == Report {
		return 0, ErrReportOnly
	}
	if len(d.running) > 0 {
		if r := k.Running(d.running); r != "" {
			return 0, fmt.Errorf("%s is running", r)
		}
	}
	e := k.env()
	var paths []string
	if d.paths != nil {
		paths = existing(d.paths(e))
	}
	before := int64(0)
	for _, p := range paths {
		before += dirSize(p)
	}

	if d.cmd != nil {
		bin, err := k.LookTool(d.cmd[0])
		if err != nil {
			return 0, fmt.Errorf("%s is not installed", d.cmd[0])
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		if err := k.Run(ctx, bin, d.cmd[1:]); err != nil {
			return 0, fmt.Errorf("%s: %w", strings.Join(d.cmd, " "), err)
		}
		after := int64(0)
		for _, p := range paths {
			after += dirSize(p)
		}
		if before > after {
			return before - after, nil
		}
		return 0, nil
	}

	var targets []string
	for _, p := range paths {
		switch {
		case d.keepNewest:
			targets = append(targets, allButNewest(p)...)
		case d.emptyOnly:
			entries, _ := os.ReadDir(p)
			for _, en := range entries {
				targets = append(targets, filepath.Join(p, en.Name()))
			}
		default:
			targets = append(targets, p)
		}
	}
	var moved int64
	for _, t := range targets {
		if !safeTarget(k.Home, t, paths) {
			continue
		}
		size := dirSize(t)
		dest, err := k.Trash.Trash(t)
		if err != nil {
			return moved, err
		}
		moved += size
		if err := k.Log.Append(history.Entry{Event: history.Trashed, Time: k.Now(), Original: t, Trashed: dest,
			Pack: "cache:" + d.id, Bytes: size}); err != nil {
			return moved, err
		}
	}
	return moved, nil
}

// safeTarget is the last line of defence before a move: the target must sit
// inside one of the cache's own folders, and never be home itself.
func safeTarget(home, t string, roots []string) bool {
	t = filepath.Clean(t)
	if t == filepath.Clean(home) || t == filepath.Dir(t) {
		return false
	}
	for _, r := range roots {
		r = filepath.Clean(r)
		if t == r || strings.HasPrefix(t, r+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

// allButNewest returns every entry in dir except the most recently modified.
func allButNewest(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) < 2 {
		return nil
	}
	type item struct {
		path string
		mod  time.Time
	}
	var items []item
	for _, e := range entries {
		if info, err := e.Info(); err == nil && e.IsDir() {
			items = append(items, item{filepath.Join(dir, e.Name()), info.ModTime()})
		}
	}
	if len(items) < 2 {
		return nil
	}
	sort.Slice(items, func(i, j int) bool { return items[i].mod.After(items[j].mod) })
	var out []string
	for _, it := range items[1:] {
		out = append(out, it.path)
	}
	return out
}

func existing(paths []string) []string {
	var out []string
	for _, p := range paths {
		if p == "" {
			continue
		}
		if info, err := os.Lstat(p); err == nil && info.IsDir() {
			out = append(out, p)
		}
	}
	return out
}

func dirSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.Type().IsRegular() {
			if info, err := d.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}

// lookTool finds a developer tool even when the service was started by the
// system with a short PATH, by also checking the usual install folders.
func lookTool(home, name string) (string, error) {
	if p, err := exec.LookPath(name); err == nil {
		return p, nil
	}
	dirs := []string{"/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
		filepath.Join(home, ".local", "bin"), filepath.Join(home, "go", "bin"), "/usr/local/go/bin",
		filepath.Join(home, ".cargo", "bin"), filepath.Join(home, ".bun", "bin"),
		filepath.Join(home, "development", "flutter", "bin"), filepath.Join(home, "flutter", "bin"),
		filepath.Join(home, "fvm", "default", "bin"), filepath.Join(home, ".pub-cache", "bin")}
	if nvm, _ := filepath.Glob(filepath.Join(home, ".nvm", "versions", "node", "*", "bin")); len(nvm) > 0 {
		sort.Strings(nvm)
		dirs = append(dirs, nvm[len(nvm)-1])
	}
	for _, d := range dirs {
		for _, n := range []string{name, name + ".exe", name + ".cmd"} {
			p := filepath.Join(d, n)
			if info, err := os.Stat(p); err == nil && !info.IsDir() {
				return p, nil
			}
		}
	}
	return "", exec.ErrNotFound
}

// runTool runs a cleaning command with the tool's own folder first on PATH,
// so scripts like npm find their runtime.
func runTool(ctx context.Context, bin string, args []string) error {
	cmd := proc.CommandContext(ctx, bin, args...)
	cmd.Env = append(os.Environ(), "PATH="+filepath.Dir(bin)+string(os.PathListSeparator)+os.Getenv("PATH"))
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(out.String())
		if len(msg) > 300 {
			msg = msg[len(msg)-300:]
		}
		return fmt.Errorf("%w: %s", err, msg)
	}
	return nil
}

// running reports the first of names that is a running process.
func running(names []string) string {
	for _, n := range names {
		var cmd *exec.Cmd
		if runtime.GOOS == "windows" {
			cmd = proc.Command("tasklist", "/FI", "IMAGENAME eq "+n+".exe", "/NH")
			out, err := cmd.Output()
			if err == nil && strings.Contains(strings.ToLower(string(out)), strings.ToLower(n)+".exe") {
				return n
			}
			continue
		}
		cmd = proc.Command("pgrep", "-x", n)
		if err := cmd.Run(); err == nil {
			return n
		}
		if n == "GradleDaemon" || n == "GradleWrapperMain" {
			if proc.Command("pgrep", "-f", n).Run() == nil {
				return "Gradle"
			}
		}
	}
	return ""
}
