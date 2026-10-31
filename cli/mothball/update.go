package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/herocodess/mothball/core/update"
)

// cmdUpdate checks for a newer release and says how to get it for the way
// this copy was installed. The app updates itself; the CLI on its own is
// updated by whatever installed it.
func cmdUpdate(stdout, stderr io.Writer) int {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	u := update.New(version, os.TempDir())
	st, err := u.Check(ctx)
	if err != nil {
		fmt.Fprintln(stderr, "mothball: couldn't check for updates:", err)
		return 1
	}
	if !st.Available {
		fmt.Fprintf(stdout, "Mothball %s is the latest version.\n", version)
		return 0
	}
	fmt.Fprintf(stdout, "Mothball %s is available (you have %s).\n", st.Latest, version)
	if st.Required && st.Message != "" {
		fmt.Fprintln(stdout, "This update is required:", st.Message)
	}
	exe, _ := os.Executable()
	exe, _ = filepath.EvalSymlinks(exe)
	switch {
	case u.App != "":
		fmt.Fprintln(stdout, "Open Mothball and click Update, or download it from:")
		fmt.Fprintln(stdout, " ", st.NotesURL)
	case strings.Contains(exe, "/Cellar/") || strings.Contains(exe, "/Caskroom/"):
		fmt.Fprintln(stdout, "Update with:\n  brew upgrade mothball")
	case strings.Contains(exe, string(filepath.Separator)+"go"+string(filepath.Separator)+"bin"):
		fmt.Fprintln(stdout, "Update with:\n  go install github.com/herocodess/mothball/cli/mothball@latest")
	default:
		name := fmt.Sprintf("mothball-%s-%s-%s", st.Latest, runtime.GOOS, runtime.GOARCH)
		switch runtime.GOOS {
		case "darwin":
			name = fmt.Sprintf("mothball-%s-macos-universal", st.Latest)
		case "windows":
			name += ".exe"
		}
		fmt.Fprintf(stdout, "Download %s from:\n  %s\n", name, st.NotesURL)
	}
	if st.Required {
		return 3
	}
	return 0
}
