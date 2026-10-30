package service

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/herocodess/mothball/core/config"
)

// Endpoint is how clients find a running service. It is written to
// service.json in the state folder, readable only by the user.
type Endpoint struct {
	URL   string `json:"url"`
	Token string `json:"token"`
	PID   int    `json:"pid"`
}

// EndpointFile is where the endpoint is written.
func EndpointFile(dir string) string { return filepath.Join(dir, "service.json") }

// ReadEndpoint loads the endpoint of a running service, if any.
func ReadEndpoint(dir string) (Endpoint, error) {
	var e Endpoint
	b, err := os.ReadFile(EndpointFile(dir))
	if err != nil {
		return e, err
	}
	return e, json.Unmarshal(b, &e)
}

// Serve listens on 127.0.0.1 on a free port, writes the endpoint file and
// serves until the listener is closed. Every request needs the token.
func (s *Service) Serve() (net.Listener, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	tok := make([]byte, 32)
	if _, err := rand.Read(tok); err != nil {
		ln.Close()
		return nil, err
	}
	ep := Endpoint{URL: "http://" + ln.Addr().String(), Token: hex.EncodeToString(tok), PID: os.Getpid()}
	b, _ := json.MarshalIndent(ep, "", "  ")
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		ln.Close()
		return nil, err
	}
	tmp := EndpointFile(s.Dir) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	if err := os.Rename(tmp, EndpointFile(s.Dir)); err != nil {
		ln.Close()
		return nil, err
	}
	srv := &http.Server{Handler: s.Handler(ep.Token, ln.Addr().String()), ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = srv.Serve(ln) }()
	return ln, nil
}

// Handler is the API. host is the only Host header accepted, which blocks
// web pages from reaching it through DNS tricks.
func (s *Service) Handler(token, host string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/status", func(w http.ResponseWriter, r *http.Request) {
		st, err := s.Status()
		reply(w, st, err)
	})
	mux.HandleFunc("POST /v1/scan", func(w http.ResponseWriter, r *http.Request) {
		sum, err := s.Scan()
		reply(w, sum, err)
	})
	mux.HandleFunc("POST /v1/clean", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Paths []string `json:"paths"`
		}
		if !decode(w, r, &req) {
			return
		}
		out, err := s.Clean(req.Paths)
		type result struct {
			Path  string `json:"path"`
			Bytes int64  `json:"bytes"`
			Moved bool   `json:"moved"`
			Note  string `json:"note,omitempty"`
		}
		var res []result
		for _, o := range out {
			x := result{Path: o.Candidate.Path, Bytes: o.Candidate.Bytes, Moved: o.Err == nil}
			if o.Err != nil {
				x.Note = o.Err.Error()
			}
			res = append(res, x)
		}
		reply(w, res, err)
	})
	mux.HandleFunc("POST /v1/wake", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Project string `json:"project"`
		}
		if !decode(w, r, &req) {
			return
		}
		err := s.Wake(req.Project)
		if errors.Is(err, ErrNotMothballed) {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		reply(w, map[string]bool{"ok": err == nil}, err)
	})
	mux.HandleFunc("GET /v1/config", func(w http.ResponseWriter, r *http.Request) {
		c, err := s.Config()
		reply(w, c, err)
	})
	mux.HandleFunc("PUT /v1/config", func(w http.ResponseWriter, r *http.Request) {
		var c config.Config
		if !decode(w, r, &c) {
			return
		}
		saved, err := s.SetConfig(c)
		reply(w, saved, err)
	})

	want := []byte("Bearer " + token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != host {
			http.Error(w, "wrong host", http.StatusForbidden)
			return
		}
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), want) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(w, r)
	})
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "send JSON", http.StatusUnsupportedMediaType)
		return false
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	if err := dec.Decode(v); err != nil {
		http.Error(w, fmt.Sprintf("bad request: %v", err), http.StatusBadRequest)
		return false
	}
	return true
}

func reply(w http.ResponseWriter, v any, err error) {
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
