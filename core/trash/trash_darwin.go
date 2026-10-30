package trash

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
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

// Owned reports whether dest is the folder this package trashed from original:
// directly inside a "Mothball <date>" batch folder in ~/.Trash, under the
// name it was given.
func Owned(dest, original string) bool {
	home, err := os.UserHomeDir()
	if err != nil {
		return false
	}
	batch := filepath.Dir(filepath.Clean(dest))
	name := filepath.Base(filepath.Clean(dest))
	want := label(original)
	return filepath.Dir(batch) == filepath.Join(home, ".Trash") &&
		strings.HasPrefix(filepath.Base(batch), "Mothball ") &&
		(name == want || strings.HasPrefix(name, want+" "))
}

// Remove permanently deletes a folder this package trashed, and its batch
// folder once empty. It refuses anything else.
func Remove(dest, original string) error {
	if !Owned(dest, original) {
		return ErrNotOwned
	}
	if err := os.RemoveAll(dest); err != nil {
		return err
	}
	_ = os.Remove(filepath.Dir(dest)) // only succeeds when the batch is empty
	return nil
}
