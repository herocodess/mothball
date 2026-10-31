// Package wake is Unmothball: it knows which projects have output put away,
// notices when you come back to one, and restores it with the stack's own
// install or build command.
package wake

import (
	"github.com/herocodess/mothball/core/proc"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/pack"
)

// Project is one project with output currently put away.
type Project struct {
	Path     string          `json:"path"`
	Since    time.Time       `json:"since"`    // when the oldest missing output was put away
	Bytes    int64           `json:"bytes"`    // size of what was put away
	Missing  []string        `json:"missing"`  // output folders not back yet
	Returned bool            `json:"returned"` // you have worked on it since
	Commands []string        `json:"commands"` // what wake will run, from the current rule packs
	entries  []history.Entry // the trashed entries still missing
}

// Mothballed lists projects whose put-away output has not come back.
// Commands come from the current rule packs, never from the history file.
func Mothballed(entries []history.Entry, packs *pack.Set) []Project {
	lastWoke := map[string]time.Time{}
	for _, e := range entries {
		if e.Kind() == history.Woke && e.Time.After(lastWoke[e.Project]) {
			lastWoke[e.Project] = e.Time
		}
	}
	byProject := map[string]*Project{}
	seenOriginal := map[string]bool{}
	for i := len(entries) - 1; i >= 0; i-- { // newest first, so each folder counts once
		e := entries[i]
		if e.Kind() != history.Trashed || seenOriginal[e.Original] {
			continue
		}
		seenOriginal[e.Original] = true
		if !e.Time.After(lastWoke[e.Project]) {
			continue
		}
		if _, err := os.Lstat(e.Original); err == nil {
			continue // it is back already, rebuilt by hand
		}
		if _, err := os.Stat(e.Project); err != nil {
			continue // the project itself is gone
		}
		p := byProject[e.Project]
		if p == nil {
			p = &Project{Path: e.Project, Since: e.Time}
			byProject[e.Project] = p
		}
		if e.Time.Before(p.Since) {
			p.Since = e.Time
		}
		p.Bytes += e.Bytes
		p.Missing = append(p.Missing, e.Original)
		p.entries = append(p.entries, e)
	}

	var out []Project
	for _, p := range byProject {
		p.Commands = commands(p.Path, p.entries, packs)
		p.Returned = returnedSince(p.Path, p.Since)
		sort.Strings(p.Missing)
		out = append(out, *p)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Returned != out[j].Returned {
			return out[i].Returned
		}
		return out[i].Path < out[j].Path
	})
	return out
}

// commands picks one restore command per pack whose output was put away.
func commands(project string, entries []history.Entry, packs *pack.Set) []string {
	seen := map[string]bool{}
	var out []string
	for _, e := range entries {
		if seen[e.Pack] {
			continue
		}
		seen[e.Pack] = true
		for _, p := range packs.Packs {
			if p.ID != e.Pack {
				continue
			}
			for _, w := range p.Wake {
				if w.When == "" || exists(filepath.Join(project, w.When)) {
					out = append(out, w.Command())
					break
				}
			}
		}
	}
	return out
}

// returnedSince reports whether there has been work in the project since t:
// a newer commit, or a newer change to its top-level files.
func returnedSince(project string, t time.Time) bool {
	if git, err := exec.LookPath("git"); err == nil {
		cmd := proc.Command(git, "-C", project, "log", "-1", "--format=%ct", "--", ".")
		if out, err := cmd.Output(); err == nil {
			if secs, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64); err == nil && time.Unix(secs, 0).After(t) {
				return true
			}
		}
	}
	entries, err := os.ReadDir(project)
	if err != nil {
		return false
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if info, err := e.Info(); err == nil && info.ModTime().After(t.Add(time.Minute)) {
			return true
		}
	}
	return false
}

// Run executes the project's restore commands in its folder, in order, and
// records the wake. It stops at the first command that fails.
func Run(p Project, log interface{ Append(history.Entry) error }, stdout, stderr io.Writer) error {
	// No commands means the stack rebuilds its output on its own (game engines,
	// framework caches): there is nothing to run, only the wake to record.
	for _, c := range p.Commands {
		cmd := shell(c)
		cmd.Dir = p.Path
		cmd.Stdout, cmd.Stderr = stdout, stderr
		if err := cmd.Run(); err != nil {
			return &CommandError{Command: c, Err: err}
		}
	}
	return log.Append(history.Entry{Event: history.Woke, Time: time.Now(), Project: p.Path})
}

// CommandError is a restore command that failed.
type CommandError struct {
	Command string
	Err     error
}

func (e *CommandError) Error() string { return e.Command + ": " + e.Err.Error() }

func shell(c string) *exec.Cmd {
	if runtime.GOOS == "windows" {
		return proc.Command("cmd.exe", "/C", c)
	}
	return proc.Command("/bin/sh", "-c", c)
}

func exists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}
