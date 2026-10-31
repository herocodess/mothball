//go:build !darwin

package access

// Guarded is empty: only macOS guards home folders behind prompts.
func Guarded(string) []string { return nil }

// HasFullDisk is always true outside macOS.
func HasFullDisk(string) bool { return true }
