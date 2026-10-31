// Package config holds Mothball's settings, saved as JSON in its state folder.
package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

// Config is everything the user can set.
type Config struct {
	// Roots are the folders scanned for projects. Empty means the home folder.
	Roots []string `json:"roots"`
	// IdleDays is how long a project goes without commits before it is idle.
	IdleDays int `json:"idleDays"`
	// Autopilot puts idle output away on its own when free space runs low.
	Autopilot bool `json:"autopilot"`
	// TargetFreeGB is the free space autopilot keeps, in gigabytes.
	TargetFreeGB int `json:"targetFreeGB"`
	// AutoEmptyDays empties folders Mothball put in the Trash after this many
	// days. 0 turns it off.
	AutoEmptyDays int `json:"autoEmptyDays"`
	// CheckMinutes is how often free space is checked.
	CheckMinutes int `json:"checkMinutes"`
	// Onboarded is set once the user has seen the first-run screen.
	Onboarded bool `json:"onboarded"`
	// SkipUpdateCheck stops the daily check for new versions on GitHub.
	SkipUpdateCheck bool `json:"skipUpdateCheck"`
	// Theme is the app's appearance: "system" (default), "light" or "dark".
	Theme string `json:"theme,omitempty"`
}

// Default is the starting configuration: everything manual until the user
// turns autopilot on.
func Default() Config {
	return Config{IdleDays: 60, TargetFreeGB: 50, AutoEmptyDays: 0, CheckMinutes: 15}
}

// Validate fixes out-of-range values to safe ones and reports what it changed.
func (c *Config) Validate() []string {
	var fixed []string
	if c.IdleDays < 7 {
		c.IdleDays, fixed = 7, append(fixed, "idleDays raised to 7")
	}
	if c.TargetFreeGB < 1 {
		c.TargetFreeGB, fixed = 1, append(fixed, "targetFreeGB raised to 1")
	}
	if c.AutoEmptyDays < 0 {
		c.AutoEmptyDays, fixed = 0, append(fixed, "autoEmptyDays set to off")
	}
	switch c.Theme {
	case "", "system", "light", "dark":
	default:
		c.Theme, fixed = "system", append(fixed, "theme set to system")
	}
	if c.CheckMinutes < 1 {
		c.CheckMinutes, fixed = 15, append(fixed, "checkMinutes set to 15")
	}
	return fixed
}

func path(dir string) string { return filepath.Join(dir, "config.json") }

// Load reads the config from dir, or returns the default when there is none.
func Load(dir string) (Config, error) {
	c := Default()
	b, err := os.ReadFile(path(dir))
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return Default(), err
	}
	c.Validate()
	return c, nil
}

// Save writes the config atomically: to a temp file, then renamed over.
func Save(dir string, c Config) error {
	c.Validate()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := path(dir) + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path(dir))
}
