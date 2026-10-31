package access

import (
	"os"
	"path/filepath"
)

// Guarded are the home folders macOS protects with a privacy prompt.
func Guarded(home string) []string {
	var out []string
	for _, d := range []string{"Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"} {
		out = append(out, filepath.Join(home, d))
	}
	return out
}

// HasFullDisk reports whether this process has Full Disk Access. It tries to
// open the privacy database, which only that permission allows, and which
// never triggers a prompt.
func HasFullDisk(home string) bool {
	f, err := os.Open(filepath.Join(home, "Library", "Application Support", "com.apple.TCC", "TCC.db"))
	if err == nil {
		f.Close()
		return true
	}
	// Any failure, permission or otherwise, counts as no access, so Mothball
	// stays out of guarded folders rather than risk a surprise prompt.
	return false
}
