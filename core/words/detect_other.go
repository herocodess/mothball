//go:build !windows

package words

import (
	"os"
	"os/exec"
	"regexp"
	"runtime"
)

var firstQuoted = regexp.MustCompile(`"([^"]+)"`)

func detect() string {
	for _, k := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := os.Getenv(k); v != "" && v != "C" && v != "POSIX" {
			return v
		}
	}
	if runtime.GOOS == "darwin" {
		// The service starts at login without LANG; ask macOS for the
		// user's preferred languages.
		out, err := exec.Command("/usr/bin/defaults", "read", "-g", "AppleLanguages").Output()
		if err == nil {
			if m := firstQuoted.FindSubmatch(out); m != nil {
				return string(m[1])
			}
			// One-word codes are printed without quotes.
			return firstWord(string(out))
		}
	}
	return ""
}

func firstWord(s string) string {
	start := -1
	for i, r := range s {
		letter := r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z'
		if letter && start < 0 {
			start = i
		}
		if !letter && r != '-' && r != '_' && start >= 0 {
			return s[start:i]
		}
	}
	if start >= 0 {
		return s[start:]
	}
	return ""
}
