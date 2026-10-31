// Package proc starts child processes the way Mothball needs on every
// system. On Windows the background service has no console, and every
// console program it starts (git, powershell, schtasks, npm) would otherwise
// flash a black window on screen; Command keeps those hidden. From a
// terminal, children behave normally and share its console.
package proc

import (
	"context"
	"os/exec"
)

// Command is exec.Command, with console windows hidden when Mothball runs
// without a console of its own.
func Command(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	hide(cmd)
	return cmd
}

// CommandContext is exec.CommandContext, with the same window handling.
func CommandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	hide(cmd)
	return cmd
}
