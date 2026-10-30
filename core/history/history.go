// Package history keeps a log of every folder Mothball has put away: where it
// was, where it went and how to bring the project back. Unmothball reads it.
package history

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Entry is one folder put away.
type Entry struct {
	Time     time.Time `json:"time"`
	Original string    `json:"original"`
	Trashed  string    `json:"trashed"`
	Project  string    `json:"project"`
	Pack     string    `json:"pack"`
	Bytes    int64     `json:"bytes"`
	Wake     string    `json:"wake"`
}

// Log is an append-only JSON Lines file.
type Log struct {
	path string
	mu   sync.Mutex
}

// DefaultDir is where Mothball keeps its own state on this system.
func DefaultDir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "mothball"), nil
}

// Open returns the log in dir, creating the folder if needed.
func Open(dir string) (*Log, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	return &Log{path: filepath.Join(dir, "history.jsonl")}, nil
}

// Append adds one entry and syncs it to disk before returning, so a crash
// right after a move never loses the record of it.
func (l *Log) Append(e Entry) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	f, err := os.OpenFile(l.path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(e)
	if err != nil {
		return err
	}
	if _, err := f.Write(append(b, '\n')); err != nil {
		return err
	}
	return f.Sync()
}

// All returns every entry, oldest first. Unreadable lines are skipped.
func (l *Log) All() ([]Entry, error) {
	f, err := os.Open(l.path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []Entry
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		var e Entry
		if json.Unmarshal(sc.Bytes(), &e) == nil {
			out = append(out, e)
		}
	}
	return out, sc.Err()
}
