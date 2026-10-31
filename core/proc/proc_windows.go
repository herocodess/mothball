package proc

import (
	"os/exec"
	"syscall"
)

const createNoWindow = 0x08000000

var getConsoleWindow = syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleWindow")

// HasConsole reports whether this process is attached to a console window,
// as it is when run from a terminal.
func HasConsole() bool {
	if getConsoleWindow.Find() != nil {
		return false
	}
	h, _, _ := getConsoleWindow.Call()
	return h != 0
}

func hide(cmd *exec.Cmd) {
	if HasConsole() {
		return
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
}
