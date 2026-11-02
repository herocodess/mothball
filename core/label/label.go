// Package label names projects so people can tell them apart.
//
// A folder name alone is often ambiguous: many repositories have an
// apps/web or an admin folder. The label leads with the repository's own
// name, then the folder inside it, for example "InviteNaija › apps/web".
package label

import (
	"os"
	"path/filepath"
	"strings"
)

// Sep sits between the repository name and the folder inside it.
const Sep = " › "

// Project returns the label for a project folder.
func Project(project string) string {
	project = filepath.Clean(project)
	return For(project, RepoRoot(project))
}

// For builds the label from a project folder and the root of the
// repository it lives in ("" when it is not in one).
func For(project, root string) string {
	project = filepath.Clean(project)
	base := filepath.Base(project)
	if root != "" {
		root = filepath.Clean(root)
		if root != project {
			if rel, err := filepath.Rel(root, project); err == nil && rel != "." && !strings.HasPrefix(rel, "..") {
				return filepath.Base(root) + Sep + filepath.ToSlash(rel)
			}
		}
		return base
	}
	// Not in a repository: a very short folder name (web, api, app) says
	// little on its own, so add its parent.
	if len(base) <= 3 {
		if parent := filepath.Base(filepath.Dir(project)); parent != "." && parent != string(filepath.Separator) && parent != "" {
			return parent + "/" + base
		}
	}
	return base
}

// RepoRoot finds the nearest folder at or above dir that holds a .git
// folder or file (worktrees and submodules use a file). It stops at the
// home folder and returns "" when there is no repository.
func RepoRoot(dir string) string {
	home, _ := os.UserHomeDir()
	if home != "" {
		home = filepath.Clean(home)
	}
	d := filepath.Clean(dir)
	for {
		if _, err := os.Lstat(filepath.Join(d, ".git")); err == nil {
			return d
		}
		if d == home {
			return ""
		}
		parent := filepath.Dir(d)
		if parent == d {
			return ""
		}
		d = parent
	}
}
