package scan

import (
	"bytes"
	"github.com/herocodess/mothball/core/proc"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// gitRunner wraps the git command. Mothball reads git, it never writes to it.
type gitRunner struct {
	bin   string
	mu    sync.Mutex
	cache map[string]projectGit
}

type projectGit struct {
	inRepo     bool
	lastCommit time.Time // zero when the path has no commits yet
	dirty      bool      // uncommitted changes to tracked files
}

func newGitRunner() *gitRunner {
	bin, err := exec.LookPath("git")
	if err != nil {
		bin = ""
	}
	return &gitRunner{bin: bin, cache: map[string]projectGit{}}
}

func (g *gitRunner) run(dir string, args ...string) (string, bool) {
	if g.bin == "" {
		return "", false
	}
	cmd := proc.Command(g.bin, append([]string{"-C", dir}, args...)...)
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return "", false
	}
	return strings.TrimSpace(out.String()), true
}

// project returns git facts for a project folder, cached per folder.
func (g *gitRunner) project(dir string) projectGit {
	g.mu.Lock()
	if v, ok := g.cache[dir]; ok {
		g.mu.Unlock()
		return v
	}
	g.mu.Unlock()

	var info projectGit
	if out, ok := g.run(dir, "rev-parse", "--is-inside-work-tree"); ok && out == "true" {
		info.inRepo = true
		// Last commit touching this folder, so one busy app in a monorepo does
		// not keep its idle siblings looking active.
		if ts, ok := g.run(dir, "log", "-1", "--format=%ct", "--", "."); ok && ts != "" {
			if secs, err := strconv.ParseInt(ts, 10, 64); err == nil {
				info.lastCommit = time.Unix(secs, 0)
			}
		}
		if st, ok := g.run(dir, "status", "--porcelain", "--untracked-files=no", "--", "."); ok && st != "" {
			info.dirty = true
		}
	}

	g.mu.Lock()
	g.cache[dir] = info
	g.mu.Unlock()
	return info
}

// forget drops cached facts for dir, so the next question asks git again.
func (g *gitRunner) forget(dir string) {
	g.mu.Lock()
	delete(g.cache, dir)
	g.mu.Unlock()
}

// tracked reports whether git tracks anything at or under rel inside dir.
// When git cannot answer, it says yes, so the folder is left alone.
func (g *gitRunner) tracked(dir, rel string) bool {
	out, ok := g.run(dir, "ls-files", "--", rel)
	if !ok {
		return true
	}
	return out != ""
}
