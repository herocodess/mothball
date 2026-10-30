package main

import (
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"time"

	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/purge"
	"github.com/herocodess/mothball/core/wake"
	"github.com/herocodess/mothball/rules"
)

func cmdWake(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("wake", flag.ContinueOnError)
	fs.SetOutput(stderr)
	yes := fs.Bool("yes", false, "run the restore commands without asking")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	log, err := openHistory()
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot open the history:", err)
		return 1
	}
	packs, err := pack.Load(rules.Files)
	if err != nil {
		fmt.Fprintln(stderr, "mothball: bad rule pack:", err)
		return 1
	}
	entries, err := log.All()
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot read the history:", err)
		return 1
	}
	projects := wake.Mothballed(entries, packs)

	if fs.NArg() == 0 {
		if len(projects) == 0 {
			fmt.Fprintln(stdout, "No projects are mothballed.")
			return 0
		}
		fmt.Fprintln(stdout, "Mothballed projects:")
		for _, p := range projects {
			mark := ""
			if p.Returned {
				mark = "  you're back, wake it?"
			}
			fmt.Fprintf(stdout, "  %s  %s  since %s%s\n", human(p.Bytes), p.Path, p.Since.Format("2 Jan 2006"), mark)
		}
		fmt.Fprintln(stdout, "\nRestore one with: mothball wake <project folder>")
		return 0
	}

	target, err := filepath.Abs(fs.Arg(0))
	if err != nil {
		fmt.Fprintln(stderr, "mothball:", err)
		return 2
	}
	for _, p := range projects {
		if p.Path != target {
			continue
		}
		fmt.Fprintf(stdout, "Waking %s. It will run, in that folder:\n", p.Path)
		for _, c := range p.Commands {
			fmt.Fprintln(stdout, "  "+c)
		}
		if !*yes && !confirm(stdin, stdout, "Go ahead? [y/N] ") {
			fmt.Fprintln(stdout, "Nothing was run.")
			return 0
		}
		if err := wake.Run(p, log, stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "mothball: wake failed:", err)
			return 1
		}
		fmt.Fprintln(stdout, "Awake.")
		return 0
	}
	fmt.Fprintf(stdout, "%s is not mothballed.\n", target)
	return 0
}

func cmdEmpty(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("empty", flag.ContinueOnError)
	fs.SetOutput(stderr)
	days := fs.Int("older-than", 7, "only folders put away at least this many days ago")
	yes := fs.Bool("yes", false, "do not ask first")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *days < 1 {
		fmt.Fprintln(stderr, "mothball: --older-than must be at least 1")
		return 2
	}
	log, err := openHistory()
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot open the history:", err)
		return 1
	}
	entries, err := log.All()
	if err != nil {
		fmt.Fprintln(stderr, "mothball: cannot read the history:", err)
		return 1
	}
	due := purge.Due(entries, *days, time.Now())
	if len(due) == 0 {
		fmt.Fprintf(stdout, "Nothing Mothball put in the %s is older than %d days.\n", trashName(), *days)
		return 0
	}
	var size int64
	for _, e := range due {
		size += e.Bytes
	}
	prompt := fmt.Sprintf("Permanently empty %s (%s) that Mothball put in the %s? Nothing else in the %s is touched. [y/N] ",
		folders(len(due)), human(size), trashName(), trashName())
	if !*yes && !confirm(stdin, stdout, prompt) {
		fmt.Fprintln(stdout, "Nothing was emptied.")
		return 0
	}
	freed, errs := purge.Run(due, log, time.Now())
	for _, e := range errs {
		fmt.Fprintln(stderr, "  left alone:", e)
	}
	fmt.Fprintf(stdout, "Freed %s.\n", human(freed))
	return 0
}
