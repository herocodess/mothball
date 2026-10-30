//go:build !darwin && !linux && !windows

package trash

import "errors"

type noTrash struct{}

func platformTrasher() Trasher { return noTrash{} }

func (noTrash) Trash(string) (string, error) {
	return "", errors.New("no Trash support on this system yet")
}

func isEXDEV(error) bool { return false }

func Owned(dest, original string) bool { return false }

func Remove(dest, original string) error { return ErrNotOwned }
