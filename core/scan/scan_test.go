package scan

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/rules"
)

func packs(t *testing.T) *pack.Set {
	t.Helper()
	s, err := pack.Load(rules.Files)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// touch creates each file (and its folders) under root.
func touch(t *testing.T, root string, files ...string) {
	t.Helper()
	for _, f := range files {
		p := filepath.Join(root, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func mkdir(t *testing.T, root string, dirs ...string) {
	t.Helper()
	for _, d := range dirs {
		if err := os.MkdirAll(filepath.Join(root, filepath.FromSlash(d)), 0o755); err != nil {
			t.Fatal(err)
		}
	}
}

func scanOf(t *testing.T, home string, roots ...string) Result {
	t.Helper()
	if len(roots) == 0 {
		roots = []string{home}
	}
	return New(packs(t), home).Scan(Options{Roots: roots, Home: home})
}

func paths(r Result) map[string]Candidate {
	m := map[string]Candidate{}
	for _, c := range r.Candidates {
		m[c.Path] = c
	}
	return m
}

func git(t *testing.T, dir string, env []string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), append([]string{
		"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t",
	}, env...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func needGit(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
}

func TestFindsVerifiedFlutterOutput(t *testing.T) {
	home := t.TempDir()
	app := filepath.Join(home, "dev", "app")
	touch(t, app, "pubspec.yaml", "lib/main.dart",
		".dart_tool/package_config.json", "build/flutter_assets/AssetManifest.json")

	got := paths(scanOf(t, home))
	for _, want := range []string{filepath.Join(app, ".dart_tool"), filepath.Join(app, "build")} {
		c, ok := got[want]
		if !ok {
			t.Fatalf("missing %s; got %v", want, got)
		}
		if c.Pack != "flutter" || c.Wake != "flutter pub get" || c.Bytes == 0 {
			t.Errorf("bad candidate %+v", c)
		}
	}
	if len(got) != 2 {
		t.Errorf("want 2 candidates, got %d: %v", len(got), got)
	}
}

// A folder named like output but holding source must never match.
func TestSourceFolderNamedBuildIsNotOutput(t *testing.T) {
	home := t.TempDir()
	app := filepath.Join(home, "app")
	touch(t, app, "pubspec.yaml", "build/generator.dart", "build/README.md")

	if got := paths(scanOf(t, home)); len(got) != 0 {
		t.Fatalf("source folder was treated as output: %v", got)
	}
}

// The real-world case: Go's module cache holds source folders called build.
func TestPackageCachesAreNeverScanned(t *testing.T) {
	home := t.TempDir()
	mod := filepath.Join(home, "go", "pkg", "mod", "golang.org", "x", "tool@v1")
	touch(t, mod, "build.gradle", "build/classes/Main.java", "package.json", "node_modules/.bin/x")
	cache := filepath.Join(home, ".gradle", "caches", "proj")
	touch(t, cache, "build.gradle", "build/intermediates/a")

	if got := paths(scanOf(t, home)); len(got) != 0 {
		t.Fatalf("scanned inside a package cache: %v", got)
	}
}

func TestTrackedFoldersAreNeverOutput(t *testing.T) {
	needGit(t)
	home := t.TempDir()
	app := filepath.Join(home, "web")
	touch(t, app, "package.json", "node_modules/.package-lock.json", "node_modules/left-pad/index.js")
	git(t, app, nil, "init", "-q")
	git(t, app, nil, "add", "-A")
	git(t, app, nil, "commit", "-qm", "vendored deps on purpose")

	if got := paths(scanOf(t, home)); len(got) != 0 {
		t.Fatalf("tracked folder was treated as output: %v", got)
	}
}

func TestIdleDaysComeFromLastCommit(t *testing.T) {
	needGit(t)
	home := t.TempDir()
	app := filepath.Join(home, "old-site")
	touch(t, app, "package.json", ".gitignore")
	if err := os.WriteFile(filepath.Join(app, ".gitignore"), []byte("node_modules/\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	old := time.Now().AddDate(0, 0, -100).Format(time.RFC3339)
	git(t, app, nil, "init", "-q")
	git(t, app, nil, "add", "-A")
	git(t, app, []string{"GIT_AUTHOR_DATE=" + old, "GIT_COMMITTER_DATE=" + old}, "commit", "-qm", "init")
	// Output written today must not make the project look active.
	touch(t, app, "node_modules/.package-lock.json", "node_modules/react/index.js")

	c, ok := paths(scanOf(t, home))[filepath.Join(app, "node_modules")]
	if !ok {
		t.Fatal("node_modules not found")
	}
	if c.IdleDays < 99 || c.IdleDays > 101 {
		t.Errorf("idle days = %d, want about 100", c.IdleDays)
	}
	if !c.InGit || c.Dirty {
		t.Errorf("git facts wrong: %+v", c)
	}

	// Uncommitted work to a tracked file marks the project as in use.
	if err := os.WriteFile(filepath.Join(app, "package.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	c = paths(scanOf(t, home))[filepath.Join(app, "node_modules")]
	if !c.Dirty {
		t.Error("uncommitted change not detected")
	}
}

func TestDependenciesInsideNodeModulesAreNotProjects(t *testing.T) {
	home := t.TempDir()
	app := filepath.Join(home, "app")
	touch(t, app, "package.json", "node_modules/.package-lock.json",
		"node_modules/dep/package.json", "node_modules/dep/node_modules/.bin/x")

	got := paths(scanOf(t, home))
	if len(got) != 1 {
		t.Fatalf("want only the top node_modules, got %v", got)
	}
}

func TestIgnoreFileSkipsProjectAndChildren(t *testing.T) {
	home := t.TempDir()
	app := filepath.Join(home, "keep")
	touch(t, app, IgnoreFile, "package.json", "node_modules/.bin/x", "sub/pubspec.yaml", "sub/.dart_tool/package_config.json")

	if got := paths(scanOf(t, home)); len(got) != 0 {
		t.Fatalf("ignored project was scanned: %v", got)
	}
}

func TestSymlinkedOutputIsNotFollowed(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlinks need extra rights on Windows")
	}
	home := t.TempDir()
	real := filepath.Join(home, "precious")
	touch(t, real, ".package-lock.json", "important.txt")
	app := filepath.Join(home, "app")
	touch(t, app, "package.json")
	if err := os.Symlink(real, filepath.Join(app, "node_modules")); err != nil {
		t.Fatal(err)
	}
	if got := paths(scanOf(t, home)); len(got) != 0 {
		t.Fatalf("followed a symlink: %v", got)
	}
}

func TestNestedProjectsInMonorepo(t *testing.T) {
	home := t.TempDir()
	repo := filepath.Join(home, "mono")
	touch(t, repo, "package.json", "node_modules/.bin/x",
		"apps/web/package.json", "apps/web/.next/BUILD_ID",
		"apps/mobile/pubspec.yaml", "apps/mobile/build/flutter_assets/a",
		"apps/mobile/ios/Podfile", "apps/mobile/ios/Pods/Manifest.lock")
	mkdir(t, repo, "apps/mobile/ios/Runner")

	got := paths(scanOf(t, home))
	for _, want := range []string{
		filepath.Join(repo, "node_modules"),
		filepath.Join(repo, "apps", "web", ".next"),
		filepath.Join(repo, "apps", "mobile", "build"),
		filepath.Join(repo, "apps", "mobile", "ios", "Pods"),
	} {
		if _, ok := got[want]; !ok {
			t.Errorf("missing %s", want)
		}
	}
	if len(got) != 4 {
		t.Errorf("want 4 candidates, got %d", len(got))
	}
}
