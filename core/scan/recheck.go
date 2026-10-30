package scan

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/herocodess/mothball/core/pack"
)

// Recheck runs every safety check again on one candidate, with fresh git facts,
// immediately before it is moved. Anything may have changed since the scan:
// a commit, a checkout, a new file, the folder itself. Any doubt is a refusal.
func (s *Scanner) Recheck(c Candidate, idleDays int, now time.Time) error {
	if c.Project == "" || c.Output == "" {
		return errors.New("incomplete candidate")
	}
	want := filepath.Join(c.Project, filepath.FromSlash(c.Output))
	if filepath.Clean(c.Path) != want {
		return errors.New("path does not match its project")
	}
	if filepath.Dir(want) == want || want == filepath.Clean(c.Project) {
		return errors.New("refusing to move a root or the project itself")
	}
	var p = s.findPack(c.Pack)
	if p == nil {
		return fmt.Errorf("unknown pack %q", c.Pack)
	}
	var found bool
	for _, o := range p.Outputs {
		if o.Path != c.Output {
			continue
		}
		found = true
		if !s.claims(c.Project, p) {
			return errors.New("project file is gone")
		}
		s.git.forget(c.Project)
		if ok, _ := s.verify(c.Project, want, o); !ok {
			return errors.New("no longer passes the output checks")
		}
	}
	if !found {
		return fmt.Errorf("pack %q has no output %q", c.Pack, c.Output)
	}
	fresh := s.candidate(c.Project, want, c.Output, p, now)
	if fresh.Dirty {
		return errors.New("project has uncommitted work")
	}
	if fresh.IdleDays < idleDays {
		return fmt.Errorf("project was active %d days ago", fresh.IdleDays)
	}
	return nil
}

// claims reports whether dir still contains one of the pack's detect files.
func (s *Scanner) claims(dir string, p *pack.Pack) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, e := range entries {
		for _, q := range s.packs.Match(e.Name()) {
			if q == p {
				return true
			}
		}
	}
	return false
}
