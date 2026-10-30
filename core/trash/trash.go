// Package trash moves folders to the system Trash or Recycle Bin. It never
// deletes anything: emptying the Trash is always the user's own act.
package trash

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ErrOtherVolume means the folder is on a different disk from the Trash this
// package knows about. Mothball skips it rather than copying gigabytes.
var ErrOtherVolume = errors.New("folder is on another disk")

// ErrNotOwned means a path is not something Mothball put in the Trash, so it
// will not be deleted.
var ErrNotOwned = errors.New("not a folder Mothball put in the Trash")

// Trasher moves one folder to the Trash and says where it went.
type Trasher interface {
	Trash(path string) (dest string, err error)
}

// Default returns the Trasher for this operating system.
func Default() Trasher { return platformTrasher() }

// uniqueName returns dir/name, or dir/name 2, dir/name 3... if taken.
func uniqueName(dir, name string) string {
	p := filepath.Join(dir, name)
	for i := 2; ; i++ {
		if _, err := os.Lstat(p); errors.Is(err, os.ErrNotExist) {
			return p
		}
		p = filepath.Join(dir, fmt.Sprintf("%s %d", name, i))
	}
}

// label names a trashed folder so it is recognisable in the Trash:
// "my-app node_modules" rather than a dozen folders all called node_modules.
func label(path string) string {
	parent := filepath.Base(filepath.Dir(path))
	name := filepath.Base(path)
	s := strings.TrimSpace(parent + " " + name)
	return strings.Map(func(r rune) rune {
		if r == '/' || r == '\\' || r == ':' {
			return '-'
		}
		return r
	}, s)
}

func isCrossDevice(err error) bool {
	var le *os.LinkError
	if errors.As(err, &le) {
		return isEXDEV(le.Err)
	}
	return false
}

func stamp(t time.Time) string { return t.Format("2006-01-02 15.04") }
