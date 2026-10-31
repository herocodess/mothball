//go:build !windows

package proc

import "os/exec"

// HasConsole is always true outside Windows, where no windows are created.
func HasConsole() bool { return true }

func hide(*exec.Cmd) {}
