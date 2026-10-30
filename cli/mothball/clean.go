package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/herocodess/mothball/core/clean"
	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/trash"
)

func cmdClean(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("clean", flag.ContinueOnError)
	fs.SetOutput(stderr)
	idleDays := fs.Int("idle-days", 60, "days without commits before a project counts as idle")
	dryRun := fs.Bool("dry-run", false, "show what would move, change nothing")
	yes := fs.Bool("yes", false, "do not ask before moving")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *idleDays < 1 {
		fmt.Fprintln(stderr, "mothball: --idle-days must be at least 1")
		return 2
	}

	st, code := doScan(fs.Args(), stderr)
	if st == nil {
		return code
	}
	plan := clean.Plan(st.result.Candidates, *idleDays)
	if len(plan) == 0 {
		fmt.Fprintf(stdout, "Nothing to put away: no build output in projects idle %d+ days.\n", *idleDays)
		return 0
	}

	fmt.Fprintf(stdout, "Build output in projects idle %d+ days:\n", *idleDays)
	table(stdout, plan, st.base)
	size := total(plan)
	fmt.Fprintf(stdout, "\nTotal: %s in %s.\n", human(size), folders(len(plan)))

	if *dryRun {
		fmt.Fprintln(stdout, "Dry run: nothing was moved.")
		return 0
	}
	if !*yes && !confirm(stdin, stdout, fmt.Sprintf("Move %s (%s) to the %s? [y/N] ", folders(len(plan)), human(size), trashName())) {
		fmt.Fprintln(stdout, "Nothing was moved.")
		return 0
	}

	dir := os.Getenv("MOTHBALL_STATE_DIR")
	if dir == "" {
		var err error
		if dir, err = history.DefaultDir(); err != nil {
			fmt.Fprintln(stderr, "mothball: cannot find a place for the history:", err)
			return 1
		}
	}
	log, err := history.Open(dir)
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot open the history:", err)
		return 1
	}

	outcomes := clean.Run(plan, *idleDays, st.scanner, trash.Default(), log, time.Now())

	var moved, skipped, failed int
	var freed int64
	for _, o := range outcomes {
		var skip *clean.SkipError
		var hist *clean.HistoryError
		switch {
		case o.Err == nil:
			moved++
			freed += o.Candidate.Bytes
		case errors.As(o.Err, &skip):
			skipped++
			fmt.Fprintf(stdout, "  left alone  %s (%s)\n", shortPath(o.Candidate.Path, st.base), skip.Reason)
		case errors.As(o.Err, &hist):
			moved++
			freed += o.Candidate.Bytes
			fmt.Fprintf(stderr, "mothball: %s: %v\n", o.Candidate.Path, o.Err)
		case errors.Is(o.Err, trash.ErrOtherVolume):
			skipped++
			fmt.Fprintf(stdout, "  left alone  %s (on another disk, not supported yet)\n", shortPath(o.Candidate.Path, st.base))
		default:
			failed++
			fmt.Fprintf(stderr, "  failed      %s: %v\n", shortPath(o.Candidate.Path, st.base), o.Err)
		}
	}

	fmt.Fprintf(stdout, "\nMoved %s (%s) to the %s.", folders(moved), human(freed), trashName())
	if skipped > 0 {
		fmt.Fprintf(stdout, " Left %d alone.", skipped)
	}
	fmt.Fprintln(stdout)
	if moved > 0 {
		fmt.Fprintf(stdout, "The space comes back when you empty the %s. Each project can be restored with its usual install command.\n", trashName())
	}
	if failed > 0 {
		return 1
	}
	return 0
}

func confirm(in io.Reader, out io.Writer, prompt string) bool {
	fmt.Fprint(out, prompt)
	line, _ := bufio.NewReader(in).ReadString('\n')
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "y", "yes":
		return true
	}
	return false
}

func trashName() string {
	if runtime.GOOS == "windows" {
		return "Recycle Bin"
	}
	return "Trash"
}
