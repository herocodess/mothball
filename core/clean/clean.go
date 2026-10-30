// Package clean puts verified output away: it picks what is safe from a scan,
// checks each folder again, moves it to the Trash and records the move.
package clean

import (
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/scan"
	"github.com/herocodess/mothball/core/trash"
)

// Checker re-verifies a candidate just before it moves. *scan.Scanner is one.
type Checker interface {
	Recheck(c scan.Candidate, idleDays int, now time.Time) error
}

// Recorder keeps the history of moves. *history.Log is one.
type Recorder interface {
	Append(history.Entry) error
}

// Plan picks the candidates that may be put away: idle long enough and with
// no uncommitted work. The order is kept (largest first from a scan).
func Plan(cs []scan.Candidate, idleDays int) []scan.Candidate {
	var out []scan.Candidate
	for _, c := range cs {
		if c.IdleDays >= idleDays && !c.Dirty {
			out = append(out, c)
		}
	}
	return out
}

// Outcome says what happened to one candidate.
type Outcome struct {
	Candidate scan.Candidate
	Dest      string
	Err       error
}

// Run moves each planned folder, one at a time. A folder that fails its
// re-check is left exactly where it is. If the history cannot be written the
// run stops, because a move nobody recorded cannot be woken later.
func Run(plan []scan.Candidate, idleDays int, chk Checker, tr trash.Trasher, rec Recorder, now time.Time) []Outcome {
	var out []Outcome
	for i, c := range plan {
		if err := chk.Recheck(c, idleDays, now); err != nil {
			out = append(out, Outcome{Candidate: c, Err: &SkipError{Reason: err.Error()}})
			continue
		}
		dest, err := tr.Trash(c.Path)
		if err != nil {
			out = append(out, Outcome{Candidate: c, Err: err})
			continue
		}
		o := Outcome{Candidate: c, Dest: dest}
		if err := rec.Append(history.Entry{
			Time: now, Original: c.Path, Trashed: dest, Project: c.Project,
			Pack: c.Pack, Bytes: c.Bytes, Wake: c.Wake,
		}); err != nil {
			o.Err = &HistoryError{Err: err}
			out = append(out, o)
			for _, rest := range plan[i+1:] {
				out = append(out, Outcome{Candidate: rest, Err: &SkipError{Reason: "stopped: history could not be written"}})
			}
			return out
		}
		out = append(out, o)
	}
	return out
}

// SkipError means a folder was deliberately left alone.
type SkipError struct{ Reason string }

func (e *SkipError) Error() string { return "skipped: " + e.Reason }

// HistoryError means the folder moved but the record of it was not saved.
type HistoryError struct{ Err error }

func (e *HistoryError) Error() string {
	return "moved, but the history could not be saved: " + e.Err.Error()
}
