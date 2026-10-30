package trash

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// linuxTrash follows the freedesktop.org Trash spec, so file managers show each
// folder with its original location and can restore it.
type linuxTrash struct{}

func platformTrasher() Trasher { return linuxTrash{} }

func (linuxTrash) Trash(path string) (string, error) {
	root := os.Getenv("XDG_DATA_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		root = filepath.Join(home, ".local", "share")
	}
	files := filepath.Join(root, "Trash", "files")
	info := filepath.Join(root, "Trash", "info")
	for _, d := range []string{files, info} {
		if err := os.MkdirAll(d, 0o700); err != nil {
			return "", err
		}
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	dest := uniqueName(files, label(abs))
	name := filepath.Base(dest)
	infoPath := filepath.Join(info, name+".trashinfo")

	// The spec says: write the info file first, then move.
	body := fmt.Sprintf("[Trash Info]\nPath=%s\nDeletionDate=%s\n",
		encodePath(abs), time.Now().Format("2006-01-02T15:04:05"))
	f, err := os.OpenFile(infoPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return "", err
	}
	if _, err := f.WriteString(body); err != nil {
		f.Close()
		os.Remove(infoPath)
		return "", err
	}
	f.Close()

	if err := os.Rename(abs, dest); err != nil {
		os.Remove(infoPath)
		if isCrossDevice(err) {
			return "", ErrOtherVolume
		}
		return "", err
	}
	return dest, nil
}

func encodePath(p string) string {
	parts := strings.Split(p, "/")
	for i, s := range parts {
		parts[i] = url.PathEscape(s)
	}
	return strings.Join(parts, "/")
}

func isEXDEV(err error) bool { return errors.Is(err, syscall.EXDEV) }
