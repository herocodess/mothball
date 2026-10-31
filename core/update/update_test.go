package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNewer(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"0.2.0", "0.1.0", true},
		{"v0.1.10", "0.1.9", true},
		{"0.1.0", "0.1.0", false},
		{"0.1.0", "0.2.0", false},
		{"1.0.0", "0.9.9", true},
		{"0.1.0", "0.1.0-dev", true},
		{"0.1.0-dev", "0.1.0", false},
		{"0.1.1", "0.1.0-dev", true},
	}
	for _, c := range cases {
		if got := Newer(c.a, c.b); got != c.want {
			t.Errorf("Newer(%q, %q) = %v", c.a, c.b, got)
		}
	}
}

func TestParseChecksums(t *testing.T) {
	h := "bb1c50ac953539467a6b7fadb2fc736fee9f107c47a686d570045f093b0f46e9"
	m := ParseChecksums(h + "  Mothball-0.1.0.dmg\n\ngarbage line\n")
	if m["Mothball-0.1.0.dmg"] != h || len(m) != 1 {
		t.Fatalf("got %v", m)
	}
}

func TestBundleOf(t *testing.T) {
	exe := "/Applications/Mothball.app/Contents/Library/LoginItems/Mothball Agent.app/Contents/MacOS/mothball"
	if got := bundleOf(exe); got != "/Applications/Mothball.app" {
		t.Fatalf("got %q", got)
	}
	if bundleOf("/opt/homebrew/bin/mothball") != "" {
		t.Fatal("bare binary treated as an app")
	}
}

type fakeMac struct {
	teams    map[string]string // app base name -> team
	badVerif bool
}

func (f fakeMac) Extract(dmg, dest string) error {
	if err := os.MkdirAll(filepath.Join(dest, "Contents"), 0o755); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dest, "Contents", "version"), []byte("new"), 0o644)
}

func (f fakeMac) Team(app string) (string, error) {
	if b, err := os.ReadFile(filepath.Join(app, "Contents", "version")); err == nil {
		return f.teams[string(b)], nil
	}
	return "", nil
}

func (f fakeMac) Verify(app string) error {
	if f.badVerif {
		return fmt.Errorf("rejected")
	}
	return nil
}

type server struct {
	*httptest.Server
	minimum string
	dmg     []byte
	sum     string
}

func newServer(t *testing.T, tag string) *server {
	s := &server{dmg: []byte("pretend disk image")}
	h := sha256.Sum256(s.dmg)
	s.sum = hex.EncodeToString(h[:])
	v := tag[1:]
	mux := http.NewServeMux()
	s.Server = httptest.NewServer(mux)
	mux.HandleFunc("/repos/"+Repo+"/releases/latest", func(w http.ResponseWriter, r *http.Request) {
		assets := []map[string]any{
			{"name": "Mothball-" + v + ".dmg", "browser_download_url": s.URL + "/dmg", "size": len(s.dmg)},
			{"name": "checksums-" + v + ".txt", "browser_download_url": s.URL + "/sums"},
			{"name": WindowsInstaller(v, "amd64"), "browser_download_url": s.URL + "/dmg", "size": len(s.dmg)},
			{"name": WindowsInstaller(v, "arm64"), "browser_download_url": s.URL + "/dmg", "size": len(s.dmg)},
			{"name": LinuxAppImage(v, "amd64"), "browser_download_url": s.URL + "/dmg", "size": len(s.dmg)},
			{"name": LinuxAppImage(v, "arm64"), "browser_download_url": s.URL + "/dmg", "size": len(s.dmg)},
		}
		if s.minimum != "" {
			assets = append(assets, map[string]any{"name": "update.json", "browser_download_url": s.URL + "/manifest"})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"tag_name": tag, "html_url": "https://example.com/" + tag, "body": "## What's new\n- Faster scans", "published_at": "2026-11-02T10:00:00Z", "assets": assets})
	})
	mux.HandleFunc("/dmg", func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write(s.dmg) })
	mux.HandleFunc("/sums", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s  Mothball-%s.dmg\n", s.sum, v)
		fmt.Fprintf(w, "%s  %s\n", s.sum, WindowsInstaller(v, "amd64"))
		fmt.Fprintf(w, "%s  %s\n", s.sum, WindowsInstaller(v, "arm64"))
		fmt.Fprintf(w, "%s  %s\n", s.sum, LinuxAppImage(v, "amd64"))
		fmt.Fprintf(w, "%s  %s\n", s.sum, LinuxAppImage(v, "arm64"))
	})
	mux.HandleFunc("/manifest", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{"minimum":%q,"message":"Fixes a bug that could put away the wrong folder."}`, s.minimum)
	})
	t.Cleanup(s.Close)
	return s
}

func newUpdater(t *testing.T, srv *server, mac fakeMac) *Updater {
	apps := t.TempDir()
	app := filepath.Join(apps, "Mothball.app")
	if err := os.MkdirAll(filepath.Join(app, "Contents"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(app, "Contents", "version"), []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	u := &Updater{Current: "0.1.0", Dir: t.TempDir(), App: app, API: srv.URL, HTTP: srv.Client(), Mac: mac, Now: time.Now}
	u.st = State{Current: u.Current, CanInstall: u.canInstall()}
	return u
}

func TestCheckFindsNewerRelease(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1", "new": "TEAM1"}})
	st, err := u.Check(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !st.Available || st.Latest != "0.2.0" || st.Required || !st.CanInstall || st.Notes == "" || st.PublishedAt.IsZero() {
		t.Fatalf("state %+v", st)
	}
}

func TestSameVersionIsNotAnUpdate(t *testing.T) {
	srv := newServer(t, "v0.1.0")
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1"}})
	st, _ := u.Check(context.Background())
	if st.Available {
		t.Fatal("same version offered as an update")
	}
	if err := u.Download(context.Background()); err != nil || u.State().Phase != Idle {
		t.Fatalf("downloaded with nothing to update: %v %+v", err, u.State())
	}
}

func TestMinimumMakesItRequired(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	srv.minimum = "0.1.5"
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1"}})
	st, _ := u.Check(context.Background())
	if !st.Required || st.Message == "" || !u.Blocked() {
		t.Fatalf("state %+v", st)
	}
	srv.minimum = "0.1.0"
	st, _ = u.Check(context.Background())
	if st.Required {
		t.Fatal("required although this version meets the minimum")
	}
}

func TestDownloadAndInstall(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1", "new": "TEAM1"}})
	if _, err := u.Check(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := u.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if st := u.State(); st.Phase != Ready || st.Progress != 1 {
		t.Fatalf("state %+v", st)
	}
	if err := u.Install(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(u.App, "Contents", "version"))
	if string(b) != "new" {
		t.Fatalf("app not replaced, has %q", b)
	}
	u.cleanLeftovers()
	left, _ := filepath.Glob(filepath.Join(filepath.Dir(u.App), ".Mothball-*"))
	if len(left) != 0 {
		t.Fatalf("leftovers %v", left)
	}
}

func TestBadChecksumIsRejected(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	srv.sum = "0000000000000000000000000000000000000000000000000000000000000000"
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1", "new": "TEAM1"}})
	_, _ = u.Check(context.Background())
	if err := u.Download(context.Background()); err == nil {
		t.Fatal("accepted a download with the wrong checksum")
	}
	if st := u.State(); st.Phase != Idle || st.Error == "" {
		t.Fatalf("state %+v", st)
	}
}

func TestOtherTeamIsRejected(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{"old": "TEAM1", "new": "SOMEONEELSE"}})
	_, _ = u.Check(context.Background())
	if err := u.Download(context.Background()); err == nil {
		t.Fatal("accepted an app signed by another team")
	}
	b, _ := os.ReadFile(filepath.Join(u.App, "Contents", "version"))
	if string(b) != "old" {
		t.Fatal("running app was touched")
	}
}

func TestUnsignedAppCannotInstall(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newUpdater(t, srv, fakeMac{teams: map[string]string{}})
	st, _ := u.Check(context.Background())
	if st.CanInstall {
		t.Fatal("ad hoc build offered to install updates")
	}
	if err := u.Download(context.Background()); err != ErrCannotInstall {
		t.Fatalf("err = %v", err)
	}
}

type fakeWin struct {
	signers  map[string]string // base name -> subject
	launched []string
}

func (f *fakeWin) Signer(path string) (string, error) { return f.signers[filepath.Base(path)], nil }
func (f *fakeWin) Launch(installer string, args []string) error {
	f.launched = append([]string{installer}, args...)
	return nil
}

func newWinUpdater(t *testing.T, srv *server, win *fakeWin, installed bool) *Updater {
	app := t.TempDir()
	write := func(name string) {
		if err := os.WriteFile(filepath.Join(app, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("Mothball.exe")
	if installed {
		write("unins000.exe")
	}
	u := &Updater{Current: "0.1.0", Dir: t.TempDir(), App: app, API: srv.URL, HTTP: srv.Client(),
		Win: win, GOOS: "windows", GOARCH: "arm64", Now: time.Now}
	u.st = State{Current: u.Current, CanInstall: u.canInstall()}
	return u
}

func TestWindowsUpdateRunsTheInstallerSilently(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	win := &fakeWin{}
	u := newWinUpdater(t, srv, win, true)
	if _, err := u.Check(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := u.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if st := u.State(); st.Phase != Ready {
		t.Fatalf("state %+v", st)
	}
	if err := u.Install(); err != nil {
		t.Fatal(err)
	}
	if len(win.launched) == 0 || filepath.Base(win.launched[0]) != "Mothball-0.2.0-windows-arm64-setup.exe" {
		t.Fatalf("launched %v", win.launched)
	}
	args := strings.Join(win.launched[1:], " ")
	for _, a := range []string{"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/RELAUNCH=1"} {
		if !strings.Contains(args, a) {
			t.Errorf("installer started without %s: %s", a, args)
		}
	}
}

func TestWindowsPortableCopyDoesNotSelfUpdate(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newWinUpdater(t, srv, &fakeWin{}, false)
	st, _ := u.Check(context.Background())
	if st.CanInstall || !st.Available {
		t.Fatalf("state %+v", st)
	}
	if err := u.Download(context.Background()); err != ErrCannotInstall {
		t.Fatalf("err = %v", err)
	}
}

func TestWindowsInstallerFromAnotherPublisherIsRejected(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	win := &fakeWin{signers: map[string]string{
		"Mothball.exe":                           "CN=Hero Momoh",
		"Mothball-0.2.0-windows-arm64-setup.exe": "CN=Someone Else",
	}}
	u := newWinUpdater(t, srv, win, true)
	_, _ = u.Check(context.Background())
	if err := u.Download(context.Background()); err == nil {
		t.Fatal("accepted an installer signed by someone else")
	}
	if len(win.launched) != 0 {
		t.Fatal("ran a rejected installer")
	}
}

func TestWindowsBadChecksumIsRejected(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	srv.sum = strings.Repeat("0", 64)
	u := newWinUpdater(t, srv, &fakeWin{}, true)
	_, _ = u.Check(context.Background())
	if err := u.Download(context.Background()); err == nil {
		t.Fatal("accepted a download with the wrong checksum")
	}
	left, _ := filepath.Glob(filepath.Join(u.Dir, "*.exe"))
	if len(left) != 0 {
		t.Fatalf("bad download left on disk: %v", left)
	}
}

func TestWindowsAppDir(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := windowsAppDirOf(filepath.Join(dir, "bin", "mothballw.exe")); got != "" {
		t.Fatalf("found an app folder with no Mothball.exe: %q", got)
	}
	if err := os.WriteFile(filepath.Join(dir, "Mothball.exe"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if got := windowsAppDirOf(filepath.Join(dir, "bin", "mothballw.exe")); got != dir {
		t.Fatalf("got %q, want %q", got, dir)
	}
	if windowsAppDirOf(filepath.Join(dir, "mothball.exe")) != "" {
		t.Fatal("a CLI outside bin\\ treated as installed")
	}
}

func newLinuxUpdater(t *testing.T, srv *server) *Updater {
	app := filepath.Join(t.TempDir(), "Mothball.AppImage")
	if err := os.WriteFile(app, []byte("old appimage"), 0o755); err != nil {
		t.Fatal(err)
	}
	u := &Updater{Current: "0.1.0", Dir: t.TempDir(), App: app, API: srv.URL, HTTP: srv.Client(),
		GOOS: "linux", GOARCH: "amd64", Now: time.Now}
	u.st = State{Current: u.Current, CanInstall: u.canInstall()}
	return u
}

func TestAppImageUpdateReplacesTheFile(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := newLinuxUpdater(t, srv)
	st, err := u.Check(context.Background())
	if err != nil || !st.CanInstall || !st.Available {
		t.Fatalf("state %+v, %v", st, err)
	}
	if err := u.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if u.State().Phase != Ready {
		t.Fatalf("state %+v", u.State())
	}
	if err := u.Install(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(u.App)
	if string(b) != string(srv.dmg) {
		t.Fatalf("AppImage not replaced, has %q", b)
	}
	if info, _ := os.Stat(u.App); info.Mode()&0o111 == 0 {
		t.Fatal("new AppImage is not executable")
	}
	left, _ := filepath.Glob(filepath.Join(filepath.Dir(u.App), ".Mothball-*"))
	if len(left) != 0 {
		t.Fatalf("leftovers %v", left)
	}
}

func TestAppImageBadChecksumKeepsTheOldFile(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	srv.sum = strings.Repeat("0", 64)
	u := newLinuxUpdater(t, srv)
	_, _ = u.Check(context.Background())
	if err := u.Download(context.Background()); err == nil {
		t.Fatal("accepted a download with the wrong checksum")
	}
	b, _ := os.ReadFile(u.App)
	if string(b) != "old appimage" {
		t.Fatal("running AppImage was touched")
	}
	left, _ := filepath.Glob(filepath.Join(filepath.Dir(u.App), ".Mothball-*"))
	if len(left) != 0 {
		t.Fatalf("bad download left on disk: %v", left)
	}
}

func TestLinuxPackageDoesNotSelfUpdate(t *testing.T) {
	srv := newServer(t, "v0.2.0")
	u := &Updater{Current: "0.1.0", Dir: t.TempDir(), App: "", API: srv.URL, HTTP: srv.Client(),
		GOOS: "linux", GOARCH: "amd64", Now: time.Now}
	u.st = State{Current: u.Current, CanInstall: u.canInstall()}
	st, _ := u.Check(context.Background())
	if st.CanInstall || !st.Available {
		t.Fatalf("state %+v", st)
	}
}

func TestAppImageNames(t *testing.T) {
	if LinuxAppImage("0.1.3", "amd64") != "Mothball-0.1.3-linux-x86_64.AppImage" ||
		LinuxAppImage("0.1.3", "arm64") != "Mothball-0.1.3-linux-aarch64.AppImage" {
		t.Fatal("unexpected AppImage names")
	}
}
