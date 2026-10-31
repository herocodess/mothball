// Package access knows which folders the operating system guards behind a
// privacy permission, and whether Mothball has been given access to them.
// Checking never shows a prompt.
package access

import (
	"path/filepath"
	"strings"
)

// Info is what the app and CLI show about access.
type Info struct {
	// FullDisk is true when every folder can be read without a prompt.
	FullDisk bool `json:"fullDisk"`
	// Skipped lists guarded folders left out of scans because access is missing.
	Skipped []string `json:"skipped,omitempty"`
	// Executable is the program that needs the permission.
	Executable string `json:"executable,omitempty"`
}

// SkipFor returns the guarded folders to leave out when scanning root:
// only those strictly inside it, so a folder the user names is still scanned.
func SkipFor(root string, guarded []string) []string {
	root = filepath.Clean(root)
	var out []string
	for _, g := range guarded {
		g = filepath.Clean(g)
		if g != root && strings.HasPrefix(g, root+string(filepath.Separator)) {
			out = append(out, g)
		}
	}
	return out
}
