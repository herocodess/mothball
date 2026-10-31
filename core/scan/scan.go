// Package scan finds generated output in projects and proves it is safe to
// remove. It only reads; nothing here moves or deletes anything.
package scan

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/herocodess/mothball/core/access"
	"github.com/herocodess/mothball/core/pack"
)

// IgnoreFile in a project folder keeps Mothball out of it and everything below.
const IgnoreFile = ".mothballignore"

// Candidate is one output folder that passed every safety check.
type Candidate struct {
	Path     string    `json:"path"`
	Project  string    `json:"project"`
	Pack     string    `json:"pack"`
	Output   string    `json:"output"` // the pack's output path, relative to Project
	Bytes    int64     `json:"bytes"`
	LastWork time.Time `json:"lastWork"`
	IdleDays int       `json:"idleDays"`
	InGit    bool      `json:"inGit"`
	Dirty    bool      `json:"dirty"`
	Wake     string    `json:"wake"`
}

// Options controls a scan.
type Options struct {
	Roots       []string
	Home        string
	Now         time.Time
	Concurrency int
	// Skip lists folders to leave out, such as privacy-guarded ones. A root
	// inside a skipped folder is still scanned: the user asked for it.
	Skip []string
}

// Result is what a scan found.
type Result struct {
	Candidates []Candidate `json:"candidates"`
	Projects   int         `json:"projects"`
	Skipped    int         `json:"skipped"` // folders that looked like output but failed a check
}

// Scanner walks folders using a set of rule packs.
type Scanner struct {
	packs *pack.Set
	guard *Guard
	git   *gitRunner
}

// New makes a scanner.
func New(packs *pack.Set, home string) *Scanner {
	return &Scanner{packs: packs, guard: NewGuard(home), git: newGitRunner()}
}

// Scan walks every root and returns verified candidates, largest first.
func (s *Scanner) Scan(opt Options) Result {
	if opt.Now.IsZero() {
		opt.Now = time.Now()
	}
	if opt.Concurrency <= 0 {
		opt.Concurrency = 8
	}
	var res Result
	seen := map[string]bool{}
	for _, root := range opt.Roots {
		abs, err := filepath.Abs(root)
		if err != nil {
			continue
		}
		skip := map[string]bool{}
		for _, p := range access.SkipFor(abs, opt.Skip) {
			skip[normalize(p)] = true
		}
		s.walk(abs, opt.Now, &res, seen, skip)
	}
	s.measure(res.Candidates, opt.Concurrency)
	sort.Slice(res.Candidates, func(i, j int) bool {
		return res.Candidates[i].Bytes > res.Candidates[j].Bytes
	})
	return res
}

func (s *Scanner) walk(dir string, now time.Time, res *Result, seen, skip map[string]bool) {
	if s.guard.Denied(dir) || skip[normalize(dir)] {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	names := make(map[string]fs.DirEntry, len(entries))
	for _, e := range entries {
		names[e.Name()] = e
	}
	if _, ok := names[IgnoreFile]; ok {
		return
	}

	// Which packs claim this folder as a project?
	claimed := map[string]bool{} // output folders taken by a pack, never walked into
	var matched []*pack.Pack
	dedupe := map[string]bool{}
	for name := range names {
		for _, p := range s.packs.Match(name) {
			if !dedupe[p.ID] {
				dedupe[p.ID] = true
				matched = append(matched, p)
			}
		}
	}
	sort.Slice(matched, func(i, j int) bool { return matched[i].ID < matched[j].ID })

	if len(matched) > 0 {
		res.Projects++
		for _, p := range matched {
			for _, out := range p.Outputs {
				full := filepath.Join(dir, filepath.FromSlash(out.Path))
				if seen[full] {
					continue
				}
				ok, isDir := s.verify(dir, full, out)
				if isDir {
					claimed[full] = true
				}
				if !ok {
					if isDir {
						res.Skipped++
					}
					continue
				}
				seen[full] = true
				res.Candidates = append(res.Candidates, s.candidate(dir, full, out.Path, p, now))
			}
		}
	}

	for _, e := range entries {
		if !e.IsDir() { // symlinks report false here, so links are never followed
			continue
		}
		child := filepath.Join(dir, e.Name())
		if neverDescend[e.Name()] || claimed[child] {
			continue
		}
		s.walk(child, now, res, seen, skip)
	}
}

// verify runs every check an output must pass. isDir says whether the folder
// exists at all, so the walker knows not to search inside it either way.
func (s *Scanner) verify(project, full string, out pack.Output) (ok bool, isDir bool) {
	info, err := os.Lstat(full)
	if err != nil || !info.IsDir() || info.Mode()&fs.ModeSymlink != 0 {
		return false, false
	}
	if s.guard.Denied(full) {
		return false, true
	}
	if !anyExists(full, out.RequireAny) {
		return false, true
	}
	if len(out.RequireSibling) > 0 && !anyExists(project, out.RequireSibling) {
		return false, true
	}
	g := s.git.project(project)
	if g.inRepo && s.git.tracked(project, filepath.ToSlash(out.Path)) {
		return false, true
	}
	return true, true
}

func (s *Scanner) candidate(project, full, rel string, p *pack.Pack, now time.Time) Candidate {
	g := s.git.project(project)
	last := g.lastCommit
	if last.IsZero() {
		last = newestManifest(project, p)
	}
	idle := 0
	if !last.IsZero() && now.After(last) {
		idle = int(now.Sub(last).Hours() / 24)
	}
	return Candidate{
		Path:     full,
		Project:  project,
		Pack:     p.ID,
		Output:   rel,
		LastWork: last,
		IdleDays: idle,
		InGit:    g.inRepo,
		Dirty:    g.dirty,
		Wake:     wakeCommand(project, p),
	}
}

func (s *Scanner) findPack(id string) *pack.Pack {
	for _, p := range s.packs.Packs {
		if p.ID == id {
			return p
		}
	}
	return nil
}

func anyExists(dir string, names []string) bool {
	for _, n := range names {
		if _, err := os.Lstat(filepath.Join(dir, filepath.FromSlash(n))); err == nil {
			return true
		}
	}
	return false
}

// newestManifest is the fallback idle clock for projects without commits: the
// newest change to the files that define the project, not its output.
func newestManifest(project string, p *pack.Pack) time.Time {
	var newest time.Time
	for _, d := range p.Detect {
		if info, err := os.Stat(filepath.Join(project, d)); err == nil && info.ModTime().After(newest) {
			newest = info.ModTime()
		}
	}
	for _, w := range p.Wake {
		if w.When == "" {
			continue
		}
		if info, err := os.Stat(filepath.Join(project, w.When)); err == nil && info.ModTime().After(newest) {
			newest = info.ModTime()
		}
	}
	return newest
}

func wakeCommand(project string, p *pack.Pack) string {
	for _, w := range p.Wake {
		if w.When == "" || anyExists(project, []string{w.When}) {
			return w.Command()
		}
	}
	return ""
}

// measure fills in sizes, a few folders at a time.
func (s *Scanner) measure(cs []Candidate, workers int) {
	var wg sync.WaitGroup
	sem := make(chan struct{}, workers)
	for i := range cs {
		wg.Add(1)
		sem <- struct{}{}
		go func(c *Candidate) {
			defer wg.Done()
			defer func() { <-sem }()
			c.Bytes = dirSize(c.Path)
		}(&cs[i])
	}
	wg.Wait()
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
