package label

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFor(t *testing.T) {
	sep := string(filepath.Separator)
	p := func(parts ...string) string { return sep + filepath.Join(parts...) }
	cases := []struct {
		name, project, root, want string
	}{
		{"folder inside a monorepo", p("dev", "InviteNaija", "apps", "web"), p("dev", "InviteNaija"), "InviteNaija › apps/web"},
		{"repository root", p("dev", "eventbrdge"), p("dev", "eventbrdge"), "eventbrdge"},
		{"no repository", p("dev", "admin"), "", "admin"},
		{"short name without a repository", p("dev", "kuvori", "web"), "", "kuvori/web"},
		{"root above is not a parent", p("dev", "a"), p("other"), "a"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := For(c.project, c.root); got != c.want {
				t.Errorf("For(%q, %q) = %q, want %q", c.project, c.root, got, c.want)
			}
		})
	}
}

func TestRepoRoot(t *testing.T) {
	dir := t.TempDir()
	repo := filepath.Join(dir, "InviteNaija")
	app := filepath.Join(repo, "apps", "web")
	if err := os.MkdirAll(app, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(repo, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := RepoRoot(app); got != repo {
		t.Fatalf("RepoRoot = %q, want %q", got, repo)
	}
	if got := Project(app); got != "InviteNaija › apps/web" {
		t.Fatalf("Project = %q", got)
	}

	// A worktree or submodule has a .git file instead of a folder.
	sub := filepath.Join(dir, "lib")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sub, ".git"), []byte("gitdir: ../x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := RepoRoot(sub); got != sub {
		t.Fatalf("RepoRoot with .git file = %q, want %q", got, sub)
	}

	if got := RepoRoot(filepath.Join(dir, "nothing")); got != "" && got != dir {
		// The temp folder itself might sit inside a repository on some machines;
		// anything else is wrong.
		t.Fatalf("RepoRoot outside a repository = %q", got)
	}
}
