package trash

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

type darwinTrash struct{}

func platformTrasher() Trasher { return darwinTrash{} }

// Trash moves the folder into ~/.Trash/Mothball <date>/, so one cleanup shows
// up as one folder in the Trash. Folders on external disks are skipped for now.
func (darwinTrash) Trash(path string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	batch := filepath.Join(home, ".Trash", "Mothball "+stamp(time.Now()))
	if err := os.MkdirAll(batch, 0o700); err != nil {
		return "", err
	}
	dest := uniqueName(batch, label(path))
	if err := os.Rename(path, dest); err != nil {
		if isCrossDevice(err) {
			return "", ErrOtherVolume
		}
		return "", err
	}
	return dest, nil
}

func isEXDEV(err error) bool { return errors.Is(err, syscall.EXDEV) }
