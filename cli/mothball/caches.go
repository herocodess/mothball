package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/herocodess/mothball/core/caches"
)

func cmdCaches(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	clean := len(args) > 0 && args[0] == "clean"
	if clean {
		args = args[1:]
	}
	fs := flag.NewFlagSet("caches", flag.ContinueOnError)
	fs.SetOutput(stderr)
	dryRun := fs.Bool("dry-run", false, "show what would be cleaned")
	yes := fs.Bool("yes", false, "do not ask first")
	safe := fs.Bool("safe", false, "clean every cache that only costs a re-download")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	home, _ := os.UserHomeDir()
	log, err := openHistory()
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot open the history:", err)
		return 1
	}
	kit := caches.DefaultKit(home, log)
	all := kit.Survey()
	if len(all) == 0 {
		fmt.Fprintln(stdout, "No developer caches found.")
		return 0
	}

	if !clean {
		tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(tw, "SIZE\t ID\t CACHE\t NOTE\t")
		var total int64
		for _, c := range all {
			note := map[caches.Policy]string{caches.Auto: "safe", caches.Ask: "re-download is slow", caches.Report: "shown only"}[c.Policy]
			if c.Blocked != "" {
				note = c.Blocked
			}
			if c.Policy != caches.Report && c.Blocked == "" {
				total += c.Bytes
			}
			fmt.Fprintf(tw, "%s\t %s\t %s\t %s\t\n", human(c.Bytes), c.ID, c.Name, note)
		}
		tw.Flush()
		fmt.Fprintf(stdout, "\nCleanable now: %s.\n", human(total))
		fmt.Fprintln(stdout, "Clean the safe ones with `mothball caches clean --safe`, or name them: `mothball caches clean npm gradle`.")
		return 0
	}

	want := map[string]bool{}
	for _, id := range fs.Args() {
		want[id] = true
	}
	if len(want) == 0 && !*safe {
		fmt.Fprintln(stderr, "mothball: name the caches to clean, or use --safe")
		return 2
	}
	var pick []caches.Cache
	var size int64
	for _, c := range all {
		chosen := want[c.ID] || (*safe && c.Policy == caches.Auto)
		if !chosen {
			continue
		}
		delete(want, c.ID)
		if c.Policy == caches.Report {
			fmt.Fprintf(stdout, "  skipping %s: shown for information only\n", c.Name)
			continue
		}
		if c.Blocked != "" {
			fmt.Fprintf(stdout, "  skipping %s: %s\n", c.Name, c.Blocked)
			continue
		}
		pick = append(pick, c)
		size += c.Bytes
	}
	for id := range want {
		fmt.Fprintf(stdout, "  no cache called %q here (see `mothball caches`)\n", id)
	}
	if len(pick) == 0 {
		fmt.Fprintln(stdout, "Nothing to clean.")
		return 0
	}
	fmt.Fprintln(stdout, "Will clean:")
	for _, c := range pick {
		fmt.Fprintf(stdout, "  %s  %s: %s\n", human(c.Bytes), c.Name, c.How)
	}
	if *dryRun {
		fmt.Fprintln(stdout, "Dry run: nothing was cleaned.")
		return 0
	}
	if !*yes && !confirm(stdin, stdout, fmt.Sprintf("Clean %s of caches? [y/N] ", human(size))) {
		fmt.Fprintln(stdout, "Nothing was cleaned.")
		return 0
	}
	var freed int64
	failed := 0
	for _, c := range pick {
		n, err := kit.Clean(c)
		freed += n
		if err != nil {
			failed++
			fmt.Fprintf(stderr, "  %s: %s\n", c.Name, strings.TrimSpace(err.Error()))
		}
	}
	fmt.Fprintf(stdout, "Freed %s.\n", human(freed))
	if failed > 0 {
		return 1
	}
	return 0
}
