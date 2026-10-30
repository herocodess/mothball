// Package purge empties folders Mothball itself put in the Trash, once their
// grace period is over. It is opt-in, and it never touches anything else in
// the Trash: each folder must match its own history record exactly.
package purge

import (
	"os"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/trash"
)

// Waiting returns trashed folders still sitting in the Trash, oldest first.
func Waiting(entries []history.Entry) []history.Entry {
	gone := map[string]bool{}
	for _, e := range entries {
		if e.Kind() == history.Purged {
			gone[e.Trashed] = true
		}
	}
	var out []history.Entry
	for _, e := range entries {
		if e.Kind() != history.Trashed || gone[e.Trashed] || e.Trashed == "" {
			continue
		}
		if _, err := os.Lstat(e.Trashed); err != nil {
			continue // already emptied by the user, or restored from the Trash
		}
		out = append(out, e)
	}
	return out
}

// WaitingBytes is how much space emptying Mothball's Trash items would free.
func WaitingBytes(entries []history.Entry) int64 {
	var n int64
	for _, e := range Waiting(entries) {
		n += e.Bytes
	}
	return n
}

// Due returns waiting folders older than graceDays. A graceDays below 1
// means auto-empty is off, and nothing is ever due.
func Due(entries []history.Entry, graceDays int, now time.Time) []history.Entry {
	if graceDays < 1 {
		return nil
	}
	cutoff := now.AddDate(0, 0, -graceDays)
	var out []history.Entry
	for _, e := range Waiting(entries) {
		if e.Time.Before(cutoff) {
			out = append(out, e)
		}
	}
	return out
}

// Run permanently removes each due folder and records it. Folders that no
// longer match their record are left alone.
func Run(due []history.Entry, log interface{ Append(history.Entry) error }, now time.Time) (freed int64, errs []error) {
	for _, e := range due {
		if err := trash.Remove(e.Trashed, e.Original); err != nil {
			errs = append(errs, err)
			continue
		}
		freed += e.Bytes
		if err := log.Append(history.Entry{Event: history.Purged, Time: now, Original: e.Original,
			Trashed: e.Trashed, Project: e.Project, Pack: e.Pack, Bytes: e.Bytes}); err != nil {
			errs = append(errs, err)
		}
	}
	return freed, errs
}
