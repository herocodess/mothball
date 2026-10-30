//go:build !darwin && !linux && !windows

package trash

import "errors"

type noTrash struct{}

func platformTrasher() Trasher { return noTrash{} }

func (noTrash) Trash(string) (string, error) {
	return "", errors.New("no Trash support on this system yet")
}

func isEXDEV(error) bool { return false }
