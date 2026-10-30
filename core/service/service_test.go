package service

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/herocodess/mothball/core/config"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/rules"
)

type fakeTrash struct{ dir string }

func (f fakeTrash) Trash(p string) (string, error) {
	dest := filepath.Join(f.dir, filepath.Base(filepath.Dir(p))+"-"+filepath.Base(p))
	return dest, os.Rename(p, dest)
}

// project makes a flutter project whose build folder is size bytes, idle for days.
func project(t *testing.T, home, name string, size int, days int) string {
	t.Helper()
	dir := filepath.Join(home, name)
	if err := os.MkdirAll(filepath.Join(dir, "build", "flutter_assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "build", "flutter_assets", "blob"), make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
	spec := filepath.Join(dir, "pubspec.yaml")
	if err := os.WriteFile(spec, []byte("name: x"), 0o644); err != nil {
		t.Fatal(err)
	}
	old := time.Now().AddDate(0, 0, -days)
	if err := os.Chtimes(spec, old, old); err != nil {
		t.Fatal(err)
	}
	return filepath.Join(dir, "build")
}

func newService(t *testing.T, free uint64) (*Service, string) {
	t.Helper()
	ps, err := pack.Load(rules.Files)
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	s, err := New(t.TempDir(), home, ps)
	if err != nil {
		t.Fatal(err)
	}
	s.Free = func(string) (uint64, error) { return free, nil }
	s.Trash = fakeTrash{t.TempDir()}
	return s, home
}

func TestAutopilotOffDoesNothing(t *testing.T) {
	s, home := newService(t, 0)
	b := project(t, home, "a", 1000, 100)
	s.Tick()
	if _, err := os.Stat(b); err != nil {
		t.Fatal("autopilot moved something while off")
	}
}

func TestAutopilotTakesLongestIdleUntilCovered(t *testing.T) {
	// Target 1 GB, 1 GB minus 1500 bytes free: needs 1500 bytes.
	s, home := newService(t, 1<<30-1500)
	c := config.Default()
	c.Autopilot, c.TargetFreeGB, c.IdleDays = true, 1, 30
	if _, err := s.SetConfig(c); err != nil {
		t.Fatal(err)
	}
	oldest := project(t, home, "oldest", 1000, 300)
	older := project(t, home, "older", 1000, 200)
	old := project(t, home, "old", 1000, 100)
	active := project(t, home, "active", 5000, 1)

	s.Tick()
	gone := func(p string) bool { _, err := os.Stat(p); return os.IsNotExist(err) }
	if !gone(oldest) || !gone(older) {
		t.Error("longest-idle output not put away first")
	}
	if gone(old) {
		t.Error("took more than the shortfall needed")
	}
	if gone(active) {
		t.Error("touched an active project")
	}
	st, _ := s.Status()
	if len(st.Events) == 0 || st.Events[len(st.Events)-1].Bytes != 2000 {
		t.Errorf("events = %+v", st.Events)
	}
}

func TestAutopilotCountsWaitingTrash(t *testing.T) {
	s, home := newService(t, 1<<30-1500)
	c := config.Default()
	c.Autopilot, c.TargetFreeGB, c.IdleDays, c.AutoEmptyDays = true, 1, 30, 7
	_, _ = s.SetConfig(c)
	project(t, home, "a", 1000, 300)
	project(t, home, "b", 1000, 200)
	s.Tick() // puts both away: 2000 bytes waiting for auto-empty
	c2 := project(t, home, "c", 1000, 100)
	s.Tick() // free space unchanged, but the waiting 2000 covers the 1500 gap
	if _, err := os.Stat(c2); err != nil {
		t.Fatal("kept trashing even though waiting space covers the gap")
	}
}

func TestAPINeedsTokenAndHost(t *testing.T) {
	s, _ := newService(t, 1<<40)
	h := s.Handler("secret", "127.0.0.1:9")

	do := func(method, path, host, auth string, body any) int {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		r := httptest.NewRequest(method, path, &buf)
		r.Host = host
		if auth != "" {
			r.Header.Set("Authorization", auth)
		}
		if body != nil {
			r.Header.Set("Content-Type", "application/json")
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w.Code
	}
	if c := do("GET", "/v1/status", "127.0.0.1:9", "", nil); c != http.StatusUnauthorized {
		t.Errorf("no token: %d", c)
	}
	if c := do("GET", "/v1/status", "evil.example:9", "Bearer secret", nil); c != http.StatusForbidden {
		t.Errorf("wrong host: %d", c)
	}
	if c := do("GET", "/v1/status", "127.0.0.1:9", "Bearer secret", nil); c != http.StatusOK {
		t.Errorf("good request: %d", c)
	}
	cfg := config.Default()
	cfg.TargetFreeGB = 80
	if c := do("PUT", "/v1/config", "127.0.0.1:9", "Bearer secret", cfg); c != http.StatusOK {
		t.Errorf("put config: %d", c)
	}
	if got, _ := s.Config(); got.TargetFreeGB != 80 {
		t.Errorf("config not saved: %+v", got)
	}
}

func TestServeWritesPrivateEndpoint(t *testing.T) {
	s, _ := newService(t, 1<<40)
	ln, err := s.Serve()
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	ep, err := ReadEndpoint(s.Dir)
	if err != nil || ep.Token == "" {
		t.Fatalf("endpoint: %+v %v", ep, err)
	}
	if info, _ := os.Stat(EndpointFile(s.Dir)); runtime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
		t.Errorf("endpoint file is readable by others: %v", info.Mode())
	}
	req, _ := http.NewRequest("GET", ep.URL+"/v1/status", nil)
	req.Header.Set("Authorization", "Bearer "+ep.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}
