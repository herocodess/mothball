// Command mothball finds build output in idle projects and, in later versions,
// puts it away. This version only scans; it never changes anything on disk.
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

	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/scan"
	"github.com/herocodess/mothball/rules"
)

var version = "0.0.1-dev"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		usage(stderr)
		return 2
	}
	switch args[0] {
	case "scan":
		return cmdScan(args[1:], stdout, stderr)
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
  mothball scan [folders...]   show build output in idle projects (reads only)
  mothball version

Scan options:
  --idle-days N   a project is idle after N days with no commits (default 60)
  --all           also list output in active projects
  --json          print machine-readable results
`)
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

	home, _ := os.UserHomeDir()
	roots := fs.Args()
	if len(roots) == 0 {
		if home == "" {
			fmt.Fprintln(stderr, "mothball: no folder given and no home folder found")
			return 2
		}
		roots = []string{home}
	}

	packs, err := pack.Load(rules.Files)
	if err != nil {
		fmt.Fprintln(stderr, "mothball: bad rule pack:", err)
		return 1
	}

	res := scan.New(packs, home).Scan(scan.Options{Roots: roots, Home: home, Now: time.Now()})

	var idle, active []scan.Candidate
	var idleBytes, activeBytes int64
	for _, c := range res.Candidates {
		if c.IdleDays >= *idleDays && !c.Dirty {
			idle = append(idle, c)
			idleBytes += c.Bytes
		} else {
			active = append(active, c)
			activeBytes += c.Bytes
		}
	}

	if *asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(map[string]any{
			"idleDays":  *idleDays,
			"projects":  res.Projects,
			"idle":      idle,
			"active":    active,
			"idleBytes": idleBytes,
		})
		return 0
	}

	base := ""
	if len(roots) == 1 {
		base, _ = filepath.Abs(roots[0])
	}
	fmt.Fprintf(stdout, "Scanned %d projects in %s\n\n", res.Projects, strings.Join(roots, ", "))

	if len(idle) > 0 {
		fmt.Fprintf(stdout, "Idle %d+ days, safe to put away:\n", *idleDays)
		table(stdout, idle, base)
	} else {
		fmt.Fprintf(stdout, "No build output in projects idle %d+ days.\n", *idleDays)
	}
	if *all && len(active) > 0 {
		fmt.Fprintln(stdout, "\nActive or with uncommitted work, kept:")
		table(stdout, active, base)
	}

	fmt.Fprintf(stdout, "\nReclaimable: %s in %s.\n", human(idleBytes), folders(len(idle)))
	fmt.Fprintf(stdout, "Kept: %s in %s from active projects", human(activeBytes), folders(len(active)))
	if !*all && len(active) > 0 {
		fmt.Fprint(stdout, " (--all to list)")
	}
	fmt.Fprintln(stdout, ".")
	fmt.Fprintln(stdout, "Nothing was changed. Cleaning arrives in the next version.")
	return 0
}

func table(w io.Writer, cs []scan.Candidate, base string) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "SIZE\tIDLE\t STACK\t PATH\t")
	for _, c := range cs {
		p := c.Path
		if base != "" {
			if rel, err := filepath.Rel(base, c.Path); err == nil && !strings.HasPrefix(rel, "..") {
				p = rel
			}
		}
		mark := ""
		if c.Dirty {
			mark = " (uncommitted work)"
		}
		fmt.Fprintf(tw, "%s\t%dd\t %s\t %s%s\t\n", human(c.Bytes), c.IdleDays, c.Pack, p, mark)
	}
	tw.Flush()
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
