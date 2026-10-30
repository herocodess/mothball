// Package pack loads rule packs. A pack describes one stack: the file that marks
// a project of that stack, the folders it generates, how to prove a folder really
// is generated output, and how to restore it later.
package pack

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strings"
)

// Pack is one stack's rules.
type Pack struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	Detect  []string `json:"detect"`
	Outputs []Output `json:"outputs"`
	Wake    []Wake   `json:"wake"`
}

// Output is a folder a stack generates, relative to the project folder.
type Output struct {
	// Path is relative to the folder holding the detect file. Always a single
	// folder name or a short relative path, never absolute, never "..".
	Path string `json:"path"`
	// RequireAny lists names, at least one of which must exist directly inside the
	// folder before it counts as output. This is what stops a source folder that
	// happens to be called "build" from ever being touched.
	RequireAny []string `json:"requireAny"`
	// RequireSibling, when set, lists names of which at least one must exist next
	// to the output folder.
	RequireSibling []string `json:"requireSibling,omitempty"`
}

// Wake is one way to restore a project. The first entry whose When file exists
// in the project wins; an entry with no When is the fallback.
type Wake struct {
	When string `json:"when,omitempty"`
	Run  string `json:"run"`
}

// Set is every loaded pack plus an index from detect file name to packs.
type Set struct {
	Packs    []*Pack
	ByDetect map[string][]*Pack
}

// Load reads every *.json pack in fsys.
func Load(fsys fs.FS) (*Set, error) {
	names, err := fs.Glob(fsys, "*.json")
	if err != nil {
		return nil, err
	}
	sort.Strings(names)
	set := &Set{ByDetect: map[string][]*Pack{}}
	seen := map[string]bool{}
	for _, name := range names {
		data, err := fs.ReadFile(fsys, name)
		if err != nil {
			return nil, err
		}
		var p Pack
		if err := json.Unmarshal(data, &p); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		if err := p.validate(); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		if seen[p.ID] {
			return nil, fmt.Errorf("%s: duplicate pack id %q", name, p.ID)
		}
		seen[p.ID] = true
		pp := &p
		set.Packs = append(set.Packs, pp)
		for _, d := range p.Detect {
			set.ByDetect[d] = append(set.ByDetect[d], pp)
		}
	}
	return set, nil
}

func (p *Pack) validate() error {
	if p.ID == "" || p.Name == "" {
		return fmt.Errorf("pack needs an id and a name")
	}
	if len(p.Detect) == 0 {
		return fmt.Errorf("pack %q has no detect files", p.ID)
	}
	if len(p.Outputs) == 0 {
		return fmt.Errorf("pack %q has no outputs", p.ID)
	}
	for _, d := range p.Detect {
		if strings.ContainsAny(d, `/\`) {
			return fmt.Errorf("pack %q: detect entry %q must be a plain file name", p.ID, d)
		}
	}
	for _, o := range p.Outputs {
		clean := path.Clean(o.Path)
		if o.Path == "" || clean != o.Path || path.IsAbs(clean) || clean == "." ||
			clean == ".." || strings.HasPrefix(clean, "../") || strings.Contains(o.Path, `\`) {
			return fmt.Errorf("pack %q: output path %q must be a clean relative path inside the project", p.ID, o.Path)
		}
		if len(o.RequireAny) == 0 {
			return fmt.Errorf("pack %q: output %q needs requireAny, so it can never match by name alone", p.ID, o.Path)
		}
	}
	if len(p.Wake) == 0 {
		return fmt.Errorf("pack %q has no wake command", p.ID)
	}
	return nil
}
