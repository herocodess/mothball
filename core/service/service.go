// Package service is Mothball's background process: it watches free space,
// runs autopilot, and answers the desktop app and CLI over a local API.
// Every action goes through the same core packages as the CLI.
package service

import (
	"errors"
	"os"
	"sort"
	"sync"
	"time"

	"github.com/herocodess/mothball/core/clean"
	"github.com/herocodess/mothball/core/config"
	"github.com/herocodess/mothball/core/disk"
	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/purge"
	"github.com/herocodess/mothball/core/scan"
	"github.com/herocodess/mothball/core/trash"
	"github.com/herocodess/mothball/core/wake"
)

// Service holds Mothball's state while it runs.
type Service struct {
	Dir   string // state folder: config, history, service file
	Home  string
	Packs *pack.Set

	// Swappable for tests.
	Free  func(path string) (uint64, error)
	Trash trash.Trasher
	Now   func() time.Time

	mu       sync.Mutex // one scan, clean or wake at a time
	log      *history.Log
	lastScan *ScanSummary

	evMu   sync.Mutex
	events []Event
}

// ErrNotMothballed means the project has nothing put away.
var ErrNotMothballed = errors.New("project is not mothballed")

// ScanSummary is the result of the latest scan.
type ScanSummary struct {
	At         time.Time        `json:"at"`
	Projects   int              `json:"projects"`
	Idle       []scan.Candidate `json:"idle"`
	IdleBytes  int64            `json:"idleBytes"`
	Active     []scan.Candidate `json:"active"`
	ActiveSize int64            `json:"activeBytes"`
}

// Event is something worth telling the user about.
type Event struct {
	At      time.Time `json:"at"`
	Kind    string    `json:"kind"` // autopilot, emptied, error
	Message string    `json:"message"`
	Bytes   int64     `json:"bytes,omitempty"`
}

// New makes a service using the real disk, Trash and clock.
func New(dir, home string, packs *pack.Set) (*Service, error) {
	log, err := history.Open(dir)
	if err != nil {
		return nil, err
	}
	return &Service{Dir: dir, Home: home, Packs: packs, Free: disk.Free,
		Trash: trash.Default(), Now: time.Now, log: log}, nil
}

// Config returns the saved settings.
func (s *Service) Config() (config.Config, error) { return config.Load(s.Dir) }

// SetConfig saves new settings.
func (s *Service) SetConfig(c config.Config) (config.Config, error) {
	c.Validate()
	return c, config.Save(s.Dir, c)
}

func (s *Service) roots(c config.Config) []string {
	if len(c.Roots) > 0 {
		return c.Roots
	}
	return []string{s.Home}
}

func (s *Service) scanner() *scan.Scanner { return scan.New(s.Packs, s.Home) }

// Scan runs a fresh scan and remembers it.
func (s *Service) Scan() (*ScanSummary, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.scanLocked()
}

func (s *Service) scanLocked() (*ScanSummary, error) {
	c, err := s.Config()
	if err != nil {
		return nil, err
	}
	res := s.scanner().Scan(scan.Options{Roots: s.roots(c), Home: s.Home, Now: s.Now()})
	sum := &ScanSummary{At: s.Now(), Projects: res.Projects}
	sum.Idle = clean.Plan(res.Candidates, c.IdleDays)
	idle := map[string]bool{}
	for _, x := range sum.Idle {
		idle[x.Path] = true
		sum.IdleBytes += x.Bytes
	}
	for _, x := range res.Candidates {
		if !idle[x.Path] {
			sum.Active = append(sum.Active, x)
			sum.ActiveSize += x.Bytes
		}
	}
	s.lastScan = sum
	return sum, nil
}

// Status is what the menu bar and app show at a glance.
type Status struct {
	FreeBytes    uint64         `json:"freeBytes"`
	TargetBytes  uint64         `json:"targetBytes"`
	WaitingBytes int64          `json:"waitingBytes"` // in the Trash from Mothball, not yet emptied
	Config       config.Config  `json:"config"`
	LastScan     *ScanSummary   `json:"lastScan,omitempty"`
	Mothballed   []wake.Project `json:"mothballed"`
	Events       []Event        `json:"events"`
}

// Status reports the current state without scanning.
func (s *Service) Status() (Status, error) {
	c, err := s.Config()
	if err != nil {
		return Status{}, err
	}
	free, _ := s.Free(s.Home)
	entries, err := s.log.All()
	if err != nil {
		return Status{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return Status{
		FreeBytes:    free,
		TargetBytes:  uint64(c.TargetFreeGB) << 30,
		WaitingBytes: purge.WaitingBytes(entries),
		Config:       c,
		LastScan:     s.lastScan,
		Mothballed:   wake.Mothballed(entries, s.Packs),
		Events:       s.recentEvents(),
	}, nil
}

// Clean puts away the given idle folders, or every idle folder when paths is
// empty. Each one is re-checked before it moves.
func (s *Service) Clean(paths []string) ([]clean.Outcome, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, err := s.Config()
	if err != nil {
		return nil, err
	}
	sum, err := s.scanLocked()
	if err != nil {
		return nil, err
	}
	plan := sum.Idle
	if len(paths) > 0 {
		want := map[string]bool{}
		for _, p := range paths {
			want[p] = true
		}
		plan = nil
		for _, x := range sum.Idle {
			if want[x.Path] {
				plan = append(plan, x)
			}
		}
	}
	out := clean.Run(plan, c.IdleDays, s.scanner(), s.Trash, s.log, s.Now())
	_, _ = s.scanLocked()
	return out, nil
}

// Wake restores one mothballed project.
func (s *Service) Wake(project string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	entries, err := s.log.All()
	if err != nil {
		return err
	}
	for _, p := range wake.Mothballed(entries, s.Packs) {
		if p.Path == project {
			return wake.Run(p, s.log, os.Stdout, os.Stderr)
		}
	}
	return ErrNotMothballed
}

// Tick is one autopilot step: empty what is due, then, if free space is
// below target, put away the longest-idle output until the shortfall is
// covered. Space already waiting in the Trash for auto-empty counts as
// covered, so autopilot never keeps trashing more while it waits.
func (s *Service) Tick() {
	c, err := s.Config()
	if err != nil {
		s.event("error", "could not read settings: "+err.Error(), 0)
		return
	}
	entries, err := s.log.All()
	if err != nil {
		s.event("error", "could not read history: "+err.Error(), 0)
		return
	}
	if due := purge.Due(entries, c.AutoEmptyDays, s.Now()); len(due) > 0 {
		freed, errs := purge.Run(due, s.log, s.Now())
		if freed > 0 {
			s.event("emptied", "Emptied folders Mothball put in the Trash", freed)
		}
		for _, e := range errs {
			s.event("error", e.Error(), 0)
		}
		entries, _ = s.log.All()
	}
	if !c.Autopilot {
		return
	}
	free, err := s.Free(s.Home)
	if err != nil {
		s.event("error", "could not read free space: "+err.Error(), 0)
		return
	}
	target := uint64(c.TargetFreeGB) << 30
	var waiting uint64
	if c.AutoEmptyDays > 0 {
		waiting = uint64(purge.WaitingBytes(entries))
	}
	if free+waiting >= target {
		return
	}
	need := int64(target - free - waiting)

	s.mu.Lock()
	defer s.mu.Unlock()
	sum, err := s.scanLocked()
	if err != nil {
		s.event("error", "scan failed: "+err.Error(), 0)
		return
	}
	plan := append([]scan.Candidate(nil), sum.Idle...)
	sort.SliceStable(plan, func(i, j int) bool { return plan[i].IdleDays > plan[j].IdleDays })
	var pick []scan.Candidate
	var picked int64
	for _, x := range plan {
		if picked >= need {
			break
		}
		pick = append(pick, x)
		picked += x.Bytes
	}
	if len(pick) == 0 {
		s.event("autopilot", "Free space is below target, but no idle projects have build output to put away", 0)
		return
	}
	var moved int64
	for _, o := range clean.Run(pick, c.IdleDays, s.scanner(), s.Trash, s.log, s.Now()) {
		if o.Err == nil {
			moved += o.Candidate.Bytes
		}
	}
	msg := "Put away build output from idle projects"
	if c.AutoEmptyDays > 0 {
		msg += "; it is emptied from the Trash after the grace period"
	} else {
		msg += "; empty the Trash to free the space"
	}
	s.event("autopilot", msg, moved)
	_, _ = s.scanLocked()
}

func (s *Service) recentEvents() []Event {
	s.evMu.Lock()
	defer s.evMu.Unlock()
	return append([]Event(nil), s.events...)
}

func (s *Service) event(kind, msg string, bytes int64) {
	s.evMu.Lock()
	defer s.evMu.Unlock()
	s.events = append(s.events, Event{At: s.Now(), Kind: kind, Message: msg, Bytes: bytes})
	if len(s.events) > 50 {
		s.events = s.events[len(s.events)-50:]
	}
}

// Run checks on a schedule until stop is closed. A full scan happens only when
// autopilot needs one, plus a refresh every few hours for the app's numbers,
// so an idle service costs almost nothing.
func (s *Service) Run(stop <-chan struct{}) {
	lastRefresh := time.Time{}
	for {
		s.Tick()
		if s.Now().Sub(lastRefresh) > 6*time.Hour {
			_, _ = s.Scan()
			lastRefresh = s.Now()
		}
		c, _ := s.Config()
		select {
		case <-stop:
			return
		case <-time.After(time.Duration(c.CheckMinutes) * time.Minute):
		}
	}
}
