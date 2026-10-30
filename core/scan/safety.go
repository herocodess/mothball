package scan

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// neverDescend are folder names the walker never enters. node_modules is still
// found as an output of its project; it is just never searched for projects,
// because every dependency inside it has its own package.json.
var neverDescend = map[string]bool{
	".git":         true,
	".hg":          true,
	".svn":         true,
	"node_modules": true,
	".Trash":       true,
	"$RECYCLE.BIN": true,
}

// homeDenied are locations under the home folder that hold shared caches,
// toolchains or app data. Folders inside them may look like build output
// (Go's module cache has source folders named "build") so they are never
// scanned. Their space is reclaimed, later, through each tool's own command.
var homeDenied = []string{
	"Library",
	"AppData",
	".Trash",
	".cache",
	".local/share",
	".config",
	"go/pkg",
	".cargo",
	".rustup",
	".m2",
	".gradle",
	".pub-cache",
	".npm",
	".yarn",
	".pnpm-store",
	".nvm",
	".pyenv",
	".rbenv",
	".gem",
	".cocoapods",
	".android",
	".swiftpm",
	".dartServer",
	".vscode",
	".cursor",
}

// Guard decides which paths are off limits.
type Guard struct {
	denied []string
}

// NewGuard builds the deny list for a home folder. GOPATH and GOMODCACHE are
// added when set, since they can live outside home.
func NewGuard(home string) *Guard {
	g := &Guard{}
	if home != "" {
		for _, d := range homeDenied {
			g.denied = append(g.denied, normalize(filepath.Join(home, filepath.FromSlash(d))))
		}
	}
	for _, env := range []string{"GOMODCACHE", "GOPATH"} {
		if v := os.Getenv(env); v != "" {
			for _, p := range filepath.SplitList(v) {
				if env == "GOPATH" {
					p = filepath.Join(p, "pkg")
				}
				g.denied = append(g.denied, normalize(p))
			}
		}
	}
	return g
}

// Denied reports whether path is, or is inside, a protected location.
func (g *Guard) Denied(path string) bool {
	p := normalize(path)
	for _, d := range g.denied {
		if p == d || strings.HasPrefix(p, d+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

func normalize(p string) string {
	p = filepath.Clean(p)
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		// Both default to case-insensitive file systems.
		p = strings.ToLower(p)
	}
	return p
}
