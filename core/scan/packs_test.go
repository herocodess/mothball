package scan

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/herocodess/mothball/core/pack"
)

// detectName turns a detect entry into a concrete file name for a fixture.
func detectName(d string) string { return strings.ReplaceAll(d, "*", "fixture") }

// Every output of every pack is found when its markers are present, and left
// alone when a folder of the same name holds anything else. New packs are
// covered by this test the moment they are added.
func TestEveryPackOutput(t *testing.T) {
	ps := packs(t)
	for _, p := range ps.Packs {
		for _, d := range p.Detect {
			for _, out := range p.Outputs {
				p, d, out := p, d, out
				t.Run(p.ID+"/"+detectName(d)+"/"+out.Path, func(t *testing.T) {
					check(t, ps, d, out, true)
					check(t, ps, d, out, false)
				})
			}
		}
	}
}

func check(t *testing.T, ps *pack.Set, detect string, out pack.Output, real bool) {
	t.Helper()
	home := t.TempDir()
	proj := filepath.Join(home, "proj")
	files := []string{detectName(detect)}
	outDir := filepath.Join(proj, filepath.FromSlash(out.Path))
	if real {
		files = append(files, filepath.ToSlash(filepath.Join(out.Path, out.RequireAny[0], "x")))
		if len(out.RequireSibling) > 0 {
			files = append(files, out.RequireSibling[0])
		}
	} else {
		// Same folder name and the same siblings, but source inside.
		files = append(files, filepath.ToSlash(filepath.Join(out.Path, "main.src")))
		if len(out.RequireSibling) > 0 {
			files = append(files, out.RequireSibling[0])
		}
	}
	touch(t, proj, files...)

	res := New(ps, home).Scan(Options{Roots: []string{home}, Home: home})
	found := false
	for _, c := range res.Candidates {
		if c.Path == outDir {
			found = true
		}
	}
	if real && !found {
		t.Errorf("real output %s not found", out.Path)
	}
	if !real && found {
		t.Errorf("source folder %s was treated as output", out.Path)
	}
}

// Every pack's markers must be specific: a pack whose requireAny is only a
// very common name would match source.
func TestMarkersAreSpecific(t *testing.T) {
	tooCommon := map[string]bool{"src": true, "lib": true, "main": true, "index.js": true, "README.md": true, "x": true}
	for _, p := range packs(t).Packs {
		for _, out := range p.Outputs {
			for _, m := range out.RequireAny {
				if tooCommon[m] {
					t.Errorf("pack %s output %s uses the common marker %q", p.ID, out.Path, m)
				}
			}
		}
	}
}
