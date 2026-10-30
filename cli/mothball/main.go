// Command mothball finds build output in idle projects and puts it away.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/herocodess/mothball/core/clean"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/scan"
	"github.com/herocodess/mothball/rules"
)

var version = "0.0.2-dev"

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		usage(stderr)
		return 2
	}
	switch args[0] {
	case "scan":
		return cmdScan(args[1:], stdout, stderr)
	case "clean":
		return cmdClean(args[1:], stdin, stdout, stderr)
	case "wake":
		return cmdWake(args[1:], stdin, stdout, stderr)
	case "empty":
		return cmdEmpty(args[1:], stdin, stdout, stderr)
	case "version", "--version", "-v":
		fmt.Fprintln(stdout, "mothball", version)
		return 0
	case "help", "--help", "-h":
		usage(stdout)
		return 0
	default:
		fmt.Fprintf(stderr, "mothball: unknown command %q\n\n", args[0])
		usage(stderr)
		return 2
	}
}

func usage(w io.Writer) {
	fmt.Fprint(w, `mothball: put idle projects away, get your disk back.

Usage:
  mothball scan [folders...]    show build output in idle projects (reads only)
  mothball clean [folders...]   move that output to the Trash, after asking
  mothball wake [project]       list mothballed projects, or restore one
  mothball empty                permanently empty what Mothball put in the Trash
  mothball version

Options:
  --idle-days N   a project is idle after N days with no commits (default 60)
  --all           scan: also list output in active projects
  --json          scan: print machine-readable results
  --dry-run       clean: show what would move, change nothing
  --yes           clean, wake, empty: do not ask first
  --older-than N  empty: only folders put away N+ days ago (default 7)
`)
}

// scanSetup parses the shared flags and runs a scan.
type scanSetup struct {
	scanner *scan.Scanner
	result  scan.Result
	roots   []string
	base    string
}

func doScan(roots []string, stderr io.Writer) (*scanSetup, int) {
	home, _ := os.UserHomeDir()
	if len(roots) == 0 {
		if home == "" {
			fmt.Fprintln(stderr, "mothball: no folder given and no home folder found")
			return nil, 2
		}
		roots = []string{home}
	}
	packs, err := pack.Load(rules.Files)
	if err != nil {
		fmt.Fprintln(stderr, "mothball: bad rule pack:", err)
		return nil, 1
	}
	s := scan.New(packs, home)
	res := s.Scan(scan.Options{Roots: roots, Home: home, Now: time.Now()})
	base := ""
	if len(roots) == 1 {
		base, _ = filepath.Abs(roots[0])
	}
	return &scanSetup{scanner: s, result: res, roots: roots, base: base}, 0
}

func cmdScan(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("scan", flag.ContinueOnError)
	fs.SetOutput(stderr)
	idleDays := fs.Int("idle-days", 60, "days without commits before a project counts as idle")
	all := fs.Bool("all", false, "also list output in active projects")
	asJSON := fs.Bool("json", false, "print JSON")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	st, code := doScan(fs.Args(), stderr)
	if st == nil {
		return code
	}

	idle := clean.Plan(st.result.Candidates, *idleDays)
	isIdle := map[string]bool{}
	for _, c := range idle {
		isIdle[c.Path] = true
	}
	var active []scan.Candidate
	for _, c := range st.result.Candidates {
		if !isIdle[c.Path] {
			active = append(active, c)
		}
	}
	idleBytes, activeBytes := total(idle), total(active)

	if *asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(map[string]any{
			"idleDays":  *idleDays,
			"projects":  st.result.Projects,
			"idle":      idle,
			"active":    active,
			"idleBytes": idleBytes,
		})
		return 0
	}

	fmt.Fprintf(stdout, "Scanned %d projects in %s\n\n", st.result.Projects, strings.Join(st.roots, ", "))
	if len(idle) > 0 {
		fmt.Fprintf(stdout, "Idle %d+ days, safe to put away:\n", *idleDays)
		table(stdout, idle, st.base)
	} else {
		fmt.Fprintf(stdout, "No build output in projects idle %d+ days.\n", *idleDays)
	}
	if *all && len(active) > 0 {
		fmt.Fprintln(stdout, "\nActive or with uncommitted work, kept:")
		table(stdout, active, st.base)
	}
	fmt.Fprintf(stdout, "\nReclaimable: %s in %s.\n", human(idleBytes), folders(len(idle)))
	fmt.Fprintf(stdout, "Kept: %s in %s from active projects", human(activeBytes), folders(len(active)))
	if !*all && len(active) > 0 {
		fmt.Fprint(stdout, " (--all to list)")
	}
	fmt.Fprintln(stdout, ".")
	if len(idle) > 0 {
		fmt.Fprintln(stdout, "Nothing was changed. Run `mothball clean` to put it away.")
	}
	return 0
}

func table(w io.Writer, cs []scan.Candidate, base string) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "SIZE\tIDLE\t STACK\t PATH\t")
	for _, c := range cs {
		mark := ""
		if c.Dirty {
			mark = " (uncommitted work)"
		}
		fmt.Fprintf(tw, "%s\t%dd\t %s\t %s%s\t\n", human(c.Bytes), c.IdleDays, c.Pack, shortPath(c.Path, base), mark)
	}
	tw.Flush()
}

func shortPath(p, base string) string {
	if base != "" {
		if rel, err := filepath.Rel(base, p); err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return p
}

func total(cs []scan.Candidate) int64 {
	var n int64
	for _, c := range cs {
		n += c.Bytes
	}
	return n
}

func folders(n int) string {
	if n == 1 {
		return "1 folder"
	}
	return fmt.Sprintf("%d folders", n)
}

func human(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}
