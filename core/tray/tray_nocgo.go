//go:build darwin && !cgo

// Package tray: on macOS the menu bar icon needs cgo. Builds without it run
// the service with no icon.
package tray

import "github.com/herocodess/mothball/core/service"

// Available is false: this build has no menu bar support.
func Available() bool { return false }

// Quit does nothing in this build.
func Quit() {}

// Run is never called when Available is false.
func Run(*service.Service, func(), func()) {}
