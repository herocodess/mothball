// Package update checks GitHub for new Mothball releases and, on macOS,
// installs them in place: download, verify, swap the app, restart.
//
// A release can also say that older versions must update before Mothball
// moves anything again, by shipping an update.json asset:
//
//	{"minimum": "0.1.3", "message": "0.1.2 could misread Gradle projects."}
//
// That is the safety switch for a tool that moves files: it is used only when
// a version has a bug that could put away the wrong thing.
package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Repo is where releases are published.
const Repo = "herocodess/mothball"

// Phase is where an update is in its lifecycle.
type Phase string

const (
	Idle        Phase = ""
	Checking    Phase = "checking"
	Downloading Phase = "downloading"
	Ready       Phase = "ready" // downloaded and verified, waiting for a restart
	Installing  Phase = "installing"
)

// State is what the app and menu bar show.
type State struct {
	Current   string `json:"current"`
	Latest    string `json:"latest,omitempty"`
	Available bool   `json:"available"`
	// Required means this version must update before Mothball moves files.
	Required bool   `json:"required"`
	Message  string `json:"message,omitempty"`
	NotesURL string `json:"notesUrl,omitempty"`
	// Notes are the release notes (Markdown) of the latest version.
	Notes       string    `json:"notes,omitempty"`
	PublishedAt time.Time `json:"publishedAt,omitzero"`
	// CanInstall is true when Mothball can install the update itself (the
	// macOS app in a folder it can write to). Otherwise the app links to the
	// download page.
	CanInstall bool      `json:"canInstall"`
	Phase      Phase     `json:"phase"`
	Progress   float64   `json:"progress"` // 0..1 while downloading
	CheckedAt  time.Time `json:"checkedAt,omitzero"`
	Error      string    `json:"error,omitempty"`
}

// Release is the part of GitHub's release JSON that Mothball reads.
type Release struct {
	Tag       string    `json:"tag_name"`
	HTMLURL   string    `json:"html_url"`
	Body      string    `json:"body"`
	Published time.Time `json:"published_at"`
	Draft     bool      `json:"draft"`
	Pre       bool      `json:"prerelease"`
	Assets    []struct {
		Name string `json:"name"`
		URL  string `json:"browser_download_url"`
		Size int64  `json:"size"`
	} `json:"assets"`
}

func (r Release) asset(name string) (string, int64, bool) {
	for _, a := range r.Assets {
		if a.Name == name {
			return a.URL, a.Size, true
		}
	}
	return "", 0, false
}

// Manifest is the optional update.json asset of a release.
type Manifest struct {
	Minimum string `json:"minimum"`
	Message string `json:"message"`
}

// Updater keeps the update state for one running service.
type Updater struct {
	Current string // this build's version
	Dir     string // where downloads are kept
	// App is the Mothball.app this service runs from, or "" when it does
	// not run from an app bundle (the CLI on its own, Windows, Linux).
	App string
	// API is the GitHub API base URL.
	API string

	HTTP *http.Client
	Mac  Mac // swappable for tests
	Now  func() time.Time

	mu      sync.Mutex
	st      State
	release Release
	staged  string // verified new app, next to App
}

// New makes an updater for the running build.
func New(current, dir string) *Updater {
	u := &Updater{Current: current, Dir: dir, API: "https://api.github.com", HTTP: &http.Client{Timeout: 30 * time.Second}, Now: time.Now, Mac: realMac{}}
	if runtime.GOOS == "darwin" {
		u.App = AppBundle()
	}
	u.st = State{Current: current, CanInstall: u.canInstall()}
	u.cleanLeftovers()
	return u
}

// State returns the current state.
func (u *Updater) State() State {
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.st
}

// Blocked reports whether this version must update before it moves files.
func (u *Updater) Blocked() bool {
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.st.Required
}

func (u *Updater) set(f func(*State)) {
	u.mu.Lock()
	f(&u.st)
	u.mu.Unlock()
}

// Check asks GitHub for the latest release. It never downloads anything.
func (u *Updater) Check(ctx context.Context) (State, error) {
	u.mu.Lock()
	if u.st.Phase == Downloading || u.st.Phase == Installing {
		st := u.st
		u.mu.Unlock()
		return st, nil
	}
	u.st.Phase = Checking
	u.mu.Unlock()

	rel, err := u.latest(ctx)
	if err != nil {
		u.set(func(s *State) { s.Phase, s.Error, s.CheckedAt = Idle, "Couldn't check for updates", u.Now() })
		return u.State(), err
	}
	var man Manifest
	if url, _, ok := rel.asset("update.json"); ok {
		_ = u.getJSON(ctx, url, &man) // a missing manifest only means "not required"
	}
	latest := strings.TrimPrefix(rel.Tag, "v")
	u.mu.Lock()
	defer u.mu.Unlock()
	u.release = rel
	u.st.Latest = latest
	u.st.NotesURL = rel.HTMLURL
	u.st.Notes = rel.Body
	if len(u.st.Notes) > 20000 {
		u.st.Notes = u.st.Notes[:20000]
	}
	u.st.PublishedAt = rel.Published
	u.st.CheckedAt = u.Now()
	u.st.Error = ""
	u.st.Available = Newer(latest, u.Current)
	u.st.Required = u.st.Available && man.Minimum != "" && Newer(man.Minimum, u.Current)
	u.st.Message = ""
	if u.st.Required {
		u.st.Message = man.Message
	}
	if u.st.Phase == Checking {
		u.st.Phase = Idle
	}
	if u.st.Phase == Ready && u.staged != "" && !strings.Contains(filepath.Base(u.staged), latest) {
		// A newer release came out after the last one was downloaded.
		_ = os.RemoveAll(u.staged)
		u.staged, u.st.Phase = "", Idle
	}
	return u.st, nil
}

func (u *Updater) latest(ctx context.Context) (Release, error) {
	var rel Release
	err := u.getJSON(ctx, u.API+"/repos/"+Repo+"/releases/latest", &rel)
	if err == nil && (rel.Tag == "" || rel.Draft || rel.Pre) {
		err = errors.New("no published release")
	}
	return rel, err
}

func (u *Updater) getJSON(ctx context.Context, url string, v any) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "Mothball/"+u.Current)
	resp, err := u.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s: %s", url, resp.Status)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(v)
}

// ErrCannotInstall means this copy of Mothball cannot replace itself; the
// app should send the user to the download page instead.
var ErrCannotInstall = errors.New("this copy of Mothball can't update itself")

// Download fetches the new version, checks it and stages it next to the
// running app. It reports progress through State.
func (u *Updater) Download(ctx context.Context) error {
	u.mu.Lock()
	if !u.st.CanInstall {
		u.mu.Unlock()
		return ErrCannotInstall
	}
	if !u.st.Available || u.st.Phase == Downloading || u.st.Phase == Ready || u.st.Phase == Installing {
		u.mu.Unlock()
		return nil
	}
	rel, latest := u.release, u.st.Latest
	u.st.Phase, u.st.Progress, u.st.Error = Downloading, 0, ""
	u.mu.Unlock()

	staged, err := u.download(ctx, rel, latest)
	u.mu.Lock()
	defer u.mu.Unlock()
	if err != nil {
		u.st.Phase, u.st.Error = Idle, "The update didn't download: "+err.Error()
		return err
	}
	u.staged, u.st.Phase, u.st.Progress = staged, Ready, 1
	return nil
}

func (u *Updater) download(ctx context.Context, rel Release, version string) (string, error) {
	name := "Mothball-" + version + ".dmg"
	url, size, ok := rel.asset(name)
	if !ok {
		return "", fmt.Errorf("release has no %s", name)
	}
	sums, err := u.checksums(ctx, rel, version)
	if err != nil {
		return "", err
	}
	want, ok := sums[name]
	if !ok {
		return "", fmt.Errorf("no checksum for %s", name)
	}
	if err := os.MkdirAll(u.Dir, 0o700); err != nil {
		return "", err
	}
	dmg := filepath.Join(u.Dir, name)
	if err := u.fetch(ctx, url, size, dmg); err != nil {
		return "", err
	}
	defer os.Remove(dmg)
	if got, err := fileSHA256(dmg); err != nil {
		return "", err
	} else if got != want {
		return "", errors.New("checksum does not match the release")
	}
	staged := filepath.Join(filepath.Dir(u.App), ".Mothball-"+version+".app")
	_ = os.RemoveAll(staged)
	if err := u.Mac.Extract(dmg, staged); err != nil {
		_ = os.RemoveAll(staged)
		return "", err
	}
	if err := u.verify(staged); err != nil {
		_ = os.RemoveAll(staged)
		return "", err
	}
	return staged, nil
}

func (u *Updater) checksums(ctx context.Context, rel Release, version string) (map[string]string, error) {
	url, _, ok := rel.asset("checksums-" + version + ".txt")
	if !ok {
		return nil, errors.New("release has no checksums file")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := u.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("checksums: %s", resp.Status)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	return ParseChecksums(string(b)), nil
}

// ParseChecksums reads shasum output: "<hex>  <name>" per line.
func ParseChecksums(s string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(s, "\n") {
		f := strings.Fields(line)
		if len(f) == 2 && len(f[0]) == 64 {
			out[strings.TrimPrefix(f[1], "*")] = strings.ToLower(f[0])
		}
	}
	return out
}

func (u *Updater) fetch(ctx context.Context, url string, size int64, dest string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "Mothball/"+u.Current)
	client := *u.HTTP
	client.Timeout = 15 * time.Minute
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("download: %s", resp.Status)
	}
	if size <= 0 {
		size = resp.ContentLength
	}
	f, err := os.OpenFile(dest, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	var got int64
	buf := make([]byte, 256<<10)
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, err := f.Write(buf[:n]); err != nil {
				return err
			}
			got += int64(n)
			if size > 0 {
				p := float64(got) / float64(size)
				u.set(func(s *State) { s.Progress = min(p, 0.99) })
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return rerr
		}
	}
	return f.Close()
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// verify accepts a new app only if it is validly signed, accepted by
// Gatekeeper, and signed by the same developer team as the running app.
func (u *Updater) verify(app string) error {
	want, err := u.Mac.Team(u.App)
	if err != nil || want == "" {
		return errors.New("the running app is not signed by a developer team")
	}
	got, err := u.Mac.Team(app)
	if err != nil {
		return err
	}
	if got != want {
		return fmt.Errorf("the update is signed by %q, not %q", got, want)
	}
	return u.Mac.Verify(app)
}

// Install swaps the staged app in for the running one. The caller then
// relaunches the app and restarts the service, which now runs the new code.
func (u *Updater) Install() error {
	u.mu.Lock()
	if u.st.Phase != Ready || u.staged == "" {
		u.mu.Unlock()
		return errors.New("no update is ready to install")
	}
	staged := u.staged
	u.st.Phase = Installing
	u.mu.Unlock()

	err := u.swap(staged)
	u.mu.Lock()
	defer u.mu.Unlock()
	if err != nil {
		u.st.Phase, u.st.Error = Idle, "The update couldn't be installed: "+err.Error()
		u.staged = ""
		_ = os.RemoveAll(staged)
		return err
	}
	return nil
}

func (u *Updater) swap(staged string) error {
	if err := u.verify(staged); err != nil { // again: it sat on disk meanwhile
		return err
	}
	old := filepath.Join(filepath.Dir(u.App), fmt.Sprintf(".Mothball-old-%d.app", u.Now().Unix()))
	if err := os.Rename(u.App, old); err != nil {
		return err
	}
	if err := os.Rename(staged, u.App); err != nil {
		_ = os.Rename(old, u.App)
		return err
	}
	// The running service still executes from the old copy, which is fine
	// until it restarts; the leftover is removed then (cleanLeftovers).
	return nil
}

// cleanLeftovers removes staged or replaced copies from earlier updates.
func (u *Updater) cleanLeftovers() {
	if u.App == "" {
		return
	}
	matches, _ := filepath.Glob(filepath.Join(filepath.Dir(u.App), ".Mothball-*.app"))
	for _, m := range matches {
		_ = os.RemoveAll(m)
	}
}

func (u *Updater) canInstall() bool {
	if u.App == "" {
		return false
	}
	dir := filepath.Dir(u.App)
	if strings.HasPrefix(dir, "/Volumes/") || strings.Contains(u.App, "/AppTranslocation/") {
		return false // running from the DMG or a quarantined copy
	}
	f, err := os.CreateTemp(dir, ".mothball-write-test-")
	if err != nil {
		return false
	}
	name := f.Name()
	f.Close()
	os.Remove(name)
	team, err := u.Mac.Team(u.App)
	return err == nil && team != ""
}

// AppBundle is Mothball.app when this binary runs from inside it, at
// Mothball.app/Contents/Library/LoginItems/Mothball Agent.app/Contents/MacOS.
func AppBundle() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	exe, _ = filepath.EvalSymlinks(exe)
	return bundleOf(exe)
}

func bundleOf(exe string) string {
	const marker = "/Contents/Library/LoginItems/"
	if i := strings.Index(exe, marker); i > 0 && strings.HasSuffix(exe[:i], ".app") {
		return exe[:i]
	}
	return ""
}

// Newer reports whether version a is newer than b. Versions are dotted
// numbers with an optional "v" prefix; anything after "-" or "+" marks a
// pre-release, which sorts before the release it precedes.
func Newer(a, b string) bool {
	pa, preA := parse(a)
	pb, preB := parse(b)
	for i := 0; i < 3; i++ {
		if pa[i] != pb[i] {
			return pa[i] > pb[i]
		}
	}
	return preB && !preA
}

func parse(v string) ([3]int, bool) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	pre := false
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		pre = v[i] == '-'
		v = v[:i]
	}
	var out [3]int
	for i, part := range strings.SplitN(v, ".", 3) {
		n, _ := strconv.Atoi(part)
		out[i] = n
	}
	return out, pre
}
