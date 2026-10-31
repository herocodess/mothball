//go:build e2e

// Package e2e runs the real mothball binary against a folder of fake
// projects, on whatever system the test runs on, and checks what it moves,
// what it leaves alone, and that moved folders land in the system Trash.
//
//	go test -tags e2e -v ./e2e
//
// CI runs it on Windows and Linux, on x64 and Arm. It moves folders to the
// real Recycle Bin on Windows; on Linux and macOS it uses a private Trash.
package e2e

import (
	"bytes"
	"encoding/json"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"
)

var bin string // the mothball binary under test

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "mothball-e2e-bin-")
	if err != nil {
		panic(err)
	}
	bin = filepath.Join(dir, "mothball")
	if runtime.GOOS == "windows" {
		bin += ".exe"
	}
	if b := os.Getenv("MOTHBALL_BIN"); b != "" {
		bin = b // test a release binary as shipped
	} else {
		cmd := exec.Command("go", "build", "-o", bin, "../cli/mothball")
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			panic(err)
		}
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

type env struct {
	t     *testing.T
	root  string // the fake projects
	state string // MOTHBALL_STATE_DIR
	xdg   string // private Trash on Linux
}

func newEnv(t *testing.T) *env {
	// Fixtures live next to a private home so Linux trashing is a rename on
	// the same disk, like it is for a real user.
	base := t.TempDir()
	e := &env{t: t, root: filepath.Join(base, "dev"), state: filepath.Join(base, "state"), xdg: filepath.Join(base, "xdg")}
	for _, d := range []string{e.root, e.state, e.xdg} {
		must(t, os.MkdirAll(d, 0o755))
	}
	return e
}

func (e *env) environ() []string {
	return append(os.Environ(),
		"MOTHBALL_STATE_DIR="+e.state,
		"XDG_DATA_HOME="+e.xdg,
	)
}

// run runs mothball and returns its output; it fails the test on a non-zero
// exit unless allowFail is set.
func (e *env) run(allowFail bool, args ...string) (string, int) {
	e.t.Helper()
	cmd := exec.Command(bin, args...)
	cmd.Env = e.environ()
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	code := 0
	if x, ok := err.(*exec.ExitError); ok {
		code = x.ExitCode()
	} else if err != nil {
		e.t.Fatalf("mothball %v: %v", args, err)
	}
	if code != 0 && !allowFail {
		e.t.Fatalf("mothball %v exited %d:\n%s", args, code, out.String())
	}
	return out.String(), code
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func write(t *testing.T, path string, size int) {
	t.Helper()
	must(t, os.MkdirAll(filepath.Dir(path), 0o755))
	must(t, os.WriteFile(path, bytes.Repeat([]byte("x"), size), 0o644))
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

// project makes a git repo with the given files committed at commitAge ago.
// Files under "out:" are build output: created but not committed (and
// gitignored), unless tracked is set.
type project struct {
	name      string
	files     []string // committed source files
	output    []string // build output files (relative paths), not committed
	tracked   bool     // commit the output too (a "build" folder someone checked in)
	commitAge time.Duration
	dirty     bool // leave an uncommitted change
	ignore    bool // add a .mothballignore
	noGit     bool
	contents  map[string]string // content for some of the files
}

func (e *env) make(p project) string {
	t := e.t
	dir := filepath.Join(e.root, p.name)
	for _, f := range p.files {
		if c, ok := p.contents[f]; ok {
			must(t, os.MkdirAll(filepath.Dir(filepath.Join(dir, f)), 0o755))
			must(t, os.WriteFile(filepath.Join(dir, f), []byte(c), 0o644))
			continue
		}
		write(t, filepath.Join(dir, f), 64)
	}
	for _, f := range p.output {
		write(t, filepath.Join(dir, f), 200_000)
	}
	if p.ignore {
		write(t, filepath.Join(dir, ".mothballignore"), 0)
	}
	if p.noGit {
		return dir
	}
	git := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		when := time.Now().Add(-p.commitAge).Format(time.RFC3339)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_DATE="+when, "GIT_COMMITTER_DATE="+when)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("init", "-q")
	git("config", "user.email", "e2e@example.com")
	git("config", "user.name", "e2e")
	git("config", "commit.gpgsign", "false")
	if !p.tracked {
		var ignore []string
		seen := map[string]bool{}
		for _, f := range p.output {
			top := strings.SplitN(filepath.ToSlash(f), "/", 2)[0]
			if !seen[top] {
				seen[top] = true
				ignore = append(ignore, "/"+top+"/")
			}
		}
		must(t, os.WriteFile(filepath.Join(dir, ".gitignore"), []byte(strings.Join(ignore, "\n")+"\n"), 0o644))
	}
	git("add", "-A")
	git("commit", "-q", "-m", "initial")
	if p.dirty {
		must(t, os.WriteFile(filepath.Join(dir, p.files[0]), []byte("work in progress"), 0o644))
	}
	// Make file times match the commit, as on a machine nobody touched.
	old := time.Now().Add(-p.commitAge)
	_ = filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err == nil && !strings.Contains(path, string(filepath.Separator)+".git") {
			_ = os.Chtimes(path, old, old)
		}
		return nil
	})
	return dir
}

const day = 24 * time.Hour

// fixtures builds the standard set and returns the output folders that must
// be put away and the ones that must be left alone.
func (e *env) fixtures() (idle, keep []string) {
	old := 120 * day
	add := func(dir string, outs ...string) {
		for _, o := range outs {
			idle = append(idle, filepath.Join(dir, filepath.FromSlash(o)))
		}
	}
	kept := func(dir string, outs ...string) {
		for _, o := range outs {
			keep = append(keep, filepath.Join(dir, filepath.FromSlash(o)))
		}
	}

	add(e.make(project{name: "web-old", commitAge: old,
		files:  []string{"package.json", "src/index.js"},
		output: []string{"node_modules/.package-lock.json", "node_modules/left-pad/index.js"}}), "node_modules")
	add(e.make(project{name: "rust-old", commitAge: old,
		files:  []string{"Cargo.toml", "src/main.rs"},
		output: []string{"target/CACHEDIR.TAG", "target/debug/app"}}), "target")
	add(e.make(project{name: "py-old", commitAge: old,
		files:  []string{"requirements.txt", "app.py"},
		output: []string{".venv/pyvenv.cfg", ".venv/lib/site.py"}}), ".venv")
	add(e.make(project{name: "flutter-old", commitAge: old,
		files:  []string{"pubspec.yaml", "lib/main.dart"},
		output: []string{".dart_tool/package_config.json", "build/.last_build_id", "build/app/x"}}), ".dart_tool", "build")
	add(e.make(project{name: "dotnet-old", commitAge: old,
		files:  []string{"App.csproj", "Program.cs"},
		output: []string{"bin/Debug/app.dll", "obj/project.assets.json"}}), "bin", "obj")

	// Traps.
	kept(e.make(project{name: "web-active", commitAge: 2 * day,
		files:  []string{"package.json"},
		output: []string{"node_modules/.package-lock.json", "node_modules/a/index.js"}}), "node_modules")
	kept(e.make(project{name: "web-dirty", commitAge: old, dirty: true,
		files:  []string{"package.json", "src/index.js"},
		output: []string{"node_modules/.package-lock.json", "node_modules/a/index.js"}}), "node_modules")
	kept(e.make(project{name: "flutter-tracked-build", commitAge: old, tracked: true,
		files:  []string{"pubspec.yaml"},
		output: []string{"build/.last_build_id", "build/app/x"}}), "build")
	kept(e.make(project{name: "web-ignored", commitAge: old, ignore: true,
		files:  []string{"package.json"},
		output: []string{"node_modules/.package-lock.json", "node_modules/a/index.js"}}), "node_modules")
	// A folder called node_modules with no project around it.
	kept(e.make(project{name: "not-a-project", commitAge: old, noGit: true,
		output: []string{"node_modules/.package-lock.json", "node_modules/a/index.js"}}), "node_modules")
	// A "build" folder in a project that is not Flutter and has no build markers.
	kept(e.make(project{name: "docs-build", commitAge: old,
		files:  []string{"README.md"},
		output: []string{"build/index.html"}}), "build")
	return idle, keep
}

func sorted(xs []string) []string {
	out := append([]string(nil), xs...)
	for i := range out {
		out[i] = canon(out[i])
	}
	sort.Strings(out)
	return out
}

// canon resolves symlinks in temp paths (macOS /var -> /private/var) and
// Windows short names, so paths from mothball and the test compare equal.
func canon(p string) string {
	dir, base := filepath.Split(p)
	for dir != "" && dir != string(filepath.Separator) {
		if r, err := filepath.EvalSymlinks(dir); err == nil {
			return filepath.Join(r, base)
		}
		var b string
		dir, b = filepath.Split(strings.TrimRight(dir, `/\`))
		base = filepath.Join(b, base)
	}
	return p
}

func TestScanFindsOnlyIdleOutput(t *testing.T) {
	e := newEnv(t)
	wantIdle, _ := e.fixtures()
	out, _ := e.run(false, "scan", "--json", e.root)
	var res struct {
		Idle []struct {
			Path string `json:"path"`
		} `json:"idle"`
	}
	must(t, json.Unmarshal([]byte(out), &res))
	var got []string
	for _, c := range res.Idle {
		got = append(got, c.Path)
	}
	if g, w := sorted(got), sorted(wantIdle); strings.Join(g, "\n") != strings.Join(w, "\n") {
		t.Fatalf("idle output\n got:\n  %s\nwant:\n  %s", strings.Join(g, "\n  "), strings.Join(w, "\n  "))
	}
}

func TestCleanMovesIdleOutputToTheTrash(t *testing.T) {
	e := newEnv(t)
	idle, keep := e.fixtures()
	out, _ := e.run(false, "clean", "--yes", e.root)
	t.Log(out)

	for _, p := range idle {
		if exists(p) {
			t.Errorf("not put away: %s", p)
		}
		// The project's own files stay.
		if !exists(filepath.Dir(p)) {
			t.Errorf("project folder gone: %s", filepath.Dir(p))
		}
	}
	for _, p := range keep {
		if !exists(p) {
			t.Errorf("trap moved, must be left alone: %s", p)
		}
	}
	for _, src := range []string{"web-old/package.json", "rust-old/Cargo.toml", "flutter-old/lib/main.dart", "dotnet-old/Program.cs"} {
		if !exists(filepath.Join(e.root, filepath.FromSlash(src))) {
			t.Errorf("source file gone: %s", src)
		}
	}

	switch runtime.GOOS {
	case "linux":
		info, _ := filepath.Glob(filepath.Join(e.xdg, "Trash", "info", "*.trashinfo"))
		files, _ := os.ReadDir(filepath.Join(e.xdg, "Trash", "files"))
		if len(info) != len(idle) || len(files) != len(idle) {
			t.Errorf("Trash has %d info files and %d entries, want %d each", len(info), len(files), len(idle))
		}
		for _, f := range info {
			b, _ := os.ReadFile(f)
			if !strings.Contains(string(b), "Path=/") || !strings.Contains(string(b), "DeletionDate=") {
				t.Errorf("bad trashinfo %s:\n%s", f, b)
			}
		}
	case "windows":
		names := recycleBinNames(t)
		for _, p := range idle {
			if !names[strings.ToLower(filepath.Base(p))] {
				t.Errorf("%s is not in the Recycle Bin (has %v)", filepath.Base(p), keys(names))
			}
		}
	}

	// A second run finds nothing more to do.
	out, _ = e.run(false, "scan", "--json", e.root)
	if strings.Contains(out, `"idle": [`) && !strings.Contains(out, `"idle": null`) && !strings.Contains(out, `"idle": []`) {
		t.Errorf("idle output left after clean:\n%s", out)
	}
}

func keys(m map[string]bool) []string {
	var out []string
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// recycleBinNames lists the names of items in the Recycle Bin whose original
// location is under a temp folder (where this test works).
func recycleBinNames(t *testing.T) map[string]bool {
	t.Helper()
	script := `$s = New-Object -ComObject Shell.Application; $s.NameSpace(10).Items() | ForEach-Object { $_.Name }`
	out, err := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script).CombinedOutput()
	if err != nil {
		t.Fatalf("reading the Recycle Bin: %v\n%s", err, out)
	}
	names := map[string]bool{}
	for _, l := range strings.Split(string(out), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			names[strings.ToLower(l)] = true
		}
	}
	return names
}

func TestWakeRestoresAProject(t *testing.T) {
	npm := "npm"
	if _, err := exec.LookPath(npm); err != nil {
		t.Skip("npm is not installed on this runner")
	}
	e := newEnv(t)
	dir := e.make(project{name: "web-old", commitAge: 120 * day,
		files:    []string{"package.json"},
		contents: map[string]string{"package.json": `{"name":"web-old","version":"1.0.0","private":true}`},
		output:   []string{"node_modules/.package-lock.json", "node_modules/a/index.js"}})
	e.run(false, "clean", "--yes", e.root)
	if exists(filepath.Join(dir, "node_modules")) {
		t.Fatal("node_modules not put away")
	}
	list, _ := e.run(false, "wake")
	if !strings.Contains(list, "web-old") {
		t.Fatalf("wake does not list the project:\n%s", list)
	}
	out, _ := e.run(false, "wake", "--yes", dir)
	t.Log(out)
	list, _ = e.run(false, "wake")
	if strings.Contains(list, "web-old") {
		t.Fatalf("still listed after waking:\n%s", list)
	}
}

func TestPythonWakeCommandRuns(t *testing.T) {
	py := "python3"
	if runtime.GOOS == "windows" {
		py = "python"
	}
	if _, err := exec.LookPath(py); err != nil {
		t.Skip("python is not installed on this runner")
	}
	e := newEnv(t)
	dir := e.make(project{name: "py-old", commitAge: 120 * day,
		files:    []string{"requirements.txt"},
		contents: map[string]string{"requirements.txt": "# nothing to download\n"},
		output:   []string{".venv/pyvenv.cfg", ".venv/lib/x.py"}})
	e.run(false, "clean", "--yes", e.root)
	if runtime.GOOS != "windows" {
		// The pack runs "python -m venv"; make sure "python" resolves here.
		if _, err := exec.LookPath("python"); err != nil {
			t.Skip("no python on PATH, only python3")
		}
	}
	out, _ := e.run(false, "wake", "--yes", dir)
	t.Log(out)
	if !exists(filepath.Join(dir, ".venv", "pyvenv.cfg")) {
		t.Fatal("wake did not recreate .venv")
	}
}

func TestServiceAnswersAndStops(t *testing.T) {
	e := newEnv(t)
	e.fixtures()
	cfg, _ := json.Marshal(map[string]any{"roots": []string{e.root}, "idleDays": 60, "targetFreeGB": 1, "checkMinutes": 15, "skipUpdateCheck": true})
	must(t, os.WriteFile(filepath.Join(e.state, "config.json"), cfg, 0o600))
	cmd := exec.Command(bin, "service", "run", "--no-tray")
	cmd.Env = e.environ()
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	must(t, cmd.Start())
	defer func() { _ = cmd.Process.Kill() }()

	var ep struct{ URL, Token string }
	deadline := time.Now().Add(20 * time.Second)
	for {
		b, err := os.ReadFile(filepath.Join(e.state, "service.json"))
		if err == nil && json.Unmarshal(b, &ep) == nil && ep.URL != "" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("service did not start:\n%s", out.String())
		}
		time.Sleep(200 * time.Millisecond)
	}

	get := func(method, path, token string) (int, string) {
		req, _ := http.NewRequest(method, ep.URL+path, strings.NewReader("{}"))
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var b bytes.Buffer
		_, _ = b.ReadFrom(resp.Body)
		return resp.StatusCode, b.String()
	}
	if code, _ := get("GET", "/v1/status", ""); code != 401 {
		t.Fatalf("status without a token returned %d, want 401", code)
	}
	code, body := get("GET", "/v1/status", ep.Token)
	if code != 200 || !strings.Contains(body, `"freeBytes"`) {
		t.Fatalf("status %d: %s", code, body)
	}
	code, body = get("POST", "/v1/scan", ep.Token)
	if code != 200 || !strings.Contains(body, "web-old") {
		t.Fatalf("scan %d: %s", code, body)
	}

	status, _ := e.run(false, "status")
	if !strings.Contains(status, "running") {
		t.Fatalf("mothball status does not see the service:\n%s", status)
	}
}

// TestServiceInstall registers the service to start at login, checks the
// system knows about it, and removes it again. Only on CI machines: it
// changes the user's login items.
func TestServiceInstall(t *testing.T) {
	if os.Getenv("CI") == "" {
		t.Skip("changes login items; runs on CI only")
	}
	e := newEnv(t)
	out, code := e.run(true, "service", "install")
	t.Log(out)
	if runtime.GOOS == "linux" && code != 0 && strings.Contains(out, "systemctl") {
		t.Skip("no systemd user session on this runner")
	}
	if code != 0 {
		t.Fatalf("install exited %d", code)
	}
	defer e.run(true, "service", "uninstall")
	switch runtime.GOOS {
	case "windows":
		q, err := exec.Command("schtasks", "/Query", "/TN", "Mothball").CombinedOutput()
		if err != nil {
			t.Fatalf("scheduled task missing: %v\n%s", err, q)
		}
	case "linux":
		home, _ := os.UserHomeDir()
		unit := filepath.Join(home, ".config", "systemd", "user", "mothball.service")
		if !exists(unit) {
			t.Fatalf("no unit at %s", unit)
		}
	}
	u, _ := e.run(false, "service", "uninstall")
	t.Log(u)
}

func TestVersionAndHelp(t *testing.T) {
	e := newEnv(t)
	v, _ := e.run(false, "version")
	if !strings.HasPrefix(v, "mothball ") {
		t.Fatalf("version: %q", v)
	}
	h, _ := e.run(false, "help")
	for _, cmd := range []string{"scan", "clean", "wake", "service install", "update"} {
		if !strings.Contains(h, cmd) {
			t.Errorf("help does not mention %q", cmd)
		}
	}
}
