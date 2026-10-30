package trash

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// windowsTrash sends folders to the Recycle Bin through the shell's own API,
// called from PowerShell so the core needs no extra libraries. The path is
// passed in an environment variable, never spliced into the command.
type windowsTrash struct{}

func platformTrasher() Trasher { return windowsTrash{} }

const recycleScript = `Add-Type -AssemblyName Microsoft.VisualBasic; ` +
	`[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($env:MOTHBALL_PATH, ` +
	`[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, ` +
	`[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)`

func (windowsTrash) Trash(path string) (string, error) {
	if _, err := os.Lstat(path); err != nil {
		return "", err
	}
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", recycleScript)
	cmd.Env = append(os.Environ(), "MOTHBALL_PATH="+path)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("recycle bin: %v: %s", err, strings.TrimSpace(string(out)))
	}
	if _, err := os.Lstat(path); err == nil {
		return "", errors.New("recycle bin: folder is still in place")
	}
	return "Recycle Bin", nil
}

func isEXDEV(error) bool { return false }

// Owned is false on Windows: items in the Recycle Bin cannot yet be found
// again safely, so Mothball never empties them itself.
func Owned(dest, original string) bool { return false }

// Remove always refuses on Windows. See Owned.
func Remove(dest, original string) error { return ErrNotOwned }
